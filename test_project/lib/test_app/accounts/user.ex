defmodule TestApp.Accounts.User do
  @moduledoc """
  User schema for accounts.
  """

  use Ecto.Schema

  schema "users" do
    field :email, :string
    field :name, :string
    field :age, :integer

    has_many :posts, TestApp.Content.Post
    has_one :profile, TestApp.Accounts.Profile

    timestamps()
  end
end
