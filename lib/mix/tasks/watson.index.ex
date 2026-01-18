defmodule Mix.Tasks.Watson.Index do
  @moduledoc """
  Indexes the current Mix project for code intelligence queries.

  ## Usage

      mix watson.index [--path PATH] [--force]

  ## Options

    * `--path`, `-p` - Path to the project to index (default: current directory)
    * `--force`, `-f` - Force a full re-index, bypassing incremental mode

  ## Examples

      mix watson.index
      mix watson.index --path /path/to/project
      mix watson.index --force

  ## Incremental Indexing

  By default, watson.index performs incremental indexing - it only re-indexes
  files that have changed since the last index. Use `--force` to bypass this
  and do a complete re-index.

  """

  use Mix.Task

  @shortdoc "Index the project for code intelligence"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [path: :string, force: :boolean],
        aliases: [p: :path, f: :force]
      )

    path = Keyword.get(opts, :path, ".")
    force = Keyword.get(opts, :force, false)

    result =
      if force do
        Watson.Indexer.index(path)
      else
        Watson.Indexer.ensure_index_current(path)
      end

    case result do
      {:ok, count} when is_integer(count) ->
        Mix.shell().info("Successfully indexed #{count} records")

      {:ok, :current} ->
        Mix.shell().info("Index is up to date")

      {:ok, :updated, count} ->
        Mix.shell().info("Incrementally updated index (#{count} new records)")

      {:ok, :created, count} ->
        Mix.shell().info("Created new index with #{count} records")

      {:error, reason} ->
        Mix.shell().error("Error: #{reason}")
        exit({:shutdown, 1})
    end
  end
end
