defmodule Watson.Indexer do
  @moduledoc """
  Main indexer that orchestrates all extraction phases.

  Phases:
  1. AST Pass - Parse all files and extract static structure
  2. Compiler Tracing - Run compilation with tracer to capture resolved references
  3. Xref - Import dependency edges
  4. Phoenix DSL - Extract routes from router modules
  5. Ecto DSL - Extract schemas from model modules

  ## Incremental Indexing

  The indexer supports incremental updates. When files change, only the affected
  files are re-indexed rather than rebuilding the entire index.

  Use `ensure_index_current/1` to automatically check for changes and re-index
  only when necessary.
  """

  alias Watson.Extractors.{
    AstExtractor,
    XrefExtractor,
    PhoenixExtractor,
    EctoExtractor,
    TypeExtractor,
    DiagnosticsExtractor
  }

  alias Watson.Index.{Store, FileState, ChangeDetector}

  @doc """
  Indexes the Mix project at the given path.
  """
  def index(project_root \\ ".") do
    try do
      do_index(project_root)
    rescue
      e ->
        {:error, "Indexing failed: #{Exception.message(e)}"}
    end
  end

  defp do_index(project_root) do
    IO.puts("Starting index of #{Path.expand(project_root)}...")

    # Clear any existing index
    Store.clear(project_root)

    # Find all Elixir source files
    files = find_source_files(project_root)
    IO.puts("Found #{length(files)} source files")

    # Phase 1: AST extraction
    IO.puts("Phase 1: AST extraction...")
    ast_result = AstExtractor.extract_files(files)

    # Phase 2: Compiler tracing (optional - requires compilation)
    IO.puts("Phase 2: Compiler tracing...")
    compiler_result = run_compiler_tracing(project_root)

    # Phase 3: Xref extraction
    IO.puts("Phase 3: Xref extraction...")
    xref_result = XrefExtractor.extract(project_root)

    # Phase 4: Phoenix routes
    IO.puts("Phase 4: Phoenix route extraction...")
    routes = PhoenixExtractor.extract_routes(files)

    # Phase 5: Ecto schemas
    IO.puts("Phase 5: Ecto schema extraction...")
    schemas = EctoExtractor.extract_schemas(files)

    # Phase 6: Type annotations (@spec, @type, @callback)
    IO.puts("Phase 6: Type annotation extraction...")
    type_result = TypeExtractor.extract_files(files)

    # Phase 7: Compiler diagnostics (optional - Elixir 1.15+)
    diagnostics_result =
      if DiagnosticsExtractor.available?() do
        IO.puts("Phase 7: Compiler diagnostics extraction...")
        DiagnosticsExtractor.extract_project(project_root)
      else
        IO.puts("Phase 7: Skipping diagnostics (requires Elixir 1.15+)")
        %{diagnostics: []}
      end

    # Collect all records
    all_records =
      collect_records(
        ast_result,
        compiler_result,
        xref_result,
        routes,
        schemas,
        type_result,
        diagnostics_result
      )

    # Build file states for change detection
    file_states = build_file_states(files, ast_result.modules)

    # Build module-to-file mapping
    module_files = build_module_files(ast_result.modules)

    # Build dependencies from xref edges
    dependencies = build_dependencies(xref_result.edges || [])

    # Write to store
    IO.puts("Writing index...")
    Store.write_records(all_records, project_root)

    # Write manifest with file states and dependencies
    Store.write_manifest(project_root,
      file_count: length(files),
      record_count: count_records(all_records),
      file_states: file_states,
      module_files: module_files,
      dependencies: dependencies
    )

    IO.puts("Index complete!")
    {:ok, count_records(all_records)}
  end

  @doc """
  Finds all Elixir source files in the project.
  """
  def find_source_files(project_root) do
    lib_files = Path.wildcard(Path.join([project_root, "lib", "**", "*.ex"]))
    lib_exs_files = Path.wildcard(Path.join([project_root, "lib", "**", "*.exs"]))
    test_files = Path.wildcard(Path.join([project_root, "test", "**", "*.exs"]))

    (lib_files ++ lib_exs_files ++ test_files)
    |> Enum.sort()
    |> Enum.uniq()
  end

  defp run_compiler_tracing(project_root) do
    # Compiler tracing requires running within the target project
    # We write a tracer module to a temp file that gets loaded via mix.exs compiler config
    abs_path = Path.expand(project_root)
    unique_id = :erlang.unique_integer([:positive])
    output_file = Path.join(abs_path, ".watson_tracer_output_#{unique_id}.json")
    tracer_file = Path.join(abs_path, ".watson_tracer_#{unique_id}.ex")
    runner_file = Path.join(abs_path, ".watson_runner_#{unique_id}.exs")

    try do
      # Delete any previous output
      File.rm(output_file)

      # Write tracer module
      File.write!(tracer_file, tracer_module_code(output_file))

      # Write runner script
      File.write!(runner_file, runner_script_code(tracer_file))

      IO.puts("  Running compiler tracer in #{abs_path}...")

      # Clean the project's compiled output to force recompilation
      build_dir = Path.join(abs_path, "_build/dev/lib")
      project_name = get_project_name(Path.join(abs_path, "mix.exs"))
      project_build = Path.join(build_dir, to_string(project_name))
      File.rm_rf(project_build)

      # Run the tracer
      {output, exit_code} =
        System.cmd("elixir", [runner_file],
          cd: abs_path,
          env: [{"MIX_ENV", "dev"}],
          stderr_to_stdout: true
        )

      # Cleanup temp files
      File.rm(tracer_file)
      File.rm(runner_file)

      if exit_code != 0 do
        IO.puts("  Compiler tracing warning: #{String.slice(output, 0, 500)}")
      end

      # Read the tracer output
      case File.read(output_file) do
        {:ok, content} ->
          File.rm(output_file)

          case Jason.decode(content) do
            {:ok, data} ->
              calls = Enum.map(data["calls"] || [], &decode_call_ref/1)
              edges = Enum.map(data["edges"] || [], &decode_xref_edge/1)
              IO.puts("  Captured #{length(calls)} calls, #{length(edges)} edges")
              %{calls: calls, edges: edges, compile_envs: []}

            {:error, _} ->
              IO.puts("  Warning: Could not parse tracer output")
              %{calls: [], edges: [], compile_envs: []}
          end

        {:error, _} ->
          IO.puts("  Warning: No tracer output generated")
          %{calls: [], edges: [], compile_envs: []}
      end
    rescue
      e ->
        IO.puts("  Compiler tracing failed: #{Exception.message(e)}")
        File.rm(tracer_file)
        File.rm(runner_file)
        %{calls: [], edges: [], compile_envs: []}
    end
  end

  defp tracer_module_code(output_file) do
    """
    defmodule WatsonTracer do
      @output_file "#{output_file}"

      def start do
        Agent.start_link(fn -> [] end, name: __MODULE__)
      end

      def stop do
        events = Agent.get(__MODULE__, & &1)
        Agent.stop(__MODULE__)
        events
      end

      def write_output(events) do
        calls = events
          |> Enum.filter(& &1.type == :call)
          |> Enum.filter(& &1.line > 1)
          |> Enum.map(fn e ->
            caller = if e.caller_fn, do: "\#{inspect(e.caller_mod)}.\#{elem(e.caller_fn, 0)}/\#{elem(e.caller_fn, 1)}", else: inspect(e.caller_mod)
            callee = "\#{inspect(e.callee_mod)}.\#{e.callee_name}/\#{e.callee_arity}"
            %{caller: caller, callee: callee, file: e.file, line: e.line}
          end)
          |> Enum.reject(fn c ->
            String.starts_with?(c.callee, "Kernel.") ||
            String.starts_with?(c.callee, "Module.") ||
            String.starts_with?(c.callee, ":erlang.") ||
            String.starts_with?(c.callee, "Phoenix.Component.Declarative.") ||
            String.starts_with?(c.callee, "Phoenix.Template.")
          end)
          |> Enum.uniq_by(& {&1.file, &1.line, &1.callee})

        edges = events
          |> Enum.filter(& &1.type in [:struct, :require])
          |> Enum.map(fn e -> %{from: inspect(e.from), to: inspect(e.to), type: Atom.to_string(e.type)} end)
          |> Enum.uniq()

        output = Jason.encode!(%{calls: calls, edges: edges})
        File.write!(@output_file, output)
      end

      def trace({:remote_function, meta, module, name, arity}, env) do
        record_call(meta, module, name, arity, env)
      end

      def trace({:imported_function, meta, module, name, arity}, env) do
        record_call(meta, module, name, arity, env)
      end

      def trace({:local_function, meta, name, arity}, env) do
        # Local function - callee is in the same module as caller
        record_call(meta, env.module, name, arity, env)
      end

      def trace({:local_macro, meta, name, arity}, env) do
        # Local macro - callee is in the same module as caller
        record_call(meta, env.module, name, arity, env)
      end

      def trace({:struct_expansion, _meta, module, _keys}, env) do
        if Process.whereis(__MODULE__) && env.module do
          Agent.update(__MODULE__, fn events ->
            [%{type: :struct, from: env.module, to: module} | events]
          end)
        end
        :ok
      end

      def trace({:require, _meta, module, _opts}, env) do
        if Process.whereis(__MODULE__) && env.module do
          Agent.update(__MODULE__, fn events ->
            [%{type: :require, from: env.module, to: module} | events]
          end)
        end
        :ok
      end

      def trace(_, _), do: :ok

      defp record_call(meta, module, name, arity, env) do
        if Process.whereis(__MODULE__) && env.module do
          Agent.update(__MODULE__, fn events ->
            [%{type: :call, caller_mod: env.module, caller_fn: env.function,
               callee_mod: module, callee_name: name, callee_arity: arity,
               file: env.file, line: Keyword.get(meta, :line, 0)} | events]
          end)
        end
        :ok
      end
    end
    """
  end

  defp runner_script_code(tracer_file) do
    """
    # Load the tracer module first
    Code.compile_file("#{tracer_file}")

    # Start the tracer
    WatsonTracer.start()

    # Compile with the tracer
    Mix.start()
    Mix.shell(Mix.Shell.Quiet)
    Code.compile_file("mix.exs")
    Mix.Task.run("deps.loadpaths", ["--no-compile"])
    Mix.Task.run("compile", ["--force", "--tracer", "WatsonTracer"])

    # Save results
    events = WatsonTracer.stop()
    WatsonTracer.write_output(events)
    """
  end

  defp get_project_name(mix_file) do
    case File.read(mix_file) do
      {:ok, content} ->
        case Regex.run(~r/app:\s*:(\w+)/, content) do
          [_, name] -> String.to_atom(name)
          _ -> :target_project
        end

      _ ->
        :target_project
    end
  end

  defp decode_call_ref(data) do
    alias Watson.Records.CallRef
    CallRef.new(data["caller"], data["callee"], data["file"], data["line"])
  end

  defp decode_xref_edge(data) do
    alias Watson.Records.XrefEdge
    XrefEdge.new(data["from"], data["to"], String.to_atom(data["type"]))
  end

  defp collect_records(
         ast_result,
         compiler_result,
         xref_result,
         routes,
         schemas,
         type_result \\ %{specs: [], types: []},
         diagnostics_result \\ %{diagnostics: []}
       ) do
    # Non-call AST records (source: :ast, confidence: :high)
    ast_non_call_records =
      [
        Enum.map(ast_result.modules, &{&1, :ast, :high}),
        Enum.map(ast_result.functions, &{&1, :ast, :high}),
        Enum.map(ast_result.aliases, &{&1, :ast, :high}),
        Enum.map(ast_result.structs, &{&1, :ast, :high})
      ]
      |> List.flatten()

    # Collect calls from all sources, then deduplicate
    # Priority: compiler > xref > ast (compiler has full MFA, xref has resolved callee)
    ast_calls = Enum.map(ast_result.calls, &{&1, :ast, :medium})
    compiler_calls = Enum.map(compiler_result.calls || [], &{&1, :compiler, :high})
    xref_calls = Enum.map(xref_result.calls || [], &{&1, :xref, :high})

    # Deduplicate calls - prefer higher quality sources
    # Key by (callee, file, line) to identify same call site
    deduplicated_calls = deduplicate_calls(compiler_calls, xref_calls, ast_calls)

    # Edges (don't need deduplication - different semantics)
    compiler_edges = Enum.map(compiler_result.edges || [], &{&1, :compiler, :high})
    xref_edges = Enum.map(xref_result.edges || [], &{&1, :xref, :high})

    # Phoenix routes (source: :ast, confidence: :high)
    route_records = Enum.map(routes, &{&1, :ast, :high})

    # Ecto schemas (source: :ast, confidence: :high)
    schema_records = Enum.map(schemas, &{&1, :ast, :high})

    # Type annotations (source: :ast, confidence: :high)
    type_specs = Enum.map(type_result.specs || [], &{&1, :ast, :high})
    type_defs = Enum.map(type_result.types || [], &{&1, :ast, :high})

    # Compiler diagnostics (source: :compiler, confidence: :high)
    diagnostics = Enum.map(diagnostics_result.diagnostics || [], &{&1, :compiler, :high})

    [
      ast_non_call_records,
      deduplicated_calls,
      compiler_edges,
      xref_edges,
      route_records,
      schema_records,
      type_specs,
      type_defs,
      diagnostics
    ]
    |> List.flatten()
  end

  # Deduplicate calls across sources, preferring compiler > xref > ast
  defp deduplicate_calls(compiler_calls, xref_calls, ast_calls) do
    # Build a map keyed by (callee, file, line)
    # Insert in reverse priority order so higher priority overwrites
    all_calls = ast_calls ++ xref_calls ++ compiler_calls

    all_calls
    |> Enum.reduce(%{}, fn {record, source, confidence}, acc ->
      key = call_key(record)
      # Always overwrite - later entries (higher priority) win
      Map.put(acc, key, {record, source, confidence})
    end)
    |> Map.values()
  end

  defp call_key(record) do
    # Use file + line + callee as the unique key for a call site
    # This ensures different function calls on the same line are preserved
    # Normalize file path for comparison
    file = record.file |> Path.expand()
    line = record.span[:line] || record.span.line
    callee = record.callee
    {file, line, callee}
  end

  defp count_records(records) do
    records
    |> List.flatten()
    |> length()
  end

  # Build file states for change detection
  defp build_file_states(files, modules) do
    # Group modules by file
    modules_by_file =
      modules
      |> Enum.group_by(& &1.file)
      |> Map.new(fn {file, mods} -> {file, Enum.map(mods, & &1.module)} end)

    files
    |> Enum.reduce(%{}, fn file, acc ->
      case FileState.from_file(file, Map.get(modules_by_file, file, [])) do
        {:ok, state} -> Map.put(acc, file, state)
        {:error, _} -> acc
      end
    end)
  end

  # Build module-to-file mapping
  defp build_module_files(modules) do
    modules
    |> Enum.map(fn mod -> {mod.module, mod.file} end)
    |> Map.new()
  end

  # Build dependencies from xref edges
  defp build_dependencies(edges) do
    edges
    |> Enum.reduce(%{}, fn edge, acc ->
      from = edge.from
      to = edge.to
      Map.update(acc, from, [to], fn deps -> [to | deps] end)
    end)
    |> Map.new(fn {k, v} -> {k, Enum.uniq(v)} end)
  end

  @doc """
  Ensures the index is current, performing incremental updates if needed.

  Returns:
  - `{:ok, :current}` if the index is up to date
  - `{:ok, :updated, count}` if the index was updated
  - `{:ok, :created, count}` if a new index was created
  - `{:error, reason}` if indexing failed
  """
  def ensure_index_current(project_root \\ ".") do
    cond do
      # No index exists - do full index
      not Store.index_exists?(project_root) ->
        case index(project_root) do
          {:ok, count} -> {:ok, :created, count}
          error -> error
        end

      # Schema version mismatch - do full index
      not Store.schema_compatible?(project_root) ->
        case index(project_root) do
          {:ok, count} -> {:ok, :created, count}
          error -> error
        end

      # Check for changes
      true ->
        check_and_update(project_root)
    end
  end

  defp check_and_update(project_root) do
    with {:ok, stored_states} <- Store.read_file_states(project_root),
         {:ok, dependencies} <- Store.read_dependencies(project_root),
         {:ok, module_files} <- Store.read_module_files(project_root) do
      current_files = find_source_files(project_root)

      changes = ChangeDetector.detect(current_files, stored_states, dependencies, module_files)

      if ChangeDetector.has_changes?(changes) do
        incremental_index(project_root, changes)
      else
        {:ok, :current}
      end
    else
      {:error, _} ->
        # Can't read manifest - do full index
        case index(project_root) do
          {:ok, count} -> {:ok, :created, count}
          error -> error
        end
    end
  end

  @doc """
  Performs an incremental index based on detected changes.
  """
  def incremental_index(project_root, changes) do
    try do
      do_incremental_index(project_root, changes)
    rescue
      e ->
        {:error, "Incremental indexing failed: #{Exception.message(e)}"}
    end
  end

  defp do_incremental_index(project_root, changes) do
    files_to_remove = ChangeDetector.files_to_remove(changes)
    files_to_reindex = ChangeDetector.files_to_reindex(changes)

    if files_to_reindex == [] and files_to_remove == [] do
      {:ok, :current}
    else
      IO.puts(
        "Incremental index: #{length(files_to_reindex)} files to update, #{length(changes.deleted)} deleted"
      )

      # Remove old records for changed/deleted files
      {:ok, remaining_records} = Store.remove_records_for_files(files_to_remove, project_root)

      # Extract new records from changed files
      if files_to_reindex != [] do
        # Phase 1: AST extraction for changed files
        ast_result = AstExtractor.extract_files(files_to_reindex)

        # Phase 4: Phoenix routes (check if router files changed)
        routes = PhoenixExtractor.extract_routes(files_to_reindex)

        # Phase 5: Ecto schemas
        schemas = EctoExtractor.extract_schemas(files_to_reindex)

        # Phase 2: Compiler tracing for accurate call refs
        compiler_result = run_compiler_tracing(project_root)

        # Phase 3: Refresh xref edges for updated dependency graph
        xref_result = XrefExtractor.extract(project_root)

        # Collect new records
        new_records =
          collect_records(
            ast_result,
            compiler_result,
            xref_result,
            routes,
            schemas
          )

        # Write combined records
        all_records = remaining_records ++ format_records_for_write(new_records)
        Store.rewrite_records(all_records, project_root)

        # Update manifest with new file states
        all_files = find_source_files(project_root)
        {:ok, old_states} = Store.read_file_states(project_root)
        {:ok, old_module_files} = Store.read_module_files(project_root)
        new_dependencies = build_dependencies(xref_result.edges || [])

        # Update file states for changed files
        new_states =
          files_to_reindex
          |> Enum.reduce(old_states, fn file, acc ->
            modules_in_file =
              ast_result.modules
              |> Enum.filter(&(&1.file == file))
              |> Enum.map(& &1.module)

            case FileState.from_file(file, modules_in_file) do
              {:ok, state} -> Map.put(acc, file, state)
              {:error, _} -> Map.delete(acc, file)
            end
          end)

        # Remove states for deleted files
        new_states =
          Enum.reduce(changes.deleted, new_states, fn file, acc ->
            Map.delete(acc, file)
          end)

        # Update module files
        new_module_files =
          ast_result.modules
          |> Enum.reduce(old_module_files, fn mod, acc ->
            Map.put(acc, mod.module, mod.file)
          end)

        # Remove deleted modules from module_files
        deleted_modules =
          changes.deleted
          |> Enum.flat_map(fn file ->
            case Map.get(old_states, file) do
              nil -> []
              state -> state.modules
            end
          end)

        new_module_files =
          Enum.reduce(deleted_modules, new_module_files, fn mod, acc ->
            Map.delete(acc, mod)
          end)

        Store.write_manifest(project_root,
          file_count: length(all_files),
          record_count: length(all_records),
          file_states: new_states,
          module_files: new_module_files,
          dependencies: new_dependencies
        )

        {:ok, :updated, length(new_records)}
      else
        # Only deletions
        Store.rewrite_records(remaining_records, project_root)

        {:ok, old_states} = Store.read_file_states(project_root)
        {:ok, old_module_files} = Store.read_module_files(project_root)
        {:ok, old_dependencies} = Store.read_dependencies(project_root)

        # Remove states for deleted files
        new_states =
          Enum.reduce(changes.deleted, old_states, fn file, acc ->
            Map.delete(acc, file)
          end)

        # Remove deleted modules
        deleted_modules =
          changes.deleted
          |> Enum.flat_map(fn file ->
            case Map.get(old_states, file) do
              nil -> []
              state -> state.modules
            end
          end)

        new_module_files =
          Enum.reduce(deleted_modules, old_module_files, fn mod, acc ->
            Map.delete(acc, mod)
          end)

        all_files = find_source_files(project_root)

        Store.write_manifest(project_root,
          file_count: length(all_files),
          record_count: length(remaining_records),
          file_states: new_states,
          module_files: new_module_files,
          dependencies: old_dependencies
        )

        {:ok, :updated, 0}
      end
    end
  end

  defp format_records_for_write(records) do
    records
    |> List.flatten()
    |> Enum.map(fn
      {record, source, confidence} ->
        Watson.Records.Record.to_map(record, source, confidence)

      record ->
        Watson.Records.Record.to_map(record, :ast, :high)
    end)
  end
end
