defmodule Exint.Indexer do
  @moduledoc """
  Main indexer that orchestrates all extraction phases.

  Phases:
  1. AST Pass - Parse all files and extract static structure
  2. Compiler Tracing - Run compilation with tracer to capture resolved references
  3. Xref - Import dependency edges
  4. Phoenix DSL - Extract routes from router modules
  5. Ecto DSL - Extract schemas from model modules
  """

  alias Exint.Extractors.{
    AstExtractor,
    XrefExtractor,
    PhoenixExtractor,
    EctoExtractor
  }

  alias Exint.Index.Store

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

    # Collect all records
    all_records = collect_records(ast_result, compiler_result, xref_result, routes, schemas)

    # Write to store
    IO.puts("Writing index...")
    Store.write_records(all_records, project_root)

    # Write manifest
    Store.write_manifest(project_root,
      file_count: length(files),
      record_count: count_records(all_records)
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
    output_file = Path.join(abs_path, ".exint_tracer_output.json")
    tracer_file = Path.join(abs_path, ".exint_tracer.ex")
    runner_file = Path.join(abs_path, ".exint_runner.exs")

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
      {output, exit_code} = System.cmd("elixir", [runner_file],
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
    defmodule ExintTracer do
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
          |> Enum.uniq_by(& {&1.file, &1.line})

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
    ExintTracer.start()

    # Compile with the tracer
    Mix.start()
    Mix.shell(Mix.Shell.Quiet)
    Code.compile_file("mix.exs")
    Mix.Task.run("deps.loadpaths", ["--no-compile"])
    Mix.Task.run("compile", ["--force", "--tracer", "ExintTracer"])

    # Save results
    events = ExintTracer.stop()
    ExintTracer.write_output(events)
    """
  end

  defp get_project_name(mix_file) do
    case File.read(mix_file) do
      {:ok, content} ->
        case Regex.run(~r/app:\s*:(\w+)/, content) do
          [_, name] -> String.to_atom(name)
          _ -> :target_project
        end
      _ -> :target_project
    end
  end

  defp decode_call_ref(data) do
    alias Exint.Records.CallRef
    CallRef.new(data["caller"], data["callee"], data["file"], data["line"])
  end

  defp decode_xref_edge(data) do
    alias Exint.Records.XrefEdge
    XrefEdge.new(data["from"], data["to"], String.to_atom(data["type"]))
  end

  defp collect_records(ast_result, compiler_result, xref_result, routes, schemas) do
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

    [ast_non_call_records, deduplicated_calls, compiler_edges, xref_edges, route_records, schema_records]
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
    # Use file + line as the unique key for a call site
    # (same call site may have different callee representations: Accounts.foo vs TestProject.Accounts.foo)
    # Normalize file path for comparison
    file = record.file |> Path.basename()
    line = record.span[:line] || record.span.line
    {file, line}
  end

  defp count_records(records) do
    records
    |> List.flatten()
    |> length()
  end
end
