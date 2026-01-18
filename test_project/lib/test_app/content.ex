defmodule TestApp.Content do
  @moduledoc """
  The Content context.
  """

  alias TestApp.Content.Post
  alias TestApp.Content.Comment
  alias TestApp.Repo

  @doc """
  Lists all posts.
  """
  def list_posts do
    Repo.all(Post)
  end

  @doc """
  Gets a post by ID.
  """
  def get_post(id) do
    Repo.get(Post, id)
  end

  @doc """
  Creates a post.
  """
  def create_post(user, attrs) do
    %Post{user_id: user.id}
    |> Post.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists comments for a post.
  """
  def list_comments(post) do
    Repo.all(from c in Comment, where: c.post_id == ^post.id)
  end

  @doc """
  Creates a comment.
  """
  def create_comment(post, user, attrs) do
    %Comment{post_id: post.id, user_id: user.id}
    |> Comment.changeset(attrs)
    |> Repo.insert()
  end
end
