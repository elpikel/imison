defmodule ImisionTest do
  use ExUnit.Case

  doctest Imision

  test "greets the world" do
    assert Imision.hello() == :world
  end
end
