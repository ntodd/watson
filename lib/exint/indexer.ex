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
    CompilerTracer,
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
    try do
      # Start the tracer
      CompilerTracer.start()

      # Run compilation with tracer
      prev_dir = File.cwd!()

      try do
        File.cd!(project_root)

        # Set the tracer and compile
        Mix.Task.run("compile", ["--force", "--tracer", "Exint.Extractors.CompilerTracer"])
      after
        File.cd!(prev_dir)
      end

      # Get events and convert to records
      events = CompilerTracer.stop()
      CompilerTracer.events_to_records(events)
    rescue
      e ->
        IO.puts("Compiler tracing failed: #{inspect(e)}")
        %{calls: [], edges: []}
    catch
      :exit, _ ->
        %{calls: [], edges: []}
    end
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
