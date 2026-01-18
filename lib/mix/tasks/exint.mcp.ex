defmodule Mix.Tasks.Exint.Mcp do
  @moduledoc """
  Start the exint MCP (Model Context Protocol) server.

  The MCP server communicates via JSON-RPC over stdio, providing
  code intelligence tools for LLM coding agents.

  ## Usage

      mix exint.mcp [--path PATH]

  ## Options

    * `--path`, `-p` - Path to the project to serve (default: current directory)

  ## Available Tools

  Once running, the MCP server provides these tools:

    * `exint_index` - Index the project
    * `exint_query_def` - Query function definition
    * `exint_query_refs` - Query references
    * `exint_query_callers` - Query callers graph
    * `exint_query_callees` - Query callees graph
    * `exint_query_routes` - Query Phoenix routes
    * `exint_query_schema` - Query Ecto schema
    * `exint_query_impact` - Query impact analysis

  ## Example MCP Configuration

  For Claude Code, add to your MCP config:

      {
        "mcpServers": {
          "exint": {
            "command": "mix",
            "args": ["exint.mcp", "--path", "/path/to/project"],
            "cwd": "/path/to/exint"
          }
        }
      }

  """

  use Mix.Task

  @shortdoc "Start the MCP server for LLM agent integration"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [path: :string],
        aliases: [p: :path]
      )

    path = Keyword.get(opts, :path, ".")

    # Start the application to ensure all dependencies are loaded
    Application.ensure_all_started(:exint)

    # Start the MCP server (blocks forever)
    Exint.MCP.Server.start_stdio(path)
  end
end
