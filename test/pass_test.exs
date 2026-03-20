defmodule PassTest do
  use ExUnit.Case
  doctest Pass

  test "greets the world" do
    assert Pass.hello() == :world
  end
end
