defmodule Exint.Query do
  @moduledoc """
  Query engine for the exint index.

  Supported queries:
  - def --mfa Mod.fun/arity
  - refs --mfa Mod.fun/arity
  - callers --mfa Mod.fun/arity [--depth N]
  - callees --mfa Mod.fun/arity [--depth N]
  - routes
  - schema --module Mod
  - impact --files file1 file2 ...
  """

  alias Exint.Index.Store

  @doc """
  Executes a query against the index.
  Returns JSON-serializable results.
  """
  def execute(query_type, args, opts \\ []) do
    project_root = Keyword.get(opts, :project_root, ".")

    unless Store.index_exists?(project_root) do
      {:error, "Index not found. Run 'exint index' first."}
    else
      case query_type do
        :def -> query_def(args[:mfa], project_root)
        :refs -> query_refs(args[:mfa], project_root)
        :callers -> query_callers(args[:mfa], args[:depth] || 1, project_root)
        :callees -> query_callees(args[:mfa], args[:depth] || 1, project_root)
        :routes -> query_routes(project_root)
        :schema -> query_schema(args[:module], project_root)
        :impact -> query_impact(args[:files], project_root)
        _ -> {:error, "Unknown query type: #{query_type}"}
      end
    end
  end

  @doc """
  Query for function definition.
  Returns exactly one definition or empty list.
  """
  def query_def(mfa, project_root \\ ".") do
    {module, name, arity} = parse_mfa(mfa)

    result =
      Store.stream_records(project_root)
      |> Stream.filter(&(&1["kind"] == "function_def"))
      |> Stream.filter(fn record ->
        data = record["data"]

        data["module"] == module and
          data["name"] == name and
          data["arity"] == arity
      end)
      |> Enum.take(1)

    {:ok, result}
  end

  @doc """
  Query for all call sites referencing an MFA.
  """
  def query_refs(mfa, project_root \\ ".") do
    normalized_mfa = normalize_mfa(mfa)

    result =
      Store.stream_records(project_root)
      |> Stream.filter(&(&1["kind"] == "call_ref"))
      |> Stream.filter(fn record ->
        record["data"]["callee"] == normalized_mfa
      end)
      |> Enum.to_list()
      |> Enum.sort_by(fn r -> {r["data"]["file"], r["data"]["span"]["line"]} end)

    {:ok, result}
  end

  @doc """
  Query for callers of an MFA up to a given depth.
  """
  def query_callers(mfa, depth, project_root \\ ".") do
    normalized_mfa = normalize_mfa(mfa)

    # Build call graph
    call_graph = build_call_graph(project_root)

    # BFS to find callers
    callers = find_callers_bfs(normalized_mfa, depth, call_graph)

    {:ok, callers}
  end

  @doc """
  Query for callees of an MFA up to a given depth.
  """
  def query_callees(mfa, depth, project_root \\ ".") do
    normalized_mfa = normalize_mfa(mfa)

    # Build reverse call graph
    call_graph = build_callee_graph(project_root)

    # BFS to find callees
    callees = find_callers_bfs(normalized_mfa, depth, call_graph)

    {:ok, callees}
  end

  @doc """
  Query all Phoenix routes.
  """
  def query_routes(project_root \\ ".") do
    result =
      Store.stream_records(project_root)
      |> Stream.filter(&(&1["kind"] == "phoenix_route"))
      |> Enum.to_list()
      |> Enum.sort_by(fn r ->
        data = r["data"]
        {data["verb"], data["path"]}
      end)

    {:ok, result}
  end

  @doc """
  Query for Ecto schema by module name.
  """
  def query_schema(module, project_root \\ ".") do
    result =
      Store.stream_records(project_root)
      |> Stream.filter(&(&1["kind"] == "ecto_schema"))
      |> Stream.filter(fn record ->
        record["data"]["module"] == module
      end)
      |> Enum.take(1)

    {:ok, result}
  end

  @doc """
  Query for impact of changed files.
  Returns affected modules and test files.
  """
  def query_impact(files, project_root \\ ".") do
    # Get all modules defined in the changed files
    changed_modules = get_modules_in_files(files, project_root)

    # Build module dependency graph
    dep_graph = build_module_dep_graph(project_root)

    # Find all affected modules (transitive closure)
    affected = find_affected_modules(changed_modules, dep_graph)

    # Find test files that import/use affected modules
    test_files = find_affected_tests(affected, project_root)

    {:ok,
     %{
       changed_modules: Enum.sort(changed_modules),
       affected_modules: Enum.sort(affected),
       test_files: Enum.sort(test_files)
     }}
  end

  # Private helpers

  defp parse_mfa(mfa) when is_binary(mfa) do
    # Parse "Module.function/arity" format
    case Regex.run(~r/^(.+)\.([^.\/]+)\/(\d+)$/, mfa) do
      [_, module, name, arity] ->
        {module, name, String.to_integer(arity)}

      nil ->
        {mfa, nil, nil}
    end
  end

  defp normalize_mfa(mfa) when is_binary(mfa), do: mfa

  defp normalize_mfa({module, name, arity}) do
    "#{module}.#{name}/#{arity}"
  end

  defp build_call_graph(project_root) do
    Store.stream_records(project_root)
    |> Stream.filter(&(&1["kind"] == "call_ref"))
    |> Enum.reduce(%{}, fn record, graph ->
      callee = record["data"]["callee"]
      caller = record["data"]["caller"]

      if callee && caller do
        Map.update(graph, callee, [caller], &[caller | &1])
      else
        graph
      end
    end)
    |> Map.new(fn {k, v} -> {k, Enum.uniq(v)} end)
  end

  defp build_callee_graph(project_root) do
    Store.stream_records(project_root)
    |> Stream.filter(&(&1["kind"] == "call_ref"))
    |> Enum.reduce(%{}, fn record, graph ->
      callee = record["data"]["callee"]
      caller = record["data"]["caller"]

      if callee && caller do
        Map.update(graph, caller, [callee], &[callee | &1])
      else
        graph
      end
    end)
    |> Map.new(fn {k, v} -> {k, Enum.uniq(v)} end)
  end

  defp find_callers_bfs(start, max_depth, graph) do
    find_callers_bfs([{start, 0}], max_depth, graph, MapSet.new([start]), [])
  end

  defp find_callers_bfs([], _max_depth, _graph, _visited, result) do
    result
    |> Enum.reverse()
    |> Enum.uniq_by(&{&1.mfa, &1.depth})
  end

  defp find_callers_bfs([{_current, depth} | rest], max_depth, graph, visited, result)
       when depth >= max_depth do
    find_callers_bfs(rest, max_depth, graph, visited, result)
  end

  defp find_callers_bfs([{current, depth} | rest], max_depth, graph, visited, result) do
    callers = Map.get(graph, current, [])

    new_callers =
      callers
      |> Enum.reject(&MapSet.member?(visited, &1))

    new_visited = Enum.reduce(new_callers, visited, &MapSet.put(&2, &1))

    new_entries =
      Enum.map(new_callers, fn mfa ->
        %{mfa: mfa, depth: depth + 1}
      end)

    new_queue = rest ++ Enum.map(new_callers, &{&1, depth + 1})

    find_callers_bfs(new_queue, max_depth, graph, new_visited, new_entries ++ result)
  end

  defp get_modules_in_files(files, project_root) do
    Store.stream_records(project_root)
    |> Stream.filter(&(&1["kind"] == "module_def"))
    |> Stream.filter(fn record ->
      file = record["data"]["file"]
      Enum.any?(files, &files_match?(&1, file))
    end)
    |> Enum.map(& &1["data"]["module"])
  end

  defp files_match?(pattern, file) do
    # Normalize paths and check for match
    norm_pattern = Path.expand(pattern)
    norm_file = Path.expand(file)

    String.ends_with?(norm_file, pattern) or
      norm_pattern == norm_file or
      String.contains?(norm_file, pattern)
  end

  defp build_module_dep_graph(project_root) do
    Store.stream_records(project_root)
    |> Stream.filter(&(&1["kind"] == "xref_edge"))
    |> Enum.reduce(%{}, fn record, graph ->
      from = record["data"]["from"]
      to = record["data"]["to"]

      # Build reverse graph: if A depends on B, then when B changes, A is affected
      Map.update(graph, to, [from], &[from | &1])
    end)
    |> Map.new(fn {k, v} -> {k, Enum.uniq(v)} end)
  end

  defp find_affected_modules(changed_modules, dep_graph) do
    # Transitive closure using BFS
    find_affected_bfs(changed_modules, dep_graph, MapSet.new(changed_modules))
    |> MapSet.to_list()
  end

  defp find_affected_bfs([], _graph, visited), do: visited

  defp find_affected_bfs([module | rest], graph, visited) do
    dependents = Map.get(graph, module, [])

    new_dependents =
      dependents
      |> Enum.reject(&MapSet.member?(visited, &1))

    new_visited = Enum.reduce(new_dependents, visited, &MapSet.put(&2, &1))

    find_affected_bfs(rest ++ new_dependents, graph, new_visited)
  end

  defp find_affected_tests(affected_modules, project_root) do
    affected_set = MapSet.new(affected_modules)

    # Find all test files that import/use affected modules
    Store.stream_records(project_root)
    |> Stream.filter(&(&1["kind"] == "alias_ref"))
    |> Stream.filter(fn record ->
      record["data"]["type"] in ["use", "import", "alias"] and
        MapSet.member?(affected_set, record["data"]["target"])
    end)
    |> Stream.map(& &1["data"]["file"])
    |> Stream.filter(&String.contains?(&1, "test/"))
    |> Enum.to_list()
    |> Enum.uniq()
  end
end
