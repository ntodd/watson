defmodule TestApp.Content.Comment do
  @moduledoc """
  Comment schema.
  """

  use Ecto.Schema

  schema "comments" do
    field :body, :string

    belongs_to :post, TestApp.Content.Post
    belongs_to :user, TestApp.Accounts.User

    timestamps()
  end
end
