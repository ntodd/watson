defmodule Watson.Extractors.DiagnosticsExtractor do
  @moduledoc """
  Extracts compiler diagnostics using Code.with_diagnostics/2.

  Requires Elixir 1.15+ for Code.with_diagnostics/2.
  Captures type errors with Elixir 1.17+ type checker.

  Diagnostics include:
  - Type mismatches (Elixir 1.17+)
  - Unused variables
  - Unreachable clauses
  - Pattern match warnings
  - Deprecated function usage
  """

  alias Watson.Records.TypeDiagnostic

  @type extraction_result :: %{
          diagnostics: [TypeDiagnostic.t()]
        }

  @doc """
  Checks if diagnostics extraction is available (requires Elixir 1.15+).
  """
  def available? do
    function_exported?(Code, :with_diagnostics, 1)
  end

  @doc """
  Extracts diagnostics from the given files.
  Returns empty result if Code.with_diagnostics/2 is not available.
  """
  @spec extract_files([String.t()]) :: extraction_result()
  def extract_files(files) do
    if available?() do
      results =
        files
        |> Enum.flat_map(&extract_file/1)

      %{diagnostics: results}
    else
      %{diagnostics: []}
    end
  end

  @doc """
  Extracts diagnostics from a single file using Code.with_diagnostics/2.
  """
  @spec extract_file(String.t()) :: [TypeDiagnostic.t()]
  def extract_file(file) do
    if available?() do
      try do
        do_extract_file(file)
      rescue
        _ -> []
      end
    else
      []
    end
  end

  defp do_extract_file(file) do
    with {:ok, content} <- File.read(file) do
      # Use Code.with_diagnostics to capture warnings during parsing/compilation
      {_result, diagnostics} =
        Code.with_diagnostics(fn ->
          try do
            Code.compile_string(content, file)
            :ok
          rescue
            _ -> :error
          end
        end)

      diagnostics
      |> Enum.map(&TypeDiagnostic.from_compiler_diagnostic/1)
      |> Enum.map(fn diag -> %{diag | file: file} end)
    else
      {:error, _} -> []
    end
  end

  @doc """
  Extracts diagnostics from a project by compiling all files.
  This is more accurate than file-by-file extraction as it captures
  cross-file type errors.
  """
  @spec extract_project(String.t()) :: extraction_result()
  def extract_project(project_root) do
    if available?() do
      try do
        do_extract_project(project_root)
      rescue
        _ -> %{diagnostics: []}
      end
    else
      %{diagnostics: []}
    end
  end

  defp do_extract_project(project_root) do
    abs_path = Path.expand(project_root)
    runner_file = Path.join(abs_path, ".watson_diagnostics_runner.exs")
    output_file = Path.join(abs_path, ".watson_diagnostics_output.json")

    try do
      # Delete any previous output
      File.rm(output_file)

      # Write runner script
      File.write!(runner_file, diagnostics_runner_code(output_file))

      # Run the diagnostics capture
      {_output, exit_code} =
        System.cmd("elixir", [runner_file],
          cd: abs_path,
          env: [{"MIX_ENV", "dev"}],
          stderr_to_stdout: true
        )

      # Cleanup runner
      File.rm(runner_file)

      if exit_code == 0 do
        case File.read(output_file) do
          {:ok, content} ->
            File.rm(output_file)
            parse_diagnostics_output(content)

          {:error, _} ->
            %{diagnostics: []}
        end
      else
        %{diagnostics: []}
      end
    rescue
      _ ->
        File.rm(runner_file)
        %{diagnostics: []}
    end
  end

  defp diagnostics_runner_code(output_file) do
    """
    # Capture diagnostics during compilation
    Mix.start()
    Mix.shell(Mix.Shell.Quiet)
    Code.compile_file("mix.exs")
    Mix.Task.run("deps.loadpaths", ["--no-compile"])

    {_result, diagnostics} = Code.with_diagnostics(fn ->
      try do
        Mix.Task.run("compile", ["--force"])
        :ok
      rescue
        _ -> :error
      end
    end)

    output = diagnostics
    |> Enum.map(fn d ->
      %{
        severity: to_string(d.severity),
        message: d.message,
        file: d.file || "unknown",
        line: d.position || 1,
        source: d.source && to_string(d.source)
      }
    end)
    |> Jason.encode!()

    File.write!("#{output_file}", output)
    """
  end

  defp parse_diagnostics_output(content) do
    case Jason.decode(content) do
      {:ok, data} ->
        diagnostics =
          data
          |> Enum.map(fn d ->
            TypeDiagnostic.new(
              String.to_atom(d["severity"]),
              d["message"],
              d["file"],
              d["line"],
              source: d["source"]
            )
          end)

        %{diagnostics: diagnostics}

      {:error, _} ->
        %{diagnostics: []}
    end
  end
end
