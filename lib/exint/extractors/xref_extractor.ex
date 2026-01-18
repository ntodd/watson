defmodule Exint.Extractors.XrefExtractor do
  @moduledoc """
  Phase 3: Xref integration.

  Uses Mix.Tasks.Xref to extract:
  - Fully resolved function calls (caller -> callee with exact MFAs)
  - Module dependency edges (compile-time vs runtime)
  """

  alias Exint.Records.{CallRef, XrefEdge}

  @doc """
  Extracts xref data from the compiled project.

  Must be called after the project is compiled.
  Returns resolved function calls and module dependency edges.
  """
  def extract(project_root \\ ".") do
    prev_dir = File.cwd!()

    try do
      File.cd!(project_root)

      # Get resolved function calls
      calls = extract_calls()

      # Get module dependency graph
      edges = extract_dependency_graph()

      %{calls: calls, edges: edges}
    after
      File.cd!(prev_dir)
    end
  end

  @doc """
  Extracts fully resolved function calls using Mix.Tasks.Xref.calls/0.

  This gives us accurate caller->callee relationships with resolved module names.
  """
  def extract_calls do
    try do
      # Suppress deprecation warning - this API still works and is the simplest way
      calls = Mix.Tasks.Xref.calls()

      calls
      |> Enum.map(&call_to_record/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(&{&1.caller, &1.callee, &1.span.line})
    rescue
      e ->
        IO.puts("  Warning: xref calls extraction failed: #{inspect(e)}")
        []
    end
  end

  defp call_to_record(%{caller_module: caller_mod, callee: {callee_mod, name, arity}, file: file, line: line}) do
    # Skip Elixir/Erlang stdlib calls to reduce noise
    callee_mod_str = inspect(callee_mod)

    if skip_module?(callee_mod_str) do
      nil
    else
      caller = inspect(caller_mod)
      callee = "#{callee_mod_str}.#{name}/#{arity}"

      # Normalize file path to be relative
      relative_file = make_relative(file)

      CallRef.new(caller, callee, relative_file, line)
    end
  end

  defp call_to_record(_), do: nil

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

  defp make_relative(file) do
    cwd = File.cwd!()

    if String.starts_with?(file, cwd) do
      Path.relative_to(file, cwd)
    else
      file
    end
  end
end
