defmodule Watson.Test.Fixtures do
  @moduledoc """
  Test fixtures for watson tests.
  """

  def simple_module do
    """
    defmodule MyApp.Simple do
      @moduledoc "A simple module"

      def hello(name) do
        "Hello, " <> name
      end

      defp private_func do
        :ok
      end
    end
    """
  end

  def module_with_alias do
    """
    defmodule MyApp.WithAlias do
      alias MyApp.Other
      import Enum, only: [map: 2]
      require Logger

      def call_other(x) do
        Other.do_something(x)
      end
    end
    """
  end

  def phoenix_router do
    """
    defmodule MyAppWeb.Router do
      use Phoenix.Router

      scope "/", MyAppWeb do
        get "/", PageController, :home
        resources "/users", UserController
      end

      scope "/api", MyAppWeb.API do
        get "/status", StatusController, :index
      end
    end
    """
  end

  def ecto_schema do
    """
    defmodule MyApp.User do
      use Ecto.Schema

      schema "users" do
        field :email, :string
        field :name, :string

        has_many :posts, MyApp.Post
        belongs_to :organization, MyApp.Organization

        timestamps()
      end
    end
    """
  end

  def module_with_struct do
    """
    defmodule MyApp.Settings do
      defstruct [:theme, :locale, enabled: true]

      def new(opts \\\\ []) do
        struct(__MODULE__, opts)
      end
    end
    """
  end
end
