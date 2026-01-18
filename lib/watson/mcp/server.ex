defmodule Watson.MCP.Server do
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
      description:
        "Force a full rebuild of the code index. Usually not needed - other tools auto-index incrementally. Use this to: (1) force a complete rebuild if the index seems stale, or (2) index a different project path.",
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
      description:
        "Find where a function is defined. Returns file path, line numbers, visibility (public/private), and whether it's a macro.",
      inputSchema: %{
        type: "object",
        properties: %{
          mfa: %{
            type: "string",
            description:
              "Function in Module.function/arity format, e.g., 'MyApp.Accounts.get_user/1'"
          }
        },
        required: ["mfa"]
      }
    },
    %{
      name: "function_references",
      description:
        "Find all call sites for a function. Returns file, line, and calling function for each location where the function is invoked.",
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
      description:
        "Find functions that call a given function (traverse up the call graph). Use depth=1 for direct callers, depth=2+ for transitive callers. Good for impact analysis.",
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
      description:
        "Find functions called by a given function (traverse down the call graph). Use depth=1 for direct calls, depth=2+ for transitive dependencies.",
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
      description:
        "List all Phoenix routes. Returns HTTP verb, path, controller, and action for each endpoint.",
      inputSchema: %{
        type: "object",
        properties: %{},
        required: []
      }
    },
    %{
      name: "schema",
      description:
        "Get Ecto schema structure: database table, fields with types, and associations (belongs_to, has_many, has_one).",
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
      name: "impact_analysis",
      description:
        "Analyze what's affected by changing files. Returns affected modules and suggested test files to run.",
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
    },
    %{
      name: "function_spec",
      description:
        "Get the @spec type signature for a function. Returns parameter types and return type.",
      inputSchema: %{
        type: "object",
        properties: %{
          mfa: %{
            type: "string",
            description:
              "Function in Module.function/arity format, e.g., 'MyApp.Accounts.create_user/1'"
          }
        },
        required: ["mfa"]
      }
    },
    %{
      name: "module_types",
      description: "List all type definitions (@type, @typep, @opaque, @callback) in a module.",
      inputSchema: %{
        type: "object",
        properties: %{
          module: %{
            type: "string",
            description: "Module name, e.g., 'MyApp.Accounts.User'"
          }
        },
        required: ["module"]
      }
    },
    %{
      name: "type_errors",
      description:
        "Get compiler type errors and warnings. Returns diagnostics from the Elixir type checker (Elixir 1.17+) and other compiler warnings.",
      inputSchema: %{
        type: "object",
        properties: %{},
        required: []
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

  @doc false
  def handle_line(line, state) do
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

  @doc false
  def handle_request(%{"method" => "initialize", "id" => id} = _request, state) do
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
          name: "watson",
          version: "0.1.0"
        }
      }
    }

    {response, %{state | initialized: true}}
  end

  def handle_request(%{"method" => "initialized"}, state) do
    {nil, state}
  end

  def handle_request(%{"method" => "tools/list", "id" => id}, state) do
    response = %{
      jsonrpc: "2.0",
      id: id,
      result: %{
        tools: @tools
      }
    }

    {response, state}
  end

  def handle_request(
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

  def handle_request(%{"method" => "ping", "id" => id}, state) do
    response = %{
      jsonrpc: "2.0",
      id: id,
      result: %{}
    }

    {response, state}
  end

  def handle_request(%{"method" => method, "id" => id}, state) do
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

  def handle_request(_request, state) do
    {nil, state}
  end

  # Tool execution

  defp execute_tool("index", args, state) do
    path = Map.get(args, "path", state.project_path)

    case Watson.Indexer.index(path) do
      {:ok, count} ->
        {:ok, %{success: true, records_indexed: count}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_tool("function_definition", %{"mfa" => mfa}, state) do
    with :ok <- ensure_index(state.project_path) do
      Watson.Query.execute(:def, %{mfa: mfa}, project_root: state.project_path)
    end
  end

  defp execute_tool("function_references", %{"mfa" => mfa}, state) do
    with :ok <- ensure_index(state.project_path) do
      Watson.Query.execute(:refs, %{mfa: mfa}, project_root: state.project_path)
    end
  end

  defp execute_tool("function_callers", args, state) do
    mfa = Map.get(args, "mfa")
    depth = Map.get(args, "depth", 1)

    with :ok <- ensure_index(state.project_path) do
      Watson.Query.execute(:callers, %{mfa: mfa, depth: depth}, project_root: state.project_path)
    end
  end

  defp execute_tool("function_callees", args, state) do
    mfa = Map.get(args, "mfa")
    depth = Map.get(args, "depth", 1)

    with :ok <- ensure_index(state.project_path) do
      Watson.Query.execute(:callees, %{mfa: mfa, depth: depth}, project_root: state.project_path)
    end
  end

  defp execute_tool("routes", _args, state) do
    with :ok <- ensure_index(state.project_path) do
      Watson.Query.execute(:routes, %{}, project_root: state.project_path)
    end
  end

  defp execute_tool("schema", %{"module" => module}, state) do
    with :ok <- ensure_index(state.project_path) do
      Watson.Query.execute(:schema, %{module: module}, project_root: state.project_path)
    end
  end

  defp execute_tool("impact_analysis", %{"files" => files}, state) do
    with :ok <- ensure_index(state.project_path) do
      Watson.Query.execute(:impact, %{files: files}, project_root: state.project_path)
    end
  end

  defp execute_tool("function_spec", %{"mfa" => mfa}, state) do
    with :ok <- ensure_index(state.project_path) do
      Watson.Query.execute(:spec, %{mfa: mfa}, project_root: state.project_path)
    end
  end

  defp execute_tool("module_types", %{"module" => module}, state) do
    with :ok <- ensure_index(state.project_path) do
      Watson.Query.execute(:types, %{module: module}, project_root: state.project_path)
    end
  end

  defp execute_tool("type_errors", _args, state) do
    with :ok <- ensure_index(state.project_path) do
      Watson.Query.execute(:type_errors, %{}, project_root: state.project_path)
    end
  end

  defp execute_tool(name, _args, _state) do
    {:error, "Unknown tool: #{name}"}
  end

  # Ensures the index is current before executing a query tool
  defp ensure_index(project_path) do
    case Watson.Indexer.ensure_index_current(project_path) do
      {:ok, :current} -> :ok
      {:ok, :updated, _count} -> :ok
      {:ok, :created, _count} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
