defmodule WatsonTest do
  use ExUnit.Case

  test "version returns current version" do
    assert Watson.version() == "0.1.0"
  end
end
