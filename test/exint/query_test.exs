defmodule Exint.QueryTest do
  use ExUnit.Case

  alias Exint.Query
  alias Exint.Index.Store

  @test_project_path "test_project"

  setup_all do
    # Ensure the test project is indexed
    unless Store.index_exists?(@test_project_path) do
      Exint.Indexer.index(@test_project_path)
    end

    :ok
  end

  describe "query_def/2" do
    test "returns function definition by MFA" do
      {:ok, result} = Query.execute(:def, %{mfa: "TestProject.Accounts.get_user/1"}, project_root: @test_project_path)

      assert length(result) == 1
      [def_record] = result

      assert def_record["kind"] == "function_def"
      assert def_record["data"]["module"] == "TestProject.Accounts"
      assert def_record["data"]["name"] == "get_user"
      assert def_record["data"]["arity"] == 1
    end

    test "returns empty list for non-existent function" do
      {:ok, result} = Query.execute(:def, %{mfa: "TestProject.NonExistent.foo/1"}, project_root: @test_project_path)

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
      {:ok, result} = Query.execute(:schema, %{module: "TestProject.Accounts.User"}, project_root: @test_project_path)

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
      {:ok, result} = Query.execute(:schema, %{module: "NonExistent.Schema"}, project_root: @test_project_path)

      assert result == []
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
