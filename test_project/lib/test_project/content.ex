defmodule TestProject.Content do
  @moduledoc """
  The Content context.
  """

  import Ecto.Query
  alias TestProject.Repo
  alias TestProject.Content.{Post, Comment}

  def list_posts do
    Repo.all(Post)
  end

  def list_published_posts do
    from(p in Post, where: p.published == true)
    |> Repo.all()
  end

  def get_post(id) do
    Repo.get(Post, id)
  end

  def get_post!(id) do
    Repo.get!(Post, id)
  end

  def create_post(user, attrs \\ %{}) do
    %Post{user_id: user.id}
    |> Post.changeset(attrs)
    |> Repo.insert()
  end

  def update_post(%Post{} = post, attrs) do
    post
    |> Post.changeset(attrs)
    |> Repo.update()
  end

  def delete_post(%Post{} = post) do
    Repo.delete(post)
  end

  def change_post(%Post{} = post, attrs \\ %{}) do
    Post.changeset(post, attrs)
  end

  def list_comments(%Post{} = post) do
    from(c in Comment, where: c.post_id == ^post.id)
    |> Repo.all()
  end

  def create_comment(%Post{} = post, user, attrs \\ %{}) do
    %Comment{post_id: post.id, user_id: user.id}
    |> Comment.changeset(attrs)
    |> Repo.insert()
  end

  def delete_comment(%Comment{} = comment) do
    Repo.delete(comment)
  end
end
