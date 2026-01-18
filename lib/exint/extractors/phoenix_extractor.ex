defmodule Exint.Extractors.PhoenixExtractor do
  @moduledoc """
  Phase 4: Phoenix DSL Extraction.

  Parses router modules to extract:
  - scope blocks
  - pipe_through
  - HTTP verb macros (get, post, put, patch, delete, etc.)
  - Assembles full paths from nested scopes
  """

  alias Exint.Records.PhoenixRoute

  @http_verbs [:get, :post, :put, :patch, :delete, :head, :options, :connect, :trace]

  @doc """
  Extracts Phoenix routes from router files.
  """
  def extract_routes(files) do
    files
    |> Enum.filter(&is_router_file?/1)
    |> Enum.flat_map(&extract_from_file/1)
    |> Enum.uniq_by(&{&1.verb, &1.path, &1.controller, &1.action})
    |> Enum.sort_by(&{&1.verb, &1.path})
  end

  defp is_router_file?(file) do
    case File.read(file) do
      {:ok, content} ->
        # Check for direct Phoenix.Router use or web module :router pattern
        String.contains?(content, "use Phoenix.Router") or
          (String.contains?(content, "Router") and
             (String.contains?(content, ":router") or
                String.contains?(content, "pipe_through")))

      _ ->
        false
    end
  end

  defp extract_from_file(file) do
    with {:ok, content} <- File.read(file),
         {:ok, ast} <- Code.string_to_quoted(content, file: file, columns: true) do
      extract_from_ast(ast, file)
    else
      _ -> []
    end
  end

  defp extract_from_ast(ast, file) do
    router_module = find_router_module(ast)

    context = %{
      file: file,
      router: router_module,
      path_prefix: "",
      alias_prefix: nil
    }

    # Find the router do block and extract routes from it
    case find_router_body(ast) do
      nil -> []
      body -> extract_routes_from_block(body, context)
    end
  end

  defp find_router_module(ast) do
    {_ast, module} =
      Macro.prewalk(ast, nil, fn
        {:defmodule, _, [{:__aliases__, _, parts} | _]} = node, nil ->
          {node, module_to_string(parts)}

        node, acc ->
          {node, acc}
      end)

    module || "Router"
  end

  defp find_router_body(ast) do
    {_ast, body} =
      Macro.prewalk(ast, nil, fn
        {:defmodule, _, [_, [do: block]]} = node, nil ->
          {node, block}

        node, acc ->
          {node, acc}
      end)

    body
  end

  defp extract_routes_from_block({:__block__, _, items}, context) do
    Enum.flat_map(items, &extract_routes_from_node(&1, context))
  end

  defp extract_routes_from_block(single, context) do
    extract_routes_from_node(single, context)
  end

  # Handle scope with path, module alias, options, and do block
  defp extract_routes_from_node(
         {:scope, _meta, [path, {:__aliases__, _, alias_parts}, _opts, [do: block]]},
         context
       )
       when is_binary(path) do
    new_context = %{
      context
      | path_prefix: normalize_path(context.path_prefix, path),
        alias_prefix: module_to_string(alias_parts)
    }

    extract_routes_from_block(block, new_context)
  end

  # Handle scope with path and module alias (no options)
  defp extract_routes_from_node(
         {:scope, _meta, [path, {:__aliases__, _, alias_parts}, [do: block]]},
         context
       )
       when is_binary(path) do
    new_context = %{
      context
      | path_prefix: normalize_path(context.path_prefix, path),
        alias_prefix: module_to_string(alias_parts)
    }

    extract_routes_from_block(block, new_context)
  end

  # Handle scope with path and options
  defp extract_routes_from_node(
         {:scope, _meta, [path, opts, [do: block]]},
         context
       )
       when is_binary(path) and is_list(opts) do
    new_alias =
      case Keyword.get(opts, :alias) do
        {:__aliases__, _, parts} -> module_to_string(parts)
        atom when is_atom(atom) and not is_nil(atom) -> to_string(atom)
        _ -> context.alias_prefix
      end

    new_context = %{
      context
      | path_prefix: normalize_path(context.path_prefix, path),
        alias_prefix: new_alias
    }

    extract_routes_from_block(block, new_context)
  end

  # Handle scope with just path
  defp extract_routes_from_node(
         {:scope, _meta, [path, [do: block]]},
         context
       )
       when is_binary(path) do
    new_context = %{context | path_prefix: normalize_path(context.path_prefix, path)}
    extract_routes_from_block(block, new_context)
  end

  # Handle pipe_through - ignore
  defp extract_routes_from_node({:pipe_through, _meta, _args}, _context) do
    []
  end

  # Handle pipeline - ignore
  defp extract_routes_from_node({:pipeline, _meta, _args}, _context) do
    []
  end

  # Handle HTTP verb routes with module alias controller
  defp extract_routes_from_node(
         {verb, meta, [path, {:__aliases__, _, controller_parts}, action | _]},
         context
       )
       when verb in @http_verbs and is_binary(path) and is_atom(action) do
    line = Keyword.get(meta, :line, 1)
    controller = build_controller_name(controller_parts, context.alias_prefix)
    full_path = normalize_path(context.path_prefix, path)

    [
      PhoenixRoute.new(
        verb,
        full_path,
        controller,
        action,
        context.router,
        line,
        context.file
      )
    ]
  end

  # Handle HTTP verb routes with atom controller
  defp extract_routes_from_node(
         {verb, meta, [path, controller, action | _]},
         context
       )
       when verb in @http_verbs and is_binary(path) and is_atom(controller) and is_atom(action) do
    line = Keyword.get(meta, :line, 1)
    controller_name = build_controller_name([controller], context.alias_prefix)
    full_path = normalize_path(context.path_prefix, path)

    [
      PhoenixRoute.new(
        verb,
        full_path,
        controller_name,
        action,
        context.router,
        line,
        context.file
      )
    ]
  end

  # Handle resources with nested block
  defp extract_routes_from_node(
         {:resources, meta, [path, {:__aliases__, _, controller_parts} | rest]},
         context
       )
       when is_binary(path) do
    line = Keyword.get(meta, :line, 1)
    controller = build_controller_name(controller_parts, context.alias_prefix)
    full_path = normalize_path(context.path_prefix, path)

    # Parse options and nested block
    {opts, nested_block} = parse_resources_args(rest)

    only = get_opt(opts, :only)
    except = get_opt(opts, :except)
    actions = filter_resource_actions(only, except)

    # Generate resource routes
    resource_routes =
      Enum.map(actions, fn {action, verb, path_suffix} ->
        route_path = build_resource_path(full_path, path_suffix)

        PhoenixRoute.new(
          verb,
          route_path,
          controller,
          action,
          context.router,
          line,
          context.file
        )
      end)

    # Handle nested resources
    nested_routes =
      case nested_block do
        nil ->
          []

        block ->
          nested_context = %{context | path_prefix: full_path <> "/:#{singularize(path)}_id"}
          extract_routes_from_block(block, nested_context)
      end

    resource_routes ++ nested_routes
  end

  # Handle plug - ignore
  defp extract_routes_from_node({:plug, _meta, _args}, _context), do: []

  # Handle forward - ignore for now
  defp extract_routes_from_node({:forward, _meta, _args}, _context), do: []

  # Handle live routes
  defp extract_routes_from_node({:live, meta, [path, {:__aliases__, _, module_parts} | _]}, context)
       when is_binary(path) do
    line = Keyword.get(meta, :line, 1)
    module = module_to_string(module_parts)
    full_path = normalize_path(context.path_prefix, path)

    [
      PhoenixRoute.new(
        :get,
        full_path,
        module,
        :live,
        context.router,
        line,
        context.file
      )
    ]
  end

  # Default - ignore other nodes
  defp extract_routes_from_node(_node, _context), do: []

  defp parse_resources_args([]), do: {[], nil}

  defp parse_resources_args([[do: block]]), do: {[], block}

  defp parse_resources_args([opts]) when is_list(opts) do
    case Keyword.pop(opts, :do) do
      {nil, opts} -> {opts, nil}
      {block, opts} -> {opts, block}
    end
  end

  defp parse_resources_args([opts, [do: block]]) when is_list(opts) do
    {opts, block}
  end

  defp parse_resources_args(_), do: {[], nil}

  defp get_opt(opts, key) when is_list(opts), do: Keyword.get(opts, key)
  defp get_opt(_, _), do: nil

  defp normalize_path("", path), do: normalize_single_path(path)
  defp normalize_path(prefix, path) do
    prefix = String.trim_trailing(prefix, "/")
    path = normalize_single_path(path)
    prefix <> path
  end

  defp normalize_single_path("/" <> _ = path), do: path
  defp normalize_single_path(""), do: ""
  defp normalize_single_path(path), do: "/" <> path

  defp build_controller_name(parts, nil) do
    module_to_string(parts)
  end

  defp build_controller_name(parts, alias_prefix) do
    controller = module_to_string(parts)

    if String.contains?(controller, ".") do
      controller
    else
      "#{alias_prefix}.#{controller}"
    end
  end

  defp module_to_string(parts) when is_list(parts) do
    parts |> Enum.map(&to_string/1) |> Enum.join(".")
  end

  @default_resource_actions [
    {:index, :get, ""},
    {:show, :get, ":id"},
    {:new, :get, "new"},
    {:edit, :get, ":id/edit"},
    {:create, :post, ""},
    {:update, :put, ":id"},
    {:update, :patch, ":id"},
    {:delete, :delete, ":id"}
  ]

  defp filter_resource_actions(nil, nil), do: @default_resource_actions

  defp filter_resource_actions(only, nil) when is_list(only) do
    Enum.filter(@default_resource_actions, fn {action, _, _} -> action in only end)
  end

  defp filter_resource_actions(nil, except) when is_list(except) do
    Enum.reject(@default_resource_actions, fn {action, _, _} -> action in except end)
  end

  defp filter_resource_actions(_, _), do: @default_resource_actions

  defp build_resource_path(base_path, ""), do: base_path
  defp build_resource_path(base_path, suffix), do: base_path <> "/" <> suffix

  defp singularize(path) do
    # Simple singularization for resource paths
    name = Path.basename(path)

    cond do
      String.ends_with?(name, "ies") ->
        String.replace_suffix(name, "ies", "y")

      String.ends_with?(name, "es") ->
        String.replace_suffix(name, "es", "")

      String.ends_with?(name, "s") ->
        String.replace_suffix(name, "s", "")

      true ->
        name
    end
  end
end
