defmodule Watson.Index.FileState do
  @moduledoc """
  Tracks file state for change detection.

  Each file is tracked with:
  - mtime: File modification time
  - size: File size in bytes
  - content_hash: MD5 hash of file contents
  - modules: List of modules defined in the file
  """

  @type t :: %__MODULE__{
          path: String.t(),
          mtime: integer(),
          size: non_neg_integer(),
          content_hash: String.t(),
          modules: [String.t()]
        }

  @enforce_keys [:path, :mtime, :size, :content_hash]
  defstruct [:path, :mtime, :size, :content_hash, modules: []]

  @doc """
  Creates a FileState from a file path.
  """
  @spec from_file(String.t()) :: {:ok, t()} | {:error, term()}
  def from_file(path) do
    with {:ok, stat} <- File.stat(path, time: :posix),
         {:ok, content} <- File.read(path) do
      {:ok,
       %__MODULE__{
         path: path,
         mtime: stat.mtime,
         size: stat.size,
         content_hash: content_hash(content),
         modules: []
       }}
    end
  end

  @doc """
  Creates a FileState from a file path with known modules.
  """
  @spec from_file(String.t(), [String.t()]) :: {:ok, t()} | {:error, term()}
  def from_file(path, modules) do
    case from_file(path) do
      {:ok, state} -> {:ok, %{state | modules: modules}}
      error -> error
    end
  end

  @doc """
  Converts FileState to a map for JSON serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = state) do
    %{
      "mtime" => state.mtime,
      "size" => state.size,
      "content_hash" => state.content_hash,
      "modules" => state.modules
    }
  end

  @doc """
  Creates a FileState from a serialized map.
  """
  @spec from_map(String.t(), map()) :: t()
  def from_map(path, map) do
    %__MODULE__{
      path: path,
      mtime: map["mtime"],
      size: map["size"],
      content_hash: map["content_hash"],
      modules: map["modules"] || []
    }
  end

  @doc """
  Checks if a file has changed compared to its stored state.
  Returns true if the file has changed or doesn't exist.
  """
  @spec changed?(t()) :: boolean()
  def changed?(%__MODULE__{} = stored_state) do
    case File.stat(stored_state.path, time: :posix) do
      {:ok, stat} ->
        # Quick check: if mtime and size are the same, likely unchanged
        if stat.mtime != stored_state.mtime or stat.size != stored_state.size do
          # Verify with content hash
          case File.read(stored_state.path) do
            {:ok, content} -> content_hash(content) != stored_state.content_hash
            {:error, _} -> true
          end
        else
          false
        end

      {:error, _} ->
        # File doesn't exist or can't be read - consider it changed
        true
    end
  end

  @doc """
  Computes MD5 hash of content as hex string.
  """
  @spec content_hash(binary()) :: String.t()
  def content_hash(content) do
    :crypto.hash(:md5, content) |> Base.encode16(case: :lower)
  end
end
