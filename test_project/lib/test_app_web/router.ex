defmodule TestAppWeb.Router do
  use Phoenix.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TestAppWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/about", PageController, :about

    resources "/users", UserController
    resources "/posts", PostController do
      resources "/comments", CommentController, only: [:create, :delete]
    end
  end

  scope "/api", TestAppWeb.API do
    pipe_through :api

    get "/users", UserController, :index
    get "/users/:id", UserController, :show
    post "/users", UserController, :create
    put "/users/:id", UserController, :update
    delete "/users/:id", UserController, :delete

    resources "/posts", PostController, except: [:new, :edit]
  end

  scope "/admin", TestAppWeb.Admin, as: :admin do
    pipe_through :browser

    get "/", DashboardController, :index
    resources "/users", UserController
  end
end
