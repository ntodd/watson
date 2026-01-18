defmodule Mix.Tasks.Exint.Query do
  @moduledoc """
  Query the exint index.

  ## Usage

      mix exint.query TYPE [OPTIONS]

  ## Query Types

    * `def` - Query function definition
    * `refs` - Query references to a function
    * `callers` - Query functions that call a function
    * `callees` - Query functions called by a function
    * `routes` - Query all Phoenix routes
    * `schema` - Query Ecto schema
    * `impact` - Query impact of file changes

  ## Options

    * `--mfa`, `-m` - MFA in format Module.function/arity
    * `--module` - Module name (for schema query)
    * `--files`, `-f` - Comma-separated file paths (for impact query)
    * `--depth`, `-d` - Traversal depth for callers/callees (default: 1)
    * `--path`, `-p` - Project path (default: current directory)

  ## Examples

      mix exint.query routes
      mix exint.query def --mfa MyApp.Accounts.get_user/1
      mix exint.query refs --mfa MyApp.Accounts.get_user/1
      mix exint.query callers --mfa MyApp.Accounts.get_user/1 --depth 2
      mix exint.query schema --module MyApp.Accounts.User
      mix exint.query impact --files lib/my_app/accounts.ex

  """

  use Mix.Task

  @shortdoc "Query the code intelligence index"

  @impl Mix.Task
  def run(args) do
    case args do
      [] ->
        Mix.shell().error("Usage: mix exint.query TYPE [OPTIONS]")
        Mix.shell().info("Run `mix help exint.query` for more information")
        exit({:shutdown, 1})

      [query_type | rest] ->
        run_query(query_type, rest)
    end
  end

  defp run_query(query_type, args) do
    {opts, remaining, _} =
      OptionParser.parse(args,
        strict: [
          mfa: :string,
          module: :string,
          files: :string,
          depth: :integer,
          path: :string
        ],
        aliases: [
          m: :mfa,
          d: :depth,
          p: :path,
          f: :files
        ]
      )

    project_path = Keyword.get(opts, :path, ".")

    query_args = build_query_args(query_type, opts, remaining)

    case Exint.Query.execute(String.to_atom(query_type), query_args, project_root: project_path) do
      {:ok, result} ->
        IO.puts(Jason.encode!(result))

      {:error, reason} ->
        Mix.shell().error("Error: #{reason}")
        exit({:shutdown, 1})
    end
  end

  defp build_query_args(query_type, opts, remaining) do
    base_args =
      opts
      |> Keyword.delete(:path)
      |> Enum.into(%{})

    # Handle files argument
    files =
      case {Map.get(base_args, :files), remaining} do
        {nil, []} -> nil
        {nil, files} -> files
        {files_str, _} -> String.split(files_str, ",")
      end

    if files && query_type == "impact" do
      Map.put(base_args, :files, files)
    else
      base_args
    end
  end
end
