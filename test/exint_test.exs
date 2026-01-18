defmodule ExintTest do
  use ExUnit.Case

  test "version returns current version" do
    assert Exint.version() == "0.1.0"
  end
end
