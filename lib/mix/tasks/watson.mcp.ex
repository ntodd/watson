defmodule Mix.Tasks.Watson.Mcp do
  @moduledoc """
  Start the watson MCP (Model Context Protocol) server.

  The MCP server communicates via JSON-RPC over stdio, providing
  code intelligence tools for LLM coding agents.

  ## Usage

      mix watson.mcp [--path PATH]

  ## Options

    * `--path`, `-p` - Path to the project to serve (default: current directory)

  ## Available Tools

  Once running, the MCP server provides these tools:

    * `watson_index` - Index the project
    * `watson_query_def` - Query function definition
    * `watson_query_refs` - Query references
    * `watson_query_callers` - Query callers graph
    * `watson_query_callees` - Query callees graph
    * `watson_query_routes` - Query Phoenix routes
    * `watson_query_schema` - Query Ecto schema
    * `watson_query_impact` - Query impact analysis

  ## Example MCP Configuration

  For Claude Code, add to your MCP config:

      {
        "mcpServers": {
          "watson": {
            "command": "mix",
            "args": ["watson.mcp", "--path", "/path/to/project"],
            "cwd": "/path/to/watson"
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
    Application.ensure_all_started(:watson)

    # Start the MCP server (blocks forever)
    Watson.MCP.Server.start_stdio(path)
  end
end
