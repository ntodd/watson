defmodule TestProject.Accounts.Profile do
  use Ecto.Schema
  import Ecto.Changeset

  schema "profiles" do
    field :bio, :string
    field :avatar_url, :string

    belongs_to :user, TestProject.Accounts.User

    timestamps()
  end

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [:bio, :avatar_url, :user_id])
    |> validate_required([:user_id])
  end
end
