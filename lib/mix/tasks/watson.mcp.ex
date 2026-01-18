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

    * `index` - Force rebuild of code index
    * `function_definition` - Find where a function is defined
    * `function_references` - Find all call sites for a function
    * `function_callers` - Find functions that call a given function
    * `function_callees` - Find functions called by a given function
    * `routes` - List all Phoenix routes
    * `schema` - Get Ecto schema structure
    * `impact_analysis` - Analyze what's affected by changing files
    * `function_spec` - Get @spec type signature for a function
    * `module_types` - List all type definitions in a module
    * `type_errors` - Get compiler type errors and warnings

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
