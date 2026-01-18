defmodule Watson.Extractors.AstExtractor do
  @moduledoc """
  Phase 1: AST Pass extraction.

  Parses all .ex and .exs files and extracts:
  - modules
  - functions/macros
  - alias/import/require/use
  - struct definitions
  - remote calls (Mod.fun)
  - unresolved local calls (fun)
  """

  alias Watson.Records.{
    ModuleDef,
    FunctionDef,
    CallRef,
    AliasRef,
    StructDef
  }

  @type extraction_result :: %{
          modules: [ModuleDef.t()],
          functions: [FunctionDef.t()],
          calls: [CallRef.t()],
          aliases: [AliasRef.t()],
          structs: [StructDef.t()]
        }

  @doc """
  Extracts all AST-level information from the given files.
  """
  @spec extract_files([String.t()]) :: extraction_result()
  def extract_files(files) do
    results =
      files
      |> Task.async_stream(&extract_file/1, ordered: false, timeout: 30_000)
      |> Enum.reduce(empty_result(), fn
        {:ok, result}, acc -> merge_results(acc, result)
        {:exit, _reason}, acc -> acc
      end)

    # Sort for determinism
    %{
      modules: Enum.sort_by(results.modules, & &1.module),
      functions: Enum.sort_by(results.functions, &{&1.module, &1.name, &1.arity}),
      calls: Enum.sort_by(results.calls, &{&1.file, &1.span.line}),
      aliases: Enum.sort_by(results.aliases, &{&1.file, &1.span.line}),
      structs: Enum.sort_by(results.structs, & &1.module)
    }
  end

  @doc """
  Extracts AST information from a single file.
  """
  @spec extract_file(String.t()) :: extraction_result()
  def extract_file(file) do
    with {:ok, content} <- File.read(file),
         {:ok, ast} <- parse_string(content, file) do
      extract_ast(ast, file)
    else
      {:error, _reason} -> empty_result()
    end
  end

  defp parse_string(content, file) do
    Code.string_to_quoted(content,
      file: file,
      columns: true,
      token_metadata: true
    )
  rescue
    _ -> {:error, :parse_error}
  end

  defp empty_result do
    %{
      modules: [],
      functions: [],
      calls: [],
      aliases: [],
      structs: []
    }
  end

  defp merge_results(acc, result) do
    %{
      modules: acc.modules ++ result.modules,
      functions: acc.functions ++ result.functions,
      calls: acc.calls ++ result.calls,
      aliases: acc.aliases ++ result.aliases,
      structs: acc.structs ++ result.structs
    }
  end

  # Main AST extraction
  defp extract_ast(ast, file) do
    context = %{
      file: file,
      current_module: nil,
      current_function: nil,
      aliases_map: %{}
    }

    {_ast, {_context, result}} =
      Macro.prewalk(ast, {context, empty_result()}, &visit_node/2)

    # Also do a post-walk to find end lines for modules
    result = find_module_end_lines(ast, result, file)

    result
  end

  # Visit defmodule
  defp visit_node(
         {:defmodule, meta, [{:__aliases__, _, module_parts} | _]} = node,
         {context, result}
       ) do
    module_name = module_to_string(module_parts)
    line = Keyword.get(meta, :line, 1)

    module_def = ModuleDef.new(module_name, context.file, line, nil)

    new_context = %{context | current_module: module_name}
    new_result = %{result | modules: [module_def | result.modules]}

    {node, {new_context, new_result}}
  end

  # Visit def/defp/defmacro/defmacrop
  defp visit_node({def_type, meta, [{name, _args_meta, args} | _]} = node, {context, result})
       when def_type in [:def, :defp, :defmacro, :defmacrop] and is_atom(name) do
    if context.current_module do
      line = Keyword.get(meta, :line, 1)
      end_line = Keyword.get(meta, :end, []) |> Keyword.get(:line, line)
      arity = get_arity(args)
      visibility = if def_type in [:def, :defmacro], do: :public, else: :private
      is_macro = def_type in [:defmacro, :defmacrop]

      func_def =
        FunctionDef.new(
          context.current_module,
          name,
          arity,
          visibility,
          line,
          end_line,
          context.file,
          is_macro: is_macro
        )

      mfa = "#{context.current_module}.#{name}/#{arity}"
      new_context = %{context | current_function: mfa}
      new_result = %{result | functions: [func_def | result.functions]}

      {node, {new_context, new_result}}
    else
      {node, {context, result}}
    end
  end

  # Visit alias
  defp visit_node({:alias, meta, [{:__aliases__, _, parts} | opts]} = node, {context, result}) do
    if context.current_module do
      target = module_to_string(parts)
      line = Keyword.get(meta, :line, 1)

      as_alias = extract_as_option(opts)

      alias_ref =
        AliasRef.new(:alias, context.current_module, target, context.file, line, as: as_alias)

      new_result = %{result | aliases: [alias_ref | result.aliases]}
      {node, {context, new_result}}
    else
      {node, {context, result}}
    end
  end

  # Visit import
  defp visit_node({:import, meta, [{:__aliases__, _, parts} | opts]} = node, {context, result}) do
    if context.current_module do
      target = module_to_string(parts)
      line = Keyword.get(meta, :line, 1)

      only = extract_only_option(opts)
      except = extract_except_option(opts)

      alias_ref =
        AliasRef.new(:import, context.current_module, target, context.file, line,
          only: only,
          except: except
        )

      new_result = %{result | aliases: [alias_ref | result.aliases]}
      {node, {context, new_result}}
    else
      {node, {context, result}}
    end
  end

  # Visit require
  defp visit_node({:require, meta, [{:__aliases__, _, parts} | opts]} = node, {context, result}) do
    if context.current_module do
      target = module_to_string(parts)
      line = Keyword.get(meta, :line, 1)
      as_alias = extract_as_option(opts)

      alias_ref =
        AliasRef.new(:require, context.current_module, target, context.file, line, as: as_alias)

      new_result = %{result | aliases: [alias_ref | result.aliases]}
      {node, {context, new_result}}
    else
      {node, {context, result}}
    end
  end

  # Visit use
  defp visit_node({:use, meta, [{:__aliases__, _, parts} | _opts]} = node, {context, result}) do
    if context.current_module do
      target = module_to_string(parts)
      line = Keyword.get(meta, :line, 1)

      alias_ref = AliasRef.new(:use, context.current_module, target, context.file, line)

      new_result = %{result | aliases: [alias_ref | result.aliases]}
      {node, {context, new_result}}
    else
      {node, {context, result}}
    end
  end

  # Visit defstruct
  defp visit_node({:defstruct, meta, [fields]} = node, {context, result}) when is_list(fields) do
    if context.current_module do
      line = Keyword.get(meta, :line, 1)

      struct_fields =
        Enum.map(fields, fn
          {name, default} -> StructDef.field(name, default)
          name when is_atom(name) -> StructDef.field(name, nil)
        end)

      struct_def = StructDef.new(context.current_module, context.file, line, struct_fields)
      new_result = %{result | structs: [struct_def | result.structs]}
      {node, {context, new_result}}
    else
      {node, {context, result}}
    end
  end

  # Visit remote call (Mod.fun(args))
  defp visit_node(
         {{:., meta, [{:__aliases__, _, module_parts}, func_name]}, _call_meta, args} = node,
         {context, result}
       )
       when is_atom(func_name) and is_list(args) do
    if context.current_function do
      callee_module = module_to_string(module_parts)
      arity = length(args)
      line = Keyword.get(meta, :line, 1)

      call_ref =
        CallRef.new(
          context.current_function,
          "#{callee_module}.#{func_name}/#{arity}",
          context.file,
          line
        )

      new_result = %{result | calls: [call_ref | result.calls]}
      {node, {context, new_result}}
    else
      {node, {context, result}}
    end
  end

  # Visit local call (fun(args)) - unresolved
  defp visit_node({func_name, meta, args} = node, {context, result})
       when is_atom(func_name) and is_list(args) and
              func_name not in [
                :def,
                :defp,
                :defmacro,
                :defmacrop,
                :defmodule,
                :alias,
                :import,
                :require,
                :use,
                :defstruct,
                :@,
                :fn,
                :case,
                :cond,
                :if,
                :unless,
                :with,
                :for,
                :receive,
                :try,
                :quote,
                :unquote,
                :__block__,
                :|>,
                :.,
                :when,
                :->,
                :=,
                :==,
                :!=,
                :===,
                :!==,
                :<,
                :>,
                :<=,
                :>=,
                :+,
                :-,
                :*,
                :/,
                :++,
                :--,
                :<>,
                :and,
                :or,
                :not,
                :in,
                :do,
                :end,
                :else,
                :after,
                :catch,
                :rescue,
                :&,
                :"::"
              ] do
    if context.current_function do
      line = Keyword.get(meta, :line, 1)

      # Record as unresolved local call (callee: nil per spec)
      call_ref =
        CallRef.new(
          context.current_function,
          nil,
          context.file,
          line
        )

      new_result = %{result | calls: [call_ref | result.calls]}
      {node, {context, new_result}}
    else
      {node, {context, result}}
    end
  end

  # Default case - continue traversal
  defp visit_node(node, acc), do: {node, acc}

  # Helper functions

  defp module_to_string(parts) when is_list(parts) do
    parts
    |> Enum.map(&to_string/1)
    |> Enum.join(".")
  end

  defp get_arity(nil), do: 0
  defp get_arity(args) when is_list(args), do: length(args)
  defp get_arity(_), do: 0

  defp extract_as_option(opts) when is_list(opts) do
    case Keyword.get(opts, :as) do
      {:__aliases__, _, parts} -> module_to_string(parts)
      nil -> nil
      _ -> nil
    end
  end

  defp extract_as_option(_), do: nil

  defp extract_only_option(opts) when is_list(opts) do
    # opts may be [[only: [...]]] or [only: [...]]
    flat_opts = flatten_opts(opts)

    case Keyword.get(flat_opts, :only) do
      list when is_list(list) ->
        Enum.map(list, fn
          {name, arity} -> {name, arity}
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)

      _ ->
        nil
    end
  end

  defp extract_only_option(_), do: nil

  defp extract_except_option(opts) when is_list(opts) do
    flat_opts = flatten_opts(opts)

    case Keyword.get(flat_opts, :except) do
      list when is_list(list) ->
        Enum.map(list, fn
          {name, arity} -> {name, arity}
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)

      _ ->
        nil
    end
  end

  defp extract_except_option(_), do: nil

  defp flatten_opts([first | _] = opts) when is_list(first) do
    if Keyword.keyword?(first), do: first, else: opts
  end

  defp flatten_opts(opts), do: opts

  # Find module end lines by looking at the block structure
  defp find_module_end_lines(ast, result, file) do
    module_ends = find_module_blocks(ast, file)

    updated_modules =
      Enum.map(result.modules, fn module_def ->
        case Map.get(module_ends, module_def.module) do
          nil ->
            module_def

          end_line ->
            %{module_def | span: %{module_def.span | end: %{line: end_line}}}
        end
      end)

    %{result | modules: updated_modules}
  end

  defp find_module_blocks(ast, _file) do
    {_ast, ends} = Macro.prewalk(ast, %{}, &collect_module_ends/2)
    ends
  end

  defp collect_module_ends(
         {:defmodule, meta, [{:__aliases__, _, parts}, [do: _block]]} = node,
         acc
       ) do
    module_name = module_to_string(parts)

    end_line =
      case Keyword.get(meta, :end) do
        [line: line] -> line
        _ -> nil
      end

    if end_line do
      {node, Map.put(acc, module_name, end_line)}
    else
      {node, acc}
    end
  end

  defp collect_module_ends(node, acc), do: {node, acc}
end
