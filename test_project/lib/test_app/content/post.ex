defmodule TestApp.Content.Post do
  @moduledoc """
  Blog post schema.
  """

  use Ecto.Schema

  schema "posts" do
    field :title, :string
    field :body, :string
    field :published, :boolean, default: false

    belongs_to :user, TestApp.Accounts.User
    has_many :comments, TestApp.Content.Comment

    timestamps()
  end
end
