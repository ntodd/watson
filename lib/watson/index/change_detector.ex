defmodule Watson.Index.ChangeDetector do
  @moduledoc """
  Detects file changes for incremental indexing.

  Compares current file system state against stored file states
  to identify added, modified, deleted, and dependent files.
  """

  alias Watson.Index.FileState

  @type change_set :: %{
          added: [String.t()],
          modified: [String.t()],
          deleted: [String.t()],
          affected: [String.t()]
        }

  @doc """
  Detects changes between current files and stored file states.

  Returns a change set with:
  - added: Files that exist now but weren't in the index
  - modified: Files that have changed since last index
  - deleted: Files that were in the index but no longer exist
  - affected: Files that depend on changed/deleted files

  ## Parameters
  - current_files: List of current source file paths
  - stored_states: Map of file path to FileState from manifest
  - dependencies: Map of module -> list of dependent modules
  - module_files: Map of module -> file path
  """
  @spec detect(
          [String.t()],
          %{String.t() => FileState.t()},
          %{String.t() => [String.t()]},
          %{String.t() => String.t()}
        ) :: change_set()
  def detect(current_files, stored_states, dependencies, module_files) do
    current_set = MapSet.new(current_files)
    stored_set = stored_states |> Map.keys() |> MapSet.new()

    # Find added files (in current but not in stored)
    added = MapSet.difference(current_set, stored_set) |> MapSet.to_list()

    # Find deleted files (in stored but not in current)
    deleted = MapSet.difference(stored_set, current_set) |> MapSet.to_list()

    # Find modified files (in both, but changed)
    common = MapSet.intersection(current_set, stored_set)

    modified =
      common
      |> Enum.filter(fn path ->
        stored_state = Map.get(stored_states, path)
        stored_state && FileState.changed?(stored_state)
      end)

    # Find affected files (files that depend on changed/deleted files)
    changed_files = modified ++ deleted
    affected = find_affected_files(changed_files, stored_states, dependencies, module_files)

    # Remove files that are already in modified/deleted/added from affected
    affected =
      affected
      |> Enum.reject(&(&1 in changed_files))
      |> Enum.reject(&(&1 in added))

    %{
      added: Enum.sort(added),
      modified: Enum.sort(modified),
      deleted: Enum.sort(deleted),
      affected: Enum.sort(affected)
    }
  end

  @doc """
  Checks if any changes were detected.
  """
  @spec has_changes?(change_set()) :: boolean()
  def has_changes?(%{added: added, modified: modified, deleted: deleted, affected: affected}) do
    added != [] or modified != [] or deleted != [] or affected != []
  end

  @doc """
  Returns all files that need to be re-indexed.
  """
  @spec files_to_reindex(change_set()) :: [String.t()]
  def files_to_reindex(%{added: added, modified: modified, affected: affected}) do
    (added ++ modified ++ affected) |> Enum.uniq() |> Enum.sort()
  end

  @doc """
  Returns all files whose records should be removed from the index.
  """
  @spec files_to_remove(change_set()) :: [String.t()]
  def files_to_remove(%{modified: modified, deleted: deleted, affected: affected}) do
    (modified ++ deleted ++ affected) |> Enum.uniq() |> Enum.sort()
  end

  # Find files that depend on the changed modules
  defp find_affected_files(changed_files, stored_states, dependencies, module_files) do
    # Get all modules defined in changed files
    changed_modules =
      changed_files
      |> Enum.flat_map(fn path ->
        case Map.get(stored_states, path) do
          nil -> []
          state -> state.modules
        end
      end)
      |> MapSet.new()

    # Find all modules that depend on changed modules (transitive)
    dependent_modules = find_dependent_modules(changed_modules, dependencies)

    # Map dependent modules back to files
    dependent_modules
    |> Enum.flat_map(fn module ->
      case Map.get(module_files, module) do
        nil -> []
        file -> [file]
      end
    end)
    |> Enum.uniq()
  end

  # BFS to find all modules that depend on the changed modules
  defp find_dependent_modules(changed_modules, dependencies) do
    find_dependents_bfs(
      MapSet.to_list(changed_modules),
      dependencies,
      MapSet.new()
    )
    |> MapSet.to_list()
  end

  defp find_dependents_bfs([], _dependencies, visited), do: visited

  defp find_dependents_bfs([module | rest], dependencies, visited) do
    dependents = Map.get(dependencies, module, [])

    new_dependents =
      dependents
      |> Enum.reject(&MapSet.member?(visited, &1))

    new_visited = Enum.reduce(new_dependents, visited, &MapSet.put(&2, &1))

    find_dependents_bfs(rest ++ new_dependents, dependencies, new_visited)
  end
end
