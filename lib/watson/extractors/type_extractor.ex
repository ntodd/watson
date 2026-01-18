defmodule Watson.Extractors.TypeExtractor do
  @moduledoc """
  Extracts type annotations from Elixir source files.

  Extracts:
  - @spec definitions
  - @type definitions
  - @typep definitions
  - @opaque definitions
  - @callback definitions
  - @macrocallback definitions
  """

  alias Watson.Records.{TypeSpec, TypeDef}

  @type extraction_result :: %{
          specs: [TypeSpec.t()],
          types: [TypeDef.t()]
        }

  @doc """
  Extracts type annotations from the given files.
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
      specs: Enum.sort_by(results.specs, &{&1.module, &1.name, &1.arity}),
      types: Enum.sort_by(results.types, &{&1.module, &1.name})
    }
  end

  @doc """
  Extracts type annotations from a single file.
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
    %{specs: [], types: []}
  end

  defp merge_results(acc, result) do
    %{
      specs: acc.specs ++ result.specs,
      types: acc.types ++ result.types
    }
  end

  # Main AST extraction
  defp extract_ast(ast, file) do
    context = %{
      file: file,
      current_module: nil
    }

    {_ast, {_context, result}} =
      Macro.prewalk(ast, {context, empty_result()}, &visit_node/2)

    result
  end

  # Visit defmodule
  defp visit_node(
         {:defmodule, _meta, [{:__aliases__, _, module_parts} | _]} = node,
         {context, result}
       ) do
    module_name = module_to_string(module_parts)
    new_context = %{context | current_module: module_name}
    {node, {new_context, result}}
  end

  # Visit @spec
  defp visit_node(
         {:@, meta, [{:spec, _, [{:"::", _, [signature, return_type]}]}]} = node,
         {context, result}
       ) do
    if context.current_module do
      line = Keyword.get(meta, :line, 1)
      {name, arity, params} = extract_function_signature(signature)
      return_str = type_to_string(return_type)

      spec =
        TypeSpec.new(
          context.current_module,
          name,
          arity,
          params,
          return_str,
          context.file,
          line
        )

      new_result = %{result | specs: [spec | result.specs]}
      {node, {context, new_result}}
    else
      {node, {context, result}}
    end
  end

  # Visit @type, @typep, @opaque
  defp visit_node(
         {:@, meta, [{kind, _, [{:"::", _, [name_def, type_def]}]}]} = node,
         {context, result}
       )
       when kind in [:type, :typep, :opaque] do
    if context.current_module do
      line = Keyword.get(meta, :line, 1)
      {name, arity, params} = extract_type_name(name_def)
      definition = type_to_string(type_def)

      type =
        TypeDef.new(
          context.current_module,
          name,
          arity,
          kind,
          params,
          definition,
          context.file,
          line
        )

      new_result = %{result | types: [type | result.types]}
      {node, {context, new_result}}
    else
      {node, {context, result}}
    end
  end

  # Visit @callback, @macrocallback
  defp visit_node(
         {:@, meta, [{kind, _, [{:"::", _, [signature, return_type]}]}]} = node,
         {context, result}
       )
       when kind in [:callback, :macrocallback] do
    if context.current_module do
      line = Keyword.get(meta, :line, 1)
      {name, arity, params} = extract_function_signature(signature)
      return_str = type_to_string(return_type)
      definition = "#{format_params(params)} :: #{return_str}"

      type =
        TypeDef.new(
          context.current_module,
          name,
          arity,
          kind,
          params,
          definition,
          context.file,
          line
        )

      new_result = %{result | types: [type | result.types]}
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

  # Extract function name, arity, and param types from a spec signature
  defp extract_function_signature({name, _, args}) when is_atom(name) and is_list(args) do
    params = Enum.map(args, &type_to_string/1)
    {to_string(name), length(args), params}
  end

  defp extract_function_signature({name, _, nil}) when is_atom(name) do
    {to_string(name), 0, []}
  end

  defp extract_function_signature(_other) do
    {"unknown", 0, []}
  end

  # Extract type name, arity, and param names from a type definition
  defp extract_type_name({name, _, args}) when is_atom(name) and is_list(args) do
    params = Enum.map(args, &extract_param_name/1)
    {to_string(name), length(args), params}
  end

  defp extract_type_name({name, _, nil}) when is_atom(name) do
    {to_string(name), 0, []}
  end

  defp extract_type_name(name) when is_atom(name) do
    {to_string(name), 0, []}
  end

  defp extract_type_name(_other) do
    {"unknown", 0, []}
  end

  defp extract_param_name({name, _, _}) when is_atom(name), do: to_string(name)
  defp extract_param_name(_), do: "_"

  # Convert a type AST to a string representation
  defp type_to_string(ast) do
    Macro.to_string(ast)
  rescue
    _ -> "unknown"
  end

  defp format_params([]), do: "()"
  defp format_params(params), do: "(#{Enum.join(params, ", ")})"
end
