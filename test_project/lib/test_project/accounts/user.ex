defmodule TestProject.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :name, :string
    field :age, :integer

    has_many :posts, TestProject.Content.Post
    has_one :profile, TestProject.Accounts.Profile

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :age])
    |> validate_required([:email])
    |> unique_constraint(:email)
  end
end
