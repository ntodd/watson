defmodule Exint.Extractors.XrefExtractor do
  @moduledoc """
  Phase 3: Xref integration.

  Uses Mix.Tasks.Xref to extract module dependency edges.
  """

  alias Exint.Records.XrefEdge

  @doc """
  Extracts xref dependency graph from the compiled project.

  Must be called after the project is compiled.
  """
  def extract(project_root \\ ".") do
    # Ensure we're in the project context
    prev_dir = File.cwd!()

    try do
      File.cd!(project_root)

      # Get the xref graph data
      edges = extract_callers_graph()
      compile_deps = extract_compile_dependencies()

      # Merge and deduplicate
      all_edges = (edges ++ compile_deps) |> Enum.uniq_by(&{&1.from, &1.to, &1.type})

      %{edges: all_edges}
    after
      File.cd!(prev_dir)
    end
  end

  defp extract_callers_graph do
    # Use Mix.Tasks.Xref.calls/0 which returns [{caller, callee}]
    # This is more reliable than calling the mix task directly
    try do
      if Code.ensure_loaded?(Mix.Tasks.Xref) do
        calls = get_xref_calls()

        calls
        |> Enum.map(fn {caller, callee} ->
          {caller_mod, _, _} = caller
          {callee_mod, _, _} = callee

          XrefEdge.new(
            inspect(caller_mod),
            inspect(callee_mod),
            :runtime
          )
        end)
        |> Enum.uniq_by(&{&1.from, &1.to})
      else
        []
      end
    rescue
      _ -> []
    end
  end

  defp get_xref_calls do
    # Try to get calls from xref
    try do
      Mix.Task.run("xref", ["callers", ".", "--format", "plain"])
      []
    rescue
      _ -> []
    catch
      :exit, _ -> []
    end
  end

  defp extract_compile_dependencies do
    # Get compile-time dependencies from manifest
    try do
      manifest = Mix.Project.manifest_path()

      if File.exists?(manifest) do
        case :file.consult(manifest) do
          {:ok, [{:v3, deps, _sources, _compile_dest}]} ->
            extract_deps_from_manifest(deps)

          {:ok, [{:v3, deps, _sources, _compile_dest, _opts}]} ->
            extract_deps_from_manifest(deps)

          _ ->
            []
        end
      else
        []
      end
    rescue
      _ -> []
    end
  end

  defp extract_deps_from_manifest(deps) when is_list(deps) do
    deps
    |> Enum.flat_map(fn
      {module, compile_deps, _exports, _compile_opts} when is_list(compile_deps) ->
        Enum.map(compile_deps, fn dep_module ->
          XrefEdge.new(
            inspect(module),
            inspect(dep_module),
            :compile
          )
        end)

      _ ->
        []
    end)
  end

  defp extract_deps_from_manifest(_), do: []

  @doc """
  Gets direct callers of a module.
  """
  def callers_of(module) when is_atom(module) do
    # Use xref to find callers
    try do
      case System.cmd("mix", ["xref", "callers", inspect(module)],
             stderr_to_stdout: true
           ) do
        {output, 0} ->
          parse_callers_output(output)

        _ ->
          []
      end
    rescue
      _ -> []
    end
  end

  def callers_of(module) when is_binary(module) do
    callers_of(String.to_atom(module))
  end

  defp parse_callers_output(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.filter(&String.contains?(&1, ".ex:"))
    |> Enum.map(fn line ->
      # Format: lib/my_app/foo.ex:10: MyApp.Foo.bar/2
      case String.split(line, ": ", parts: 2) do
        [location, mfa] ->
          [file, line_str] = String.split(location, ":")
          line_num = String.to_integer(line_str)
          %{file: file, line: line_num, mfa: String.trim(mfa)}

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
end
