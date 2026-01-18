defmodule TestProject.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query
  alias TestProject.Repo
  alias TestProject.Accounts.{User, Profile}

  def list_users do
    Repo.all(User)
  end

  def get_user(id) do
    Repo.get(User, id)
  end

  def get_user!(id) do
    Repo.get!(User, id)
  end

  def get_user_by_email(email) do
    Repo.get_by(User, email: email)
  end

  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end

  def get_profile(%User{} = user) do
    Repo.get_by(Profile, user_id: user.id)
  end

  def create_profile(%User{} = user, attrs \\ %{}) do
    %Profile{user_id: user.id}
    |> Profile.changeset(attrs)
    |> Repo.insert()
  end
end
