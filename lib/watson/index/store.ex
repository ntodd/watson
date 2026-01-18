defmodule Watson.Index.Store do
  @moduledoc """
  Handles reading and writing of index files.

  The index is stored as:
  - `.watson/manifest.json` - Index metadata with file states
  - `.watson/index.jsonl` - JSON Lines format records
  - `.watson/cache/` - Cache directory for compiled data

  ## Manifest Schema v2.0

  The manifest now includes:
  - `files` - Per-file state for change detection (mtime, size, content_hash, modules)
  - `module_files` - Module-to-file mapping for dependency tracking
  - `dependencies` - Dependency graph from xref for computing affected files
  """

  alias Watson.Records.Record
  alias Watson.Index.FileState

  @index_dir ".watson"
  @manifest_file "manifest.json"
  @index_file "index.jsonl"
  @cache_dir "cache"

  @schema_version "2.0.0"

  @doc """
  Returns the index directory path for the given project root.
  """
  def index_dir(project_root \\ ".") do
    Path.join(project_root, @index_dir)
  end

  @doc """
  Returns the manifest file path.
  """
  def manifest_path(project_root \\ ".") do
    Path.join([project_root, @index_dir, @manifest_file])
  end

  @doc """
  Returns the index file path.
  """
  def index_path(project_root \\ ".") do
    Path.join([project_root, @index_dir, @index_file])
  end

  @doc """
  Returns the cache directory path.
  """
  def cache_dir(project_root \\ ".") do
    Path.join([project_root, @index_dir, @cache_dir])
  end

  @doc """
  Initializes the index directory structure.
  """
  def init(project_root \\ ".") do
    File.mkdir_p!(index_dir(project_root))
    File.mkdir_p!(cache_dir(project_root))
    :ok
  end

  @doc """
  Writes records to the index file.
  """
  def write_records(records, project_root \\ ".") do
    init(project_root)

    lines =
      records
      |> List.flatten()
      |> Enum.map(&record_to_line/1)
      |> Enum.join("\n")

    File.write!(index_path(project_root), lines <> "\n")
    :ok
  end

  @doc """
  Appends records to the index file.
  """
  def append_records(records, project_root \\ ".") do
    init(project_root)

    lines =
      records
      |> List.flatten()
      |> Enum.map(&record_to_line/1)
      |> Enum.join("\n")

    File.write!(index_path(project_root), lines <> "\n", [:append])
    :ok
  end

  defp record_to_line({record, source, confidence}) do
    Record.to_json_line(record, source, confidence)
  end

  defp record_to_line({record, source}) do
    Record.to_json_line(record, source, :high)
  end

  defp record_to_line(record) do
    Record.to_json_line(record, :ast, :high)
  end

  @doc """
  Writes the manifest file.

  ## Options

  - `:file_count` - Number of source files indexed
  - `:record_count` - Total number of records in the index
  - `:file_states` - Map of file path to FileState for change detection
  - `:module_files` - Map of module name to file path
  - `:dependencies` - Map of module to list of modules it depends on
  """
  def write_manifest(project_root \\ ".", opts \\ []) do
    init(project_root)

    file_states = Keyword.get(opts, :file_states, %{})
    module_files = Keyword.get(opts, :module_files, %{})
    dependencies = Keyword.get(opts, :dependencies, %{})

    # Convert FileState structs to maps
    files_map =
      file_states
      |> Enum.map(fn {path, state} -> {path, FileState.to_map(state)} end)
      |> Map.new()

    manifest = %{
      schema_version: @schema_version,
      elixir_version: System.version(),
      otp_version: :erlang.system_info(:otp_release) |> to_string(),
      mix_env: to_string(Mix.env()),
      git_sha: git_sha(project_root),
      indexed_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      project_root: Path.expand(project_root),
      file_count: Keyword.get(opts, :file_count, 0),
      record_count: Keyword.get(opts, :record_count, 0),
      files: files_map,
      module_files: module_files,
      dependencies: dependencies
    }

    json = Jason.encode!(manifest, pretty: true)
    File.write!(manifest_path(project_root), json)
    :ok
  end

  @doc """
  Reads the manifest file.
  """
  def read_manifest(project_root \\ ".") do
    path = manifest_path(project_root)

    case File.read(path) do
      {:ok, content} -> Jason.decode(content)
      {:error, _} = error -> error
    end
  end

  @doc """
  Returns the current schema version.
  """
  def schema_version, do: @schema_version

  @doc """
  Checks if the manifest schema version is compatible.
  Returns true if the manifest is from schema version 2.0.0 or later.
  """
  def schema_compatible?(project_root \\ ".") do
    case read_manifest(project_root) do
      {:ok, manifest} ->
        version = manifest["schema_version"] || "1.0.0"
        Version.compare(version, "2.0.0") != :lt

      {:error, _} ->
        false
    end
  end

  @doc """
  Reads file states from the manifest.
  Returns a map of file path to FileState struct.
  """
  def read_file_states(project_root \\ ".") do
    case read_manifest(project_root) do
      {:ok, manifest} ->
        files = manifest["files"] || %{}

        states =
          files
          |> Enum.map(fn {path, data} -> {path, FileState.from_map(path, data)} end)
          |> Map.new()

        {:ok, states}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Reads module-to-file mapping from the manifest.
  """
  def read_module_files(project_root \\ ".") do
    case read_manifest(project_root) do
      {:ok, manifest} -> {:ok, manifest["module_files"] || %{}}
      {:error, _} = error -> error
    end
  end

  @doc """
  Reads dependencies from the manifest.
  """
  def read_dependencies(project_root \\ ".") do
    case read_manifest(project_root) do
      {:ok, manifest} -> {:ok, manifest["dependencies"] || %{}}
      {:error, _} = error -> error
    end
  end

  @doc """
  Removes records from the index that match the given file paths.
  Returns the remaining records.
  """
  def remove_records_for_files(file_paths, project_root \\ ".") do
    path_set = MapSet.new(file_paths)

    remaining =
      stream_records(project_root)
      |> Stream.reject(fn record ->
        file = get_in(record, ["data", "file"])
        file && MapSet.member?(path_set, file)
      end)
      |> Enum.to_list()

    {:ok, remaining}
  end

  @doc """
  Rewrites the index with the given records, removing old content.
  """
  def rewrite_records(records, project_root \\ ".") do
    init(project_root)

    lines =
      records
      |> Enum.map(&record_to_json_line/1)
      |> Enum.join("\n")

    File.write!(index_path(project_root), lines <> "\n")
    :ok
  end

  defp record_to_json_line(record) when is_map(record) do
    # Already a decoded JSON map, just re-encode
    Jason.encode!(record)
  end

  @doc """
  Reads all records from the index file.
  """
  def read_records(project_root \\ ".") do
    path = index_path(project_root)

    case File.read(path) do
      {:ok, content} ->
        records =
          content
          |> String.split("\n", trim: true)
          |> Enum.map(&Jason.decode!/1)

        {:ok, records}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Streams records from the index file.
  """
  def stream_records(project_root \\ ".") do
    path = index_path(project_root)

    File.stream!(path)
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Stream.map(&Jason.decode!/1)
  end

  @doc """
  Checks if an index exists.
  """
  def index_exists?(project_root \\ ".") do
    File.exists?(manifest_path(project_root)) and
      File.exists?(index_path(project_root))
  end

  @doc """
  Clears the index.
  """
  def clear(project_root \\ ".") do
    dir = index_dir(project_root)

    if File.exists?(dir) do
      File.rm_rf!(dir)
    end

    :ok
  end

  defp git_sha(project_root) do
    git_dir = Path.join(project_root, ".git")

    if File.exists?(git_dir) do
      case System.cmd("git", ["rev-parse", "HEAD"], cd: project_root, stderr_to_stdout: true) do
        {sha, 0} -> String.trim(sha)
        _ -> nil
      end
    else
      nil
    end
  end
end
