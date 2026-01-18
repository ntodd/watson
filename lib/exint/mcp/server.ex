defmodule Exint.MCP.Server do
  @moduledoc """
  MCP (Model Context Protocol) server implementation.

  Provides tools for LLM agents to query the Elixir code index.

  Protocol:
  - Uses JSON-RPC 2.0 over stdio
  - Implements MCP 1.0 specification
  """

  require Logger

  @tools [
    %{
      name: "exint_index",
      description: "Index an Elixir/Phoenix project to build a searchable code graph. Run this once before using other query tools. The index is stored in .exint/ and persists across sessions. Re-run after code changes to update.",
      inputSchema: %{
        type: "object",
        properties: %{
          path: %{
            type: "string",
            description: "Path to the Mix project root. Defaults to current directory."
          }
        },
        required: []
      }
    },
    %{
      name: "exint_query_def",
      description: "Find where a function is defined. Returns the file path, line numbers, arity, visibility (public/private), and whether it's a macro. Use this to jump to a function's implementation.",
      inputSchema: %{
        type: "object",
        properties: %{
          mfa: %{
            type: "string",
            description: "Function to find in Module.function/arity format, e.g., 'MyApp.Accounts.get_user/1'"
          }
        },
        required: ["mfa"]
      }
    },
    %{
      name: "exint_query_refs",
      description: "Find all places where a function is called. Returns each call site with file, line number, and the calling function's MFA. Use this to understand how a function is used throughout the codebase.",
      inputSchema: %{
        type: "object",
        properties: %{
          mfa: %{
            type: "string",
            description: "Function to find references for in Module.function/arity format"
          }
        },
        required: ["mfa"]
      }
    },
    %{
      name: "exint_query_callers",
      description: "Find functions that call a given function, traversing up the call graph. With depth=1, returns direct callers. With depth=2+, also returns callers of callers. Use this for impact analysis - what code paths lead to this function?",
      inputSchema: %{
        type: "object",
        properties: %{
          mfa: %{
            type: "string",
            description: "Function to find callers for in Module.function/arity format"
          },
          depth: %{
            type: "integer",
            description: "How many levels up the call graph to traverse. Default is 1 (direct callers only)."
          }
        },
        required: ["mfa"]
      }
    },
    %{
      name: "exint_query_callees",
      description: "Find functions called by a given function, traversing down the call graph. With depth=1, returns direct callees. With depth=2+, follows the chain deeper. Use this to understand a function's dependencies.",
      inputSchema: %{
        type: "object",
        properties: %{
          mfa: %{
            type: "string",
            description: "Function to find callees for in Module.function/arity format"
          },
          depth: %{
            type: "integer",
            description: "How many levels down the call graph to traverse. Default is 1 (direct callees only)."
          }
        },
        required: ["mfa"]
      }
    },
    %{
      name: "exint_query_routes",
      description: "List all HTTP endpoints defined in Phoenix routers. Returns verb (GET/POST/etc), URL path, controller module, and action function for each route. Use this to understand the API surface or find which controller handles a URL.",
      inputSchema: %{
        type: "object",
        properties: %{},
        required: []
      }
    },
    %{
      name: "exint_query_schema",
      description: "Get the structure of an Ecto schema. Returns the database table name, all fields with their types, and associations (belongs_to, has_many, has_one). Use this to understand data models without reading the schema file.",
      inputSchema: %{
        type: "object",
        properties: %{
          module: %{
            type: "string",
            description: "Full module name of the Ecto schema, e.g., 'MyApp.Accounts.User'"
          }
        },
        required: ["module"]
      }
    },
    %{
      name: "exint_query_impact",
      description: "Analyze what would be affected by changing files. Returns modules defined in those files, all modules that depend on them (transitively), and test files that should be run. Use this before making changes to understand blast radius.",
      inputSchema: %{
        type: "object",
        properties: %{
          files: %{
            type: "array",
            items: %{type: "string"},
            description: "List of file paths that have changed or will change"
          }
        },
        required: ["files"]
      }
    }
  ]

  @doc """
  Starts the MCP server in stdio mode.
  """
  def start_stdio(project_path \\ ".") do
    state = %{
      project_path: project_path,
      initialized: false
    }

    loop(state)
  end

  defp loop(state) do
    case IO.read(:stdio, :line) do
      :eof ->
        :ok

      {:error, _reason} ->
        :ok

      line ->
        line = String.trim(line)

        if line != "" do
          state = handle_line(line, state)
          loop(state)
        else
          loop(state)
        end
    end
  end

  defp handle_line(line, state) do
    case Jason.decode(line) do
      {:ok, request} ->
        {response, new_state} = handle_request(request, state)

        if response do
          IO.puts(Jason.encode!(response))
        end

        new_state

      {:error, _} ->
        error_response = %{
          jsonrpc: "2.0",
          id: nil,
          error: %{code: -32700, message: "Parse error"}
        }

        IO.puts(Jason.encode!(error_response))
        state
    end
  end

  defp handle_request(%{"method" => "initialize", "id" => id} = _request, state) do
    response = %{
      jsonrpc: "2.0",
      id: id,
      result: %{
        protocolVersion: "2024-11-05",
        capabilities: %{
          tools: %{
            listChanged: false
          }
        },
        serverInfo: %{
          name: "exint",
          version: "0.1.0"
        }
      }
    }

    {response, %{state | initialized: true}}
  end

  defp handle_request(%{"method" => "initialized"}, state) do
    {nil, state}
  end

  defp handle_request(%{"method" => "tools/list", "id" => id}, state) do
    response = %{
      jsonrpc: "2.0",
      id: id,
      result: %{
        tools: @tools
      }
    }

    {response, state}
  end

  defp handle_request(
         %{"method" => "tools/call", "id" => id, "params" => %{"name" => name} = params},
         state
       ) do
    arguments = Map.get(params, "arguments", %{})
    result = execute_tool(name, arguments, state)

    response =
      case result do
        {:ok, data} ->
          %{
            jsonrpc: "2.0",
            id: id,
            result: %{
              content: [
                %{
                  type: "text",
                  text: Jason.encode!(data)
                }
              ]
            }
          }

        {:error, message} ->
          %{
            jsonrpc: "2.0",
            id: id,
            result: %{
              content: [
                %{
                  type: "text",
                  text: Jason.encode!(%{error: message})
                }
              ],
              isError: true
            }
          }
      end

    {response, state}
  end

  defp handle_request(%{"method" => "ping", "id" => id}, state) do
    response = %{
      jsonrpc: "2.0",
      id: id,
      result: %{}
    }

    {response, state}
  end

  defp handle_request(%{"method" => method, "id" => id}, state) do
    response = %{
      jsonrpc: "2.0",
      id: id,
      error: %{
        code: -32601,
        message: "Method not found: #{method}"
      }
    }

    {response, state}
  end

  defp handle_request(_request, state) do
    {nil, state}
  end

  # Tool execution

  defp execute_tool("exint_index", args, state) do
    path = Map.get(args, "path", state.project_path)

    case Exint.Indexer.index(path) do
      {:ok, count} ->
        {:ok, %{success: true, records_indexed: count}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_tool("exint_query_def", %{"mfa" => mfa}, state) do
    Exint.Query.execute(:def, %{mfa: mfa}, project_root: state.project_path)
  end

  defp execute_tool("exint_query_refs", %{"mfa" => mfa}, state) do
    Exint.Query.execute(:refs, %{mfa: mfa}, project_root: state.project_path)
  end

  defp execute_tool("exint_query_callers", args, state) do
    mfa = Map.get(args, "mfa")
    depth = Map.get(args, "depth", 1)
    Exint.Query.execute(:callers, %{mfa: mfa, depth: depth}, project_root: state.project_path)
  end

  defp execute_tool("exint_query_callees", args, state) do
    mfa = Map.get(args, "mfa")
    depth = Map.get(args, "depth", 1)
    Exint.Query.execute(:callees, %{mfa: mfa, depth: depth}, project_root: state.project_path)
  end

  defp execute_tool("exint_query_routes", _args, state) do
    Exint.Query.execute(:routes, %{}, project_root: state.project_path)
  end

  defp execute_tool("exint_query_schema", %{"module" => module}, state) do
    Exint.Query.execute(:schema, %{module: module}, project_root: state.project_path)
  end

  defp execute_tool("exint_query_impact", %{"files" => files}, state) do
    Exint.Query.execute(:impact, %{files: files}, project_root: state.project_path)
  end

  defp execute_tool(name, _args, _state) do
    {:error, "Unknown tool: #{name}"}
  end
end
