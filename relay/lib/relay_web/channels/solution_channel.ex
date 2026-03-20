defmodule RelayWeb.SolutionChannel do
  use Phoenix.Channel

  @impl true
  def join("solutions:lobby", _params, socket) do
    {:ok, socket}
  end

  def join("solutions:lang:" <> _lang, _params, socket) do
    {:ok, socket}
  end

  def join(_topic, _params, _socket) do
    {:error, %{reason: "invalid topic"}}
  end

  @impl true
  def handle_in("publish_solution", payload, socket) do
    broadcast_from!(socket, "new_solution", payload)
    {:reply, :ok, socket}
  end

  def handle_in("query_network", payload, socket) do
    broadcast_from!(socket, "solution_query", payload)
    {:noreply, socket}
  end
end
