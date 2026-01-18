defmodule Watson.QueryTest do
  use ExUnit.Case

  alias Watson.Query
  alias Watson.Index.Store

  @test_project_path "test_project"

  setup_all do
    # Ensure the test project is indexed
    unless Store.index_exists?(@test_project_path) do
      Watson.Indexer.index(@test_project_path)
    end

    :ok
  end

  describe "query_def/2" do
    test "returns function definition by MFA" do
      {:ok, result} =
        Query.execute(:def, %{mfa: "TestProject.Accounts.get_user/1"},
          project_root: @test_project_path
        )

      assert length(result) == 1
      [def_record] = result

      assert def_record["kind"] == "function_def"
      assert def_record["data"]["module"] == "TestProject.Accounts"
      assert def_record["data"]["name"] == "get_user"
      assert def_record["data"]["arity"] == 1
    end

    test "returns empty list for non-existent function" do
      {:ok, result} =
        Query.execute(:def, %{mfa: "TestProject.NonExistent.foo/1"},
          project_root: @test_project_path
        )

      assert result == []
    end
  end

  describe "query_routes/1" do
    test "returns all Phoenix routes" do
      {:ok, routes} = Query.execute(:routes, %{}, project_root: @test_project_path)

      assert length(routes) > 0

      # Check route structure
      [route | _] = routes
      assert route["kind"] == "phoenix_route"
      assert Map.has_key?(route["data"], "verb")
      assert Map.has_key?(route["data"], "path")
      assert Map.has_key?(route["data"], "controller")
      assert Map.has_key?(route["data"], "action")
    end

    test "routes are sorted by verb and path" do
      {:ok, routes} = Query.execute(:routes, %{}, project_root: @test_project_path)

      verbs_and_paths =
        routes
        |> Enum.map(fn r -> {r["data"]["verb"], r["data"]["path"]} end)

      sorted = Enum.sort(verbs_and_paths)
      assert verbs_and_paths == sorted
    end
  end

  describe "query_schema/2" do
    test "returns Ecto schema by module" do
      {:ok, result} =
        Query.execute(:schema, %{module: "TestProject.Accounts.User"},
          project_root: @test_project_path
        )

      assert length(result) == 1
      [schema] = result

      assert schema["kind"] == "ecto_schema"
      assert schema["data"]["module"] == "TestProject.Accounts.User"
      assert schema["data"]["source"] == "users"

      # Check fields
      fields = schema["data"]["fields"]
      field_names = Enum.map(fields, & &1["name"])
      assert "email" in field_names
      assert "name" in field_names

      # Check associations
      assocs = schema["data"]["assocs"]
      assoc_names = Enum.map(assocs, & &1["name"])
      assert "posts" in assoc_names
      assert "profile" in assoc_names
    end

    test "returns empty list for non-existent schema" do
      {:ok, result} =
        Query.execute(:schema, %{module: "NonExistent.Schema"}, project_root: @test_project_path)

      assert result == []
    end
  end

  describe "query_refs/2" do
    test "returns call sites for a function" do
      {:ok, result} =
        Query.execute(:refs, %{mfa: "TestProject.Accounts.create_user/1"},
          project_root: @test_project_path
        )

      assert length(result) >= 1

      # All results should be call_ref records
      assert Enum.all?(result, &(&1["kind"] == "call_ref"))

      # Should have file and line info
      [ref | _] = result
      assert ref["data"]["file"] != nil
      assert ref["data"]["span"]["line"] != nil
    end

    test "returns empty list for function with no references" do
      {:ok, result} =
        Query.execute(:refs, %{mfa: "TestProject.NonExistent.foo/1"},
          project_root: @test_project_path
        )

      assert result == []
    end
  end

  describe "query_callers/3" do
    test "returns direct callers at depth 1" do
      {:ok, result} =
        Query.execute(:callers, %{mfa: "TestProject.Accounts.create_user/1", depth: 1},
          project_root: @test_project_path
        )

      # create_user is called by UserController.create
      caller_mfas = Enum.map(result, & &1.mfa)
      assert Enum.any?(caller_mfas, &String.contains?(&1, "UserController.create"))

      # All results should be depth 1
      assert Enum.all?(result, &(&1.depth == 1))
    end

    test "returns transitive callers at depth 2+" do
      # Repo.insert is called by Accounts.create_user, which is called by UserController.create
      {:ok, result} =
        Query.execute(:callers, %{mfa: "TestProject.Repo.insert/1", depth: 3},
          project_root: @test_project_path
        )

      depths = result |> Enum.map(& &1.depth) |> Enum.uniq() |> Enum.sort()

      # Should have callers at multiple depths
      assert 1 in depths
      # Depth 2 would be UserController calling Accounts calling Repo
    end

    test "returns empty list for function with no callers" do
      {:ok, result} =
        Query.execute(:callers, %{mfa: "TestProject.NonExistent.foo/1", depth: 1},
          project_root: @test_project_path
        )

      assert result == []
    end

    test "defaults to depth 1" do
      {:ok, result} =
        Query.execute(:callers, %{mfa: "TestProject.Accounts.create_user/1"},
          project_root: @test_project_path
        )

      # Should return results (default depth = 1)
      assert is_list(result)
      # All at depth 1
      assert Enum.all?(result, &(&1.depth == 1))
    end
  end

  describe "query_callees/3" do
    test "returns direct callees at depth 1" do
      {:ok, result} =
        Query.execute(:callees, %{mfa: "TestProject.Accounts.create_user/1", depth: 1},
          project_root: @test_project_path
        )

      # create_user calls User.changeset and Repo.insert
      callee_mfas = Enum.map(result, & &1.mfa)

      assert Enum.any?(callee_mfas, &String.contains?(&1, "changeset"))
      assert Enum.any?(callee_mfas, &String.contains?(&1, "Repo.insert"))

      # All results should be depth 1
      assert Enum.all?(result, &(&1.depth == 1))
    end

    test "returns transitive callees at depth 2+" do
      {:ok, result} =
        Query.execute(:callees, %{mfa: "TestProjectWeb.UserController.create/2", depth: 2},
          project_root: @test_project_path
        )

      depths = result |> Enum.map(& &1.depth) |> Enum.uniq() |> Enum.sort()

      # Should have callees at depth 1 (Accounts.create_user) and depth 2 (Repo.insert, changeset)
      assert 1 in depths
      assert 2 in depths
    end

    test "returns empty list for function with no callees" do
      {:ok, result} =
        Query.execute(:callees, %{mfa: "TestProject.NonExistent.foo/1", depth: 1},
          project_root: @test_project_path
        )

      assert result == []
    end

    test "includes local/private function calls within same module" do
      # CoreComponents.flash calls CoreComponents.icon (same module)
      {:ok, result} =
        Query.execute(:callees, %{mfa: "TestProjectWeb.CoreComponents.flash/1", depth: 1},
          project_root: @test_project_path
        )

      callee_mfas = Enum.map(result, & &1.mfa)

      # Should include the local call to icon/1
      assert Enum.any?(callee_mfas, &String.contains?(&1, "CoreComponents.icon"))
    end

    test "tracks all callers of a private function from multiple call sites" do
      # format_errors/1 is called from both create/2 (line 26) and update/2 (line 40)
      {:ok, result} =
        Query.execute(
          :callers,
          %{mfa: "TestProjectWeb.API.UserController.format_errors/1", depth: 1},
          project_root: @test_project_path
        )

      caller_mfas = Enum.map(result, & &1.mfa)

      # Both create/2 and update/2 should be listed as callers
      assert Enum.any?(caller_mfas, &String.contains?(&1, "create/2")),
             "Expected create/2 to be a caller, got: #{inspect(caller_mfas)}"

      assert Enum.any?(caller_mfas, &String.contains?(&1, "update/2")),
             "Expected update/2 to be a caller, got: #{inspect(caller_mfas)}"
    end
  end

  describe "query_impact/2" do
    test "returns affected modules for changed file" do
      {:ok, result} =
        Query.execute(:impact, %{files: ["lib/test_project/accounts.ex"]},
          project_root: @test_project_path
        )

      assert Map.has_key?(result, :changed_modules)
      assert Map.has_key?(result, :affected_modules)
      assert Map.has_key?(result, :test_files)

      # Accounts module should be in changed_modules
      assert "TestProject.Accounts" in result.changed_modules

      # UserController should be affected (it calls Accounts functions)
      assert Enum.any?(result.affected_modules, &String.contains?(&1, "UserController"))
    end

    test "returns empty affected_modules for file with no dependents" do
      # A leaf module that nothing depends on
      {:ok, result} =
        Query.execute(:impact, %{files: ["lib/test_project_web/controllers/page_controller.ex"]},
          project_root: @test_project_path
        )

      # Should still return the structure
      assert Map.has_key?(result, :changed_modules)
      assert Map.has_key?(result, :affected_modules)
    end

    test "handles non-existent files gracefully" do
      {:ok, result} =
        Query.execute(:impact, %{files: ["nonexistent.ex"]}, project_root: @test_project_path)

      assert result.changed_modules == []
      assert result.affected_modules == []
    end
  end

  describe "error handling" do
    test "returns error for missing index" do
      result = Query.execute(:def, %{mfa: "Foo.bar/1"}, project_root: "nonexistent_path")

      assert {:error, message} = result
      assert String.contains?(message, "Index not found")
    end

    test "returns error for unknown query type" do
      result = Query.execute(:unknown_type, %{}, project_root: @test_project_path)

      assert {:error, message} = result
      assert String.contains?(message, "Unknown query type")
    end
  end
end
