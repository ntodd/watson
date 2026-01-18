defmodule Exint do
  @moduledoc """
  Elixir Code Intelligence Indexer (exint).

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
      exint index

      # Query function definition
      exint query def --mfa MyApp.Users.get_user/1

      # Query references
      exint query refs --mfa MyApp.Users.get_user/1

      # Query routes
      exint query routes

      # Start MCP server
      exint mcp

  ### Programmatic

      # Index the current project
      Exint.Indexer.index()

      # Query for a definition
      Exint.Query.execute(:def, %{mfa: "MyApp.Users.get_user/1"})

      # Query for routes
      Exint.Query.execute(:routes, %{})

  ## MCP Server

  exint can run as an MCP (Model Context Protocol) server, providing tools
  for LLM agents to query the code index via JSON-RPC over stdio.

  Available tools:
  - `exint_index` - Index the project
  - `exint_query_def` - Query function definition
  - `exint_query_refs` - Query references
  - `exint_query_callers` - Query callers graph
  - `exint_query_callees` - Query callees graph
  - `exint_query_routes` - Query Phoenix routes
  - `exint_query_schema` - Query Ecto schema
  - `exint_query_impact` - Query impact analysis
  """

  @doc """
  Returns the version of exint.
  """
  def version, do: "0.1.0"
end
