defmodule Pass.Network.ClientTest do
  use Slipstream.SocketTest

  alias Pass.Network.Client

  @lobby "solutions:lobby"

  setup do
    pid =
      start_supervised!(
        {Client,
         agent_id: "pass_test123",
         url: "ws://localhost:4000/socket/agent/websocket",
         test_mode?: true,
         name: :"client_#{System.unique_integer([:positive])}"}
      )

    %{client: pid}
  end

  test "starts in disconnected status", %{client: client} do
    info = Client.status(client)
    assert info.status == :disconnected
    assert info.agent_id == "pass_test123"
    assert info.channels == []
  end

  test "transitions to connected on connect", %{client: client} do
    accept_connect(client)
    assert_join(@lobby, _, :ok)

    info = Client.status(client)
    assert info.status == :connected
    assert @lobby in info.channels
  end

  test "can subscribe to language channel after connect", %{client: client} do
    accept_connect(client)
    assert_join(@lobby, _, :ok)

    Client.subscribe("solutions:lang:elixir", client)
    assert_join("solutions:lang:elixir", _, :ok)

    info = Client.status(client)
    assert "solutions:lang:elixir" in info.channels
  end

  test "publish sends message on lobby channel", %{client: client} do
    accept_connect(client)
    assert_join(@lobby, _, :ok)

    payload = %{"problem_hash" => "abc123", "solution" => "fix it"}
    assert :ok = Client.publish(payload, client)
    assert_push(@lobby, "publish_solution", ^payload)
  end

  test "publish before connect does not crash", %{client: client} do
    assert :ok = Client.publish(%{}, client)
  end

  test "receives new_solution messages", %{client: client} do
    accept_connect(client)
    assert_join(@lobby, _, :ok)

    push(client, @lobby, "new_solution", %{"problem_signature" => "xyz"})
    # Client handles internally — no crash means success
    info = Client.status(client)
    assert info.status == :connected
  end

  test "receives solution_query messages", %{client: client} do
    accept_connect(client)
    assert_join(@lobby, _, :ok)

    push(client, @lobby, "solution_query", %{"query" => "how to fix OTP"})
    info = Client.status(client)
    assert info.status == :connected
  end

  test "handles disconnect and attempts reconnect", %{client: client} do
    accept_connect(client)
    assert_join(@lobby, _, :ok)

    disconnect(client, :normal)

    info = Client.status(client)
    assert info.status == :connecting
    assert info.channels == []
  end
end
