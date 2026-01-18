defmodule TestProjectWeb.Router do
  use TestProjectWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TestProjectWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TestProjectWeb do
    pipe_through :browser

    get "/", PageController, :home
    resources "/users", UserController
    resources "/posts", PostController
  end

  scope "/api", TestProjectWeb.API do
    pipe_through :api

    resources "/users", UserController, except: [:new, :edit]
  end
end
