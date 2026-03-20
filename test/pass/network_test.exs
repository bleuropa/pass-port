defmodule Pass.NetworkTest do
  use ExUnit.Case, async: true

  alias Pass.Network

  test "status returns disconnected when no client is running" do
    info = Network.status()
    assert info.status == :disconnected
  end

  test "connected? returns false when no client is running" do
    refute Network.connected?()
  end

  test "publish_solution returns error when not connected" do
    assert {:error, :not_connected} = Network.publish_solution(%{})
  end
end
