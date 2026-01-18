defmodule TestProjectWeb.PageController do
  use TestProjectWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
