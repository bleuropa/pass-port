defmodule RelayWeb.AgentSocket do
  use Phoenix.Socket

  channel "solutions:*", RelayWeb.SolutionChannel

  @impl true
  def connect(%{"agent_id" => agent_id}, socket, _connect_info) do
    {:ok, assign(socket, :agent_id, agent_id)}
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "agent:#{socket.assigns.agent_id}"
end
