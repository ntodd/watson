defmodule Watson.Extractors.PhoenixExtractorTest do
  use ExUnit.Case, async: true

  alias Watson.Extractors.PhoenixExtractor

  setup do
    tmp_dir = System.tmp_dir!() |> Path.join("watson_phx_test_#{:rand.uniform(10000)}")
    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  describe "extract_routes/1" do
    test "extracts basic routes", %{tmp_dir: tmp_dir} do
      file = Path.join(tmp_dir, "router.ex")

      File.write!(file, """
      defmodule MyAppWeb.Router do
        use Phoenix.Router

        scope "/", MyAppWeb do
          get "/", PageController, :home
          post "/login", AuthController, :login
        end
      end
      """)

      routes = PhoenixExtractor.extract_routes([file])

      assert length(routes) == 2

      get_route = Enum.find(routes, &(&1.verb == "GET"))
      assert get_route.path == "/"
      assert get_route.controller == "MyAppWeb.PageController"
      assert get_route.action == "home"

      post_route = Enum.find(routes, &(&1.verb == "POST"))
      assert post_route.path == "/login"
      assert post_route.controller == "MyAppWeb.AuthController"
      assert post_route.action == "login"
    end

    test "extracts resources routes", %{tmp_dir: tmp_dir} do
      file = Path.join(tmp_dir, "router.ex")

      File.write!(file, """
      defmodule MyAppWeb.Router do
        use Phoenix.Router

        scope "/", MyAppWeb do
          resources "/users", UserController
        end
      end
      """)

      routes = PhoenixExtractor.extract_routes([file])

      # resources generates: index, show, new, edit, create, update (put), update (patch), delete
      assert length(routes) == 8

      paths = Enum.map(routes, & &1.path) |> Enum.sort() |> Enum.uniq()
      assert "/users" in paths
      assert "/users/:id" in paths
      assert "/users/new" in paths
      assert "/users/:id/edit" in paths
    end

    test "extracts resources with only option", %{tmp_dir: tmp_dir} do
      file = Path.join(tmp_dir, "router.ex")

      File.write!(file, """
      defmodule MyAppWeb.Router do
        use Phoenix.Router

        scope "/", MyAppWeb do
          resources "/posts", PostController, only: [:index, :show]
        end
      end
      """)

      routes = PhoenixExtractor.extract_routes([file])

      assert length(routes) == 2
      actions = Enum.map(routes, & &1.action) |> Enum.sort()
      assert actions == ["index", "show"]
    end

    test "extracts nested scopes", %{tmp_dir: tmp_dir} do
      file = Path.join(tmp_dir, "router.ex")

      File.write!(file, """
      defmodule MyAppWeb.Router do
        use Phoenix.Router

        scope "/api", MyAppWeb.API do
          scope "/v1" do
            get "/users", UserController, :index
          end
        end
      end
      """)

      routes = PhoenixExtractor.extract_routes([file])

      assert length(routes) == 1
      [route] = routes
      assert route.path == "/api/v1/users"
      assert route.controller == "MyAppWeb.API.UserController"
    end

    test "extracts nested resources", %{tmp_dir: tmp_dir} do
      file = Path.join(tmp_dir, "router.ex")

      File.write!(file, """
      defmodule MyAppWeb.Router do
        use Phoenix.Router

        scope "/", MyAppWeb do
          resources "/posts", PostController do
            resources "/comments", CommentController, only: [:create, :delete]
          end
        end
      end
      """)

      routes = PhoenixExtractor.extract_routes([file])

      comment_routes = Enum.filter(routes, &String.contains?(&1.path, "comments"))
      assert length(comment_routes) == 2

      create_route = Enum.find(comment_routes, &(&1.action == "create"))
      assert create_route.path == "/posts/:post_id/comments"
      assert create_route.verb == "POST"
    end

    test "handles scope with module and options", %{tmp_dir: tmp_dir} do
      file = Path.join(tmp_dir, "router.ex")

      File.write!(file, """
      defmodule MyAppWeb.Router do
        use Phoenix.Router

        scope "/admin", MyAppWeb.Admin, as: :admin do
          get "/dashboard", DashboardController, :index
        end
      end
      """)

      routes = PhoenixExtractor.extract_routes([file])

      assert length(routes) == 1
      [route] = routes
      assert route.path == "/admin/dashboard"
      assert route.controller == "MyAppWeb.Admin.DashboardController"
    end

    test "ignores non-router files", %{tmp_dir: tmp_dir} do
      file = Path.join(tmp_dir, "not_router.ex")

      File.write!(file, """
      defmodule MyApp.NotARouter do
        def foo, do: :bar
      end
      """)

      routes = PhoenixExtractor.extract_routes([file])
      assert routes == []
    end
  end
end
