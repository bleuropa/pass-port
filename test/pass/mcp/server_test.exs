defmodule Pass.MCP.ServerTest do
  use ExUnit.Case, async: true

  alias Pass.Actions.GetStatus
  alias Pass.Actions.PublishSolution
  alias Pass.Actions.QuerySolutions
  alias Pass.MCP.Server

  test "server module exposes published tools" do
    publish = Server.__publish__()

    assert is_list(publish.tools)
    assert PublishSolution in publish.tools
    assert QuerySolutions in publish.tools
    assert GetStatus in publish.tools
    assert length(publish.tools) == 3
  end

  test "published tools list has no duplicates" do
    publish = Server.__publish__()
    assert Enum.uniq(publish.tools) == publish.tools
  end
end
