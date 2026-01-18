defmodule Mix.Tasks.Watson.Index do
  @moduledoc """
  Indexes the current Mix project for code intelligence queries.

  ## Usage

      mix watson.index [--path PATH]

  ## Options

    * `--path`, `-p` - Path to the project to index (default: current directory)

  ## Examples

      mix watson.index
      mix watson.index --path /path/to/project

  """

  use Mix.Task

  @shortdoc "Index the project for code intelligence"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [path: :string],
        aliases: [p: :path]
      )

    path = Keyword.get(opts, :path, ".")

    case Watson.Indexer.index(path) do
      {:ok, count} ->
        Mix.shell().info("Successfully indexed #{count} records")

      {:error, reason} ->
        Mix.shell().error("Error: #{reason}")
        exit({:shutdown, 1})
    end
  end
end
