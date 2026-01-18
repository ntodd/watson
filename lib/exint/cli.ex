defmodule Exint.CLI do
  @moduledoc """
  Command-line interface for exint.

  Commands:
    exint index                           Index the current Mix project
    exint query def --mfa Mod.fun/arity   Query function definition
    exint query refs --mfa Mod.fun/arity  Query all references to function
    exint query callers --mfa Mod.fun/arity [--depth N]
    exint query callees --mfa Mod.fun/arity [--depth N]
    exint query routes                    Query all Phoenix routes
    exint query schema --module Mod       Query Ecto schema
    exint query impact --files file1,file2  Query impact of file changes
    exint mcp                             Start MCP server mode
  """

  @doc """
  Main entry point for escript.
  """
  def main(args) do
    args
    |> parse_args()
    |> run()
  end

  defp parse_args(args) do
    case args do
      ["index" | rest] ->
        {:index, parse_index_opts(rest)}

      ["query", query_type | rest] ->
        {:query, String.to_atom(query_type), parse_query_opts(rest)}

      ["mcp" | rest] ->
        {:mcp, parse_mcp_opts(rest)}

      ["help" | _] ->
        {:help, []}

      ["--help" | _] ->
        {:help, []}

      ["-h" | _] ->
        {:help, []}

      [] ->
        {:help, []}

      _ ->
        {:error, "Unknown command. Run 'exint help' for usage."}
    end
  end

  defp parse_index_opts(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [path: :string],
        aliases: [p: :path]
      )

    opts
  end

  defp parse_query_opts(args) do
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

    # Handle positional files argument
    files =
      case {Keyword.get(opts, :files), remaining} do
        {nil, []} -> nil
        {nil, files} -> files
        {files_str, _} -> String.split(files_str, ",")
      end

    if files do
      Keyword.put(opts, :files, files)
    else
      opts
    end
  end

  defp parse_mcp_opts(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          path: :string,
          transport: :string
        ],
        aliases: [p: :path, t: :transport]
      )

    opts
  end

  defp run({:help, _}) do
    IO.puts("""
    exint - Elixir Code Intelligence Indexer

    USAGE:
      exint <command> [options]

    COMMANDS:
      index                   Index the current Mix project
      query <type> [options]  Query the index
      mcp                     Start MCP server mode
      help                    Show this help message

    QUERY TYPES:
      def --mfa Mod.fun/arity
          Returns the function definition

      refs --mfa Mod.fun/arity
          Returns all call sites referencing the function

      callers --mfa Mod.fun/arity [--depth N]
          Returns functions that call this function

      callees --mfa Mod.fun/arity [--depth N]
          Returns functions called by this function

      routes
          Returns all Phoenix routes

      schema --module Mod
          Returns Ecto schema definition

      impact --files file1,file2
          Returns modules and tests affected by file changes

    OPTIONS:
      --path, -p    Project path (default: current directory)
      --depth, -d   Traversal depth for callers/callees (default: 1)
      --mfa, -m     MFA in format Module.function/arity
      --module      Module name for schema query
      --files, -f   Comma-separated list of files

    EXAMPLES:
      exint index
      exint query def --mfa MyApp.Users.get_user/1
      exint query refs --mfa MyApp.Users.get_user/1
      exint query callers --mfa MyApp.Users.get_user/1 --depth 2
      exint query routes
      exint query schema --module MyApp.Accounts.User
      exint query impact --files lib/my_app/users.ex
      exint mcp
    """)
  end

  defp run({:index, opts}) do
    project_path = Keyword.get(opts, :path, ".")

    case Exint.Indexer.index(project_path) do
      {:ok, count} ->
        IO.puts("Successfully indexed #{count} records")

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
    end
  end

  defp run({:query, query_type, opts}) do
    project_path = Keyword.get(opts, :path, ".")

    args =
      opts
      |> Keyword.delete(:path)
      |> Enum.into(%{})

    case Exint.Query.execute(query_type, args, project_root: project_path) do
      {:ok, result} ->
        IO.puts(Jason.encode!(result, pretty: false))

      {:error, reason} ->
        error = %{error: reason}
        IO.puts(:stderr, Jason.encode!(error))
        System.halt(1)
    end
  end

  defp run({:mcp, opts}) do
    project_path = Keyword.get(opts, :path, ".")
    transport = Keyword.get(opts, :transport, "stdio")

    case transport do
      "stdio" ->
        Exint.MCP.Server.start_stdio(project_path)

      other ->
        IO.puts(:stderr, "Unknown transport: #{other}")
        System.halt(1)
    end
  end

  defp run({:error, message}) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end
