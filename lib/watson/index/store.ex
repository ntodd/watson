defmodule Watson.Index.Store do
  @moduledoc """
  Handles reading and writing of index files.

  The index is stored as:
  - `.watson/manifest.json` - Index metadata
  - `.watson/index.jsonl` - JSON Lines format records
  - `.watson/cache/` - Cache directory for compiled data
  """

  alias Watson.Records.Record

  @index_dir ".watson"
  @manifest_file "manifest.json"
  @index_file "index.jsonl"
  @cache_dir "cache"

  @schema_version "1.0.0"

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
  """
  def write_manifest(project_root \\ ".", opts \\ []) do
    init(project_root)

    manifest = %{
      schema_version: @schema_version,
      elixir_version: System.version(),
      otp_version: :erlang.system_info(:otp_release) |> to_string(),
      mix_env: to_string(Mix.env()),
      git_sha: git_sha(project_root),
      indexed_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      project_root: Path.expand(project_root),
      file_count: Keyword.get(opts, :file_count, 0),
      record_count: Keyword.get(opts, :record_count, 0)
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
