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
  - `watson_index` - Index the project
  - `watson_query_def` - Query function definition
  - `watson_query_refs` - Query references
  - `watson_query_callers` - Query callers graph
  - `watson_query_callees` - Query callees graph
  - `watson_query_routes` - Query Phoenix routes
  - `watson_query_schema` - Query Ecto schema
  - `watson_query_impact` - Query impact analysis
  """

  @doc """
  Returns the version of watson.
  """
  def version, do: "0.1.0"
end
