defmodule Watson do
  @moduledoc """
  Elixir Code Intelligence Indexer (watson).

  A CLI-first code intelligence indexer that extracts compile-time and static
  structure from Elixir/Phoenix/Ecto projects, producing a queryable symbol/reference
  graph designed for LLM coding agents.

  ## Features

  - Indexes modules, functions, and macros
  - Tracks function call references
  - Extracts Phoenix routes
  - Extracts Ecto schema definitions
  - Provides callers/callees graph traversal
  - Impact analysis for file changes

  ## Usage

  ### CLI

      # Index a project
      watson index

      # Query function definition
      watson query def --mfa MyApp.Users.get_user/1

      # Query references
      watson query refs --mfa MyApp.Users.get_user/1

      # Query routes
      watson query routes

      # Start MCP server
      watson mcp

  ### Programmatic

      # Index the current project
      Watson.Indexer.index()

      # Query for a definition
      Watson.Query.execute(:def, %{mfa: "MyApp.Users.get_user/1"})

      # Query for routes
      Watson.Query.execute(:routes, %{})

  ## MCP Server

  watson can run as an MCP (Model Context Protocol) server, providing tools
  for LLM agents to query the code index via JSON-RPC over stdio.

  Available tools:
  - `index` - Force rebuild of code index
  - `function_definition` - Find where a function is defined
  - `function_references` - Find all call sites for a function
  - `function_callers` - Find functions that call a given function
  - `function_callees` - Find functions called by a given function
  - `routes` - List all Phoenix routes
  - `schema` - Get Ecto schema structure
  - `impact_analysis` - Analyze what's affected by changing files
  - `function_spec` - Get @spec type signature for a function
  - `module_types` - List all type definitions in a module
  - `type_errors` - Get compiler type errors and warnings
  """

  @doc """
  Returns the version of watson.
  """
  def version, do: "0.1.0"
end
