defmodule TestApp.AccountsTest do
  use ExUnit.Case

  alias TestApp.Accounts
  alias TestApp.Accounts.User

  describe "get_user/1" do
    test "returns user when found" do
      user = Accounts.get_user(1)
      assert user != nil
    end
  end

  describe "create_user/1" do
    test "creates user with valid attrs" do
      {:ok, user} = Accounts.create_user(%{email: "test@example.com"})
      assert user.email == "test@example.com"
    end
  end
end
