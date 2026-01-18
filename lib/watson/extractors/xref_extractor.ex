defmodule Watson.Extractors.XrefExtractor do
  @moduledoc """
  Phase 3: Xref integration.

  Extracts module dependency edges (compile-time vs runtime) from the
  compilation manifest. Function call extraction is handled by the
  CompilerTracer which provides better data (full MFA for both caller
  and callee).
  """

  alias Watson.Records.XrefEdge

  @doc """
  Extracts xref data from the compiled project.

  Must be called after the project is compiled.
  Returns module dependency edges (calls are handled by CompilerTracer).
  """
  def extract(project_root \\ ".") do
    prev_dir = File.cwd!()

    try do
      File.cd!(project_root)

      # Get module dependency graph
      edges = extract_dependency_graph()

      # Note: Function calls are extracted by CompilerTracer which provides
      # full MFA for both caller and callee. The deprecated Mix.Tasks.Xref.calls/0
      # only provided module-level caller information.
      %{calls: [], edges: edges}
    after
      File.cd!(prev_dir)
    end
  end

  @doc """
  Extracts module dependency graph.

  Returns edges with type :compile, :export, or :runtime.
  """
  def extract_dependency_graph do
    try do
      # Get all sources from the manifest
      sources = get_sources()

      sources
      |> Enum.flat_map(&extract_deps_from_source/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(&{&1.from, &1.to, &1.type})
    rescue
      e ->
        IO.puts("  Warning: xref graph extraction failed: #{inspect(e)}")
        []
    end
  end

  defp get_sources do
    try do
      # Use Mix.Project's source tracking
      manifest_path = Path.join(Mix.Project.manifest_path(), ".mix/compile.elixir")

      if File.exists?(manifest_path) do
        {sources, _} = Mix.Compilers.Elixir.read_manifest(manifest_path)
        sources
      else
        # Fallback: try to get from xref
        []
      end
    rescue
      _ -> []
    end
  end

  defp extract_deps_from_source(source) do
    try do
      # source is a tuple like {source_path, modules, compile_deps, export_deps, runtime_deps, ...}
      case source do
        {_path, _size, _digest, _kind, _beam_mtime, modules, compile_deps, export_deps, runtime_deps, _compile_env} ->
          from_modules = modules |> List.wrap()

          Enum.flat_map(from_modules, fn from_mod ->
            compile_edges = Enum.map(List.wrap(compile_deps), &create_edge(from_mod, &1, :compile))
            export_edges = Enum.map(List.wrap(export_deps), &create_edge(from_mod, &1, :export))
            runtime_edges = Enum.map(List.wrap(runtime_deps), &create_edge(from_mod, &1, :runtime))

            compile_edges ++ export_edges ++ runtime_edges
          end)

        _ ->
          []
      end
    rescue
      _ -> []
    end
  end

  defp create_edge(from, to, type) when is_atom(from) and is_atom(to) do
    from_str = inspect(from)
    to_str = inspect(to)

    if skip_module?(to_str) do
      nil
    else
      XrefEdge.new(from_str, to_str, type)
    end
  end

  defp create_edge(_, _, _), do: nil

  # Skip standard library and common framework modules to reduce noise
  defp skip_module?("Elixir." <> _), do: false  # Keep Elixir modules
  defp skip_module?(":erlang"), do: true
  defp skip_module?(":elixir" <> _), do: true
  defp skip_module?(":" <> _), do: true  # Skip erlang modules
  defp skip_module?("Kernel" <> _), do: true
  defp skip_module?("String"), do: true
  defp skip_module?("Enum"), do: true
  defp skip_module?("Map"), do: true
  defp skip_module?("List"), do: true
  defp skip_module?("IO"), do: true
  defp skip_module?("File"), do: true
  defp skip_module?("Path"), do: true
  defp skip_module?("Agent"), do: true
  defp skip_module?("GenServer"), do: true
  defp skip_module?("Supervisor"), do: true
  defp skip_module?("Application"), do: true
  defp skip_module?("Module"), do: true
  defp skip_module?("Code"), do: true
  defp skip_module?("Macro"), do: true
  defp skip_module?("Access"), do: true
  defp skip_module?(_), do: false
end
