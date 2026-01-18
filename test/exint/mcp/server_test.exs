defmodule Exint.MCP.ServerTest do
  use ExUnit.Case

  alias Exint.MCP.Server
  alias Exint.Index.Store

  @test_project_path "test_project"

  setup_all do
    # Ensure the test project is indexed
    unless Store.index_exists?(@test_project_path) do
      Exint.Indexer.index(@test_project_path)
    end

    :ok
  end

  defp make_state do
    %{project_path: @test_project_path, initialized: true}
  end

  describe "tools/list" do
    test "returns all available tools" do
      request = %{
        "method" => "tools/list",
        "id" => 1
      }

      {response, _state} = Server.handle_request(request, make_state())

      assert response.result.tools != nil
      tools = response.result.tools
      tool_names = Enum.map(tools, & &1.name)

      assert "index" in tool_names
      assert "function_definition" in tool_names
      assert "function_references" in tool_names
      assert "function_callers" in tool_names
      assert "function_callees" in tool_names
      assert "routes" in tool_names
      assert "schema" in tool_names
      assert "impact_analysis" in tool_names
    end
  end

  describe "function_definition tool" do
    test "returns function definition" do
      request = %{
        "method" => "tools/call",
        "id" => 1,
        "params" => %{
          "name" => "function_definition",
          "arguments" => %{"mfa" => "TestProject.Accounts.get_user/1"}
        }
      }

      {response, _state} = Server.handle_request(request, make_state())

      assert response.result.content != nil
      [content] = response.result.content
      result = Jason.decode!(content.text)

      assert length(result) == 1
      [def_record] = result
      assert def_record["data"]["module"] == "TestProject.Accounts"
      assert def_record["data"]["name"] == "get_user"
    end
  end

  describe "function_callers tool" do
    test "returns callers with depth" do
      request = %{
        "method" => "tools/call",
        "id" => 1,
        "params" => %{
          "name" => "function_callers",
          "arguments" => %{
            "mfa" => "TestProject.Accounts.create_user/1",
            "depth" => 1
          }
        }
      }

      {response, _state} = Server.handle_request(request, make_state())

      assert response.result.content != nil
      [content] = response.result.content
      result = Jason.decode!(content.text)

      assert is_list(result)
      # Should find UserController.create as a caller
      caller_mfas = Enum.map(result, & &1["mfa"])
      assert Enum.any?(caller_mfas, &String.contains?(&1, "UserController.create"))
    end
  end

  describe "function_callees tool" do
    test "returns callees with depth" do
      request = %{
        "method" => "tools/call",
        "id" => 1,
        "params" => %{
          "name" => "function_callees",
          "arguments" => %{
            "mfa" => "TestProject.Accounts.create_user/1",
            "depth" => 1
          }
        }
      }

      {response, _state} = Server.handle_request(request, make_state())

      assert response.result.content != nil
      [content] = response.result.content
      result = Jason.decode!(content.text)

      assert is_list(result)
      callee_mfas = Enum.map(result, & &1["mfa"])
      assert Enum.any?(callee_mfas, &String.contains?(&1, "Repo.insert"))
    end
  end

  describe "routes tool" do
    test "returns Phoenix routes" do
      request = %{
        "method" => "tools/call",
        "id" => 1,
        "params" => %{
          "name" => "routes",
          "arguments" => %{}
        }
      }

      {response, _state} = Server.handle_request(request, make_state())

      assert response.result.content != nil
      [content] = response.result.content
      result = Jason.decode!(content.text)

      assert length(result) > 0
      [route | _] = result
      assert route["data"]["verb"] != nil
      assert route["data"]["path"] != nil
    end
  end

  describe "schema tool" do
    test "returns Ecto schema" do
      request = %{
        "method" => "tools/call",
        "id" => 1,
        "params" => %{
          "name" => "schema",
          "arguments" => %{"module" => "TestProject.Accounts.User"}
        }
      }

      {response, _state} = Server.handle_request(request, make_state())

      assert response.result.content != nil
      [content] = response.result.content
      result = Jason.decode!(content.text)

      assert length(result) == 1
      [schema] = result
      assert schema["data"]["source"] == "users"
    end
  end

  describe "impact_analysis tool" do
    test "returns affected modules" do
      request = %{
        "method" => "tools/call",
        "id" => 1,
        "params" => %{
          "name" => "impact_analysis",
          "arguments" => %{"files" => ["lib/test_project/accounts.ex"]}
        }
      }

      {response, _state} = Server.handle_request(request, make_state())

      assert response.result.content != nil
      [content] = response.result.content
      result = Jason.decode!(content.text)

      assert Map.has_key?(result, "changed_modules")
      assert Map.has_key?(result, "affected_modules")
      assert "TestProject.Accounts" in result["changed_modules"]
    end
  end

  describe "unknown tool" do
    test "returns error for unknown tool" do
      request = %{
        "method" => "tools/call",
        "id" => 1,
        "params" => %{
          "name" => "nonexistent_tool",
          "arguments" => %{}
        }
      }

      {response, _state} = Server.handle_request(request, make_state())

      assert response.result.isError == true
    end
  end

  describe "initialize" do
    test "returns server info and capabilities" do
      request = %{
        "method" => "initialize",
        "id" => 1,
        "params" => %{}
      }

      {response, state} = Server.handle_request(request, %{project_path: ".", initialized: false})

      assert response.result.serverInfo.name == "exint"
      assert response.result.protocolVersion != nil
      assert state.initialized == true
    end
  end

  describe "ping" do
    test "returns empty result" do
      request = %{
        "method" => "ping",
        "id" => 1
      }

      {response, _state} = Server.handle_request(request, make_state())

      assert response.result == %{}
    end
  end
end
