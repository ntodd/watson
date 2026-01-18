defmodule TestApp.Accounts.Profile do
  @moduledoc """
  User profile schema.
  """

  use Ecto.Schema

  schema "profiles" do
    field :bio, :string
    field :avatar_url, :string

    belongs_to :user, TestApp.Accounts.User

    timestamps()
  end
end
