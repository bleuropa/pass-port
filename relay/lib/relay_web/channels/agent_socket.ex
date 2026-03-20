defmodule RelayWeb.AgentSocket do
  use Phoenix.Socket

  channel "solutions:*", RelayWeb.SolutionChannel

  @impl true
  def connect(%{"agent_id" => agent_id, "challenge_response" => sig_b64, "challenge" => challenge, "public_key" => pk_b64}, socket, _connect_info) do
    with {:ok, public_key} <- Base.decode64(pk_b64),
         {:ok, signature} <- Base.decode64(sig_b64),
         true <- verify_identity(agent_id, public_key),
         true <- Ed25519.valid_signature?(signature, challenge, public_key) do
      {:ok, assign(socket, %{agent_id: agent_id, public_key: public_key})}
    else
      _ -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "agent:#{socket.assigns.agent_id}"

  defp verify_identity(agent_id, public_key) do
    expected_prefix =
      public_key
      |> Base.url_encode64(padding: false)
      |> binary_part(0, 7)

    agent_id == "pass_" <> expected_prefix
  end
end
