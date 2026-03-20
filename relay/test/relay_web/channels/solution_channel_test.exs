defmodule RelayWeb.SolutionChannelTest do
  use RelayWeb.ChannelCase

  setup do
    {:ok, _, socket} =
      RelayWeb.AgentSocket
      |> socket("agent:test-agent", %{agent_id: "test-agent"})
      |> subscribe_and_join(RelayWeb.SolutionChannel, "solutions:lobby")

    %{socket: socket}
  end

  test "joining solutions:lobby succeeds", %{socket: socket} do
    assert socket.assigns.agent_id == "test-agent"
  end

  test "joining language-specific channel succeeds" do
    {:ok, _, _socket} =
      RelayWeb.AgentSocket
      |> socket("agent:test-agent", %{agent_id: "test-agent"})
      |> subscribe_and_join(RelayWeb.SolutionChannel, "solutions:lang:elixir")
  end

  test "joining invalid topic fails" do
    assert {:error, %{reason: "invalid topic"}} =
             RelayWeb.AgentSocket
             |> socket("agent:test-agent", %{agent_id: "test-agent"})
             |> subscribe_and_join(RelayWeb.SolutionChannel, "solutions:invalid:topic")
  end

  test "publish_solution broadcasts to others", %{socket: socket} do
    payload = %{"problem_hash" => "abc123", "solution" => "fix the bug"}
    ref = push(socket, "publish_solution", payload)

    assert_reply ref, :ok
    assert_broadcast "new_solution", ^payload
  end

  test "query_network broadcasts query to others", %{socket: socket} do
    payload = %{"query" => "how to fix OTP crash", "language" => "elixir"}
    push(socket, "query_network", payload)

    assert_broadcast "solution_query", ^payload
  end
end
