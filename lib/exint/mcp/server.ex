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
      name: "index",
      description: "Build a searchable code graph for an Elixir/Phoenix project. Run this once before using other tools. The index persists in .exint/ - re-run after code changes to update.",
      inputSchema: %{
        type: "object",
        properties: %{
          path: %{
            type: "string",
            description: "Path to the Mix project root (defaults to current directory)"
          }
        },
        required: []
      }
    },
    %{
      name: "function_definition",
      description: "Find where a function is defined. Returns file path, line numbers, visibility (public/private), and whether it's a macro.",
      inputSchema: %{
        type: "object",
        properties: %{
          mfa: %{
            type: "string",
            description: "Function in Module.function/arity format, e.g., 'MyApp.Accounts.get_user/1'"
          }
        },
        required: ["mfa"]
      }
    },
    %{
      name: "function_references",
      description: "Find all call sites for a function. Returns file, line, and calling function for each location where the function is invoked.",
      inputSchema: %{
        type: "object",
        properties: %{
          mfa: %{
            type: "string",
            description: "Function in Module.function/arity format"
          }
        },
        required: ["mfa"]
      }
    },
    %{
      name: "function_callers",
      description: "Find functions that call a given function (traverse up the call graph). Use depth=1 for direct callers, depth=2+ for transitive callers. Good for impact analysis.",
      inputSchema: %{
        type: "object",
        properties: %{
          mfa: %{
            type: "string",
            description: "Function in Module.function/arity format"
          },
          depth: %{
            type: "integer",
            description: "Levels up the call graph (default: 1)"
          }
        },
        required: ["mfa"]
      }
    },
    %{
      name: "function_callees",
      description: "Find functions called by a given function (traverse down the call graph). Use depth=1 for direct calls, depth=2+ for transitive dependencies.",
      inputSchema: %{
        type: "object",
        properties: %{
          mfa: %{
            type: "string",
            description: "Function in Module.function/arity format"
          },
          depth: %{
            type: "integer",
            description: "Levels down the call graph (default: 1)"
          }
        },
        required: ["mfa"]
      }
    },
    %{
      name: "routes",
      description: "List all Phoenix routes. Returns HTTP verb, path, controller, and action for each endpoint.",
      inputSchema: %{
        type: "object",
        properties: %{},
        required: []
      }
    },
    %{
      name: "schema",
      description: "Get Ecto schema structure: database table, fields with types, and associations (belongs_to, has_many, has_one).",
      inputSchema: %{
        type: "object",
        properties: %{
          module: %{
            type: "string",
            description: "Ecto schema module, e.g., 'MyApp.Accounts.User'"
          }
        },
        required: ["module"]
      }
    },
    %{
      name: "impact",
      description: "Analyze what's affected by changing files. Returns affected modules and suggested test files to run.",
      inputSchema: %{
        type: "object",
        properties: %{
          files: %{
            type: "array",
            items: %{type: "string"},
            description: "File paths that have or will change"
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

  defp execute_tool("index", args, state) do
    path = Map.get(args, "path", state.project_path)

    case Exint.Indexer.index(path) do
      {:ok, count} ->
        {:ok, %{success: true, records_indexed: count}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_tool("function_definition", %{"mfa" => mfa}, state) do
    Exint.Query.execute(:def, %{mfa: mfa}, project_root: state.project_path)
  end

  defp execute_tool("function_references", %{"mfa" => mfa}, state) do
    Exint.Query.execute(:refs, %{mfa: mfa}, project_root: state.project_path)
  end

  defp execute_tool("function_callers", args, state) do
    mfa = Map.get(args, "mfa")
    depth = Map.get(args, "depth", 1)
    Exint.Query.execute(:callers, %{mfa: mfa, depth: depth}, project_root: state.project_path)
  end

  defp execute_tool("function_callees", args, state) do
    mfa = Map.get(args, "mfa")
    depth = Map.get(args, "depth", 1)
    Exint.Query.execute(:callees, %{mfa: mfa, depth: depth}, project_root: state.project_path)
  end

  defp execute_tool("routes", _args, state) do
    Exint.Query.execute(:routes, %{}, project_root: state.project_path)
  end

  defp execute_tool("schema", %{"module" => module}, state) do
    Exint.Query.execute(:schema, %{module: module}, project_root: state.project_path)
  end

  defp execute_tool("impact", %{"files" => files}, state) do
    Exint.Query.execute(:impact, %{files: files}, project_root: state.project_path)
  end

  defp execute_tool(name, _args, _state) do
    {:error, "Unknown tool: #{name}"}
  end
end
