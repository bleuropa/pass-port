defmodule Pass.Network.Client do
  @moduledoc """
  WebSocket client that connects to the Pass relay server via Phoenix channels.

  Uses Slipstream for automatic reconnection, heartbeats, and channel management.
  """

  use Slipstream

  alias Pass.Network.Handler

  require Logger

  @lobby_topic "solutions:lobby"

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    Slipstream.start_link(__MODULE__, opts, name: name)
  end

  # Public API

  def publish(solution_payload, server \\ __MODULE__) do
    GenServer.cast(server, {:publish, solution_payload})
    :ok
  end

  def subscribe(topic, server \\ __MODULE__) do
    GenServer.cast(server, {:subscribe, topic})
  end

  def disconnect(server \\ __MODULE__) do
    GenServer.cast(server, :disconnect)
  end

  def status(server \\ __MODULE__) do
    GenServer.call(server, :status)
  end

  # Slipstream callbacks

  @impl Slipstream
  def init(opts) do
    agent_id = Keyword.fetch!(opts, :agent_id)

    socket =
      new_socket()
      |> assign(:agent_id, agent_id)
      |> assign(:status, :disconnected)
      |> assign(:channels, [])
      |> assign(:identity, Keyword.get(opts, :identity))

    url = Keyword.get(opts, :url) || Application.get_env(:pass, :relay_url)

    if Keyword.get(opts, :test_mode?, false) do
      {:ok, assign(socket, :url, url)}
    else
      uri = build_uri(url, agent_id)
      {:ok, socket |> assign(:url, url) |> connect!(uri: uri)}
    end
  end

  @impl Slipstream
  def handle_connect(socket) do
    Logger.info("Connected to relay as #{socket.assigns.agent_id}")
    socket = assign(socket, :status, :connected)
    {:ok, join(socket, @lobby_topic)}
  end

  @impl Slipstream
  def handle_join(topic, _response, socket) do
    Logger.info("Joined #{topic}")
    channels = Enum.uniq([topic | socket.assigns.channels])
    {:ok, assign(socket, :channels, channels)}
  end

  @impl Slipstream
  def handle_message(_topic, "new_solution", payload, socket) do
    Logger.debug(
      "Received solution from network: #{inspect(Map.get(payload, "problem_signature", "unknown"))}"
    )

    Handler.handle_solution(payload)
    notify_listeners({:new_solution, payload})
    {:ok, socket}
  end

  def handle_message(_topic, "solution_query", payload, socket) do
    Logger.debug("Received query from network: #{inspect(Map.get(payload, "query", ""))}")
    notify_listeners({:solution_query, payload})
    {:ok, socket}
  end

  def handle_message(topic, event, payload, socket) do
    Logger.debug("Unhandled message on #{topic}: #{event} #{inspect(payload)}")
    {:ok, socket}
  end

  @impl Slipstream
  def handle_reply(_ref, _reply, socket) do
    {:ok, socket}
  end

  @impl Slipstream
  def handle_disconnect(_reason, socket) do
    Logger.warning("Disconnected from relay, attempting reconnect...")

    socket =
      socket
      |> assign(:status, :connecting)
      |> assign(:channels, [])

    case reconnect(socket) do
      %Slipstream.Socket{} = socket -> {:ok, socket}
      {:error, _} -> {:ok, socket}
    end
  end

  @impl Slipstream
  def handle_topic_close(topic, :left, socket) do
    channels = List.delete(socket.assigns.channels, topic)
    {:ok, assign(socket, :channels, channels)}
  end

  def handle_topic_close(topic, _reason, socket) do
    Logger.warning("Topic #{topic} closed, attempting rejoin...")
    channels = List.delete(socket.assigns.channels, topic)
    socket = assign(socket, :channels, channels)

    case rejoin(socket, topic) do
      %Slipstream.Socket{} = socket -> {:ok, socket}
      {:error, _} -> {:ok, socket}
    end
  end

  # GenServer callbacks

  @impl Slipstream
  def handle_call(:status, _from, socket) do
    info = %{
      status: socket.assigns.status,
      agent_id: socket.assigns.agent_id,
      channels: socket.assigns.channels
    }

    {:reply, info, socket}
  end

  @impl Slipstream
  def handle_cast({:publish, payload}, socket) do
    if @lobby_topic in socket.assigns.channels do
      push(socket, @lobby_topic, "publish_solution", payload)
    end

    {:noreply, socket}
  end

  def handle_cast({:subscribe, topic}, socket) do
    if socket.assigns.status == :connected do
      {:noreply, join(socket, topic)}
    else
      {:noreply, socket}
    end
  end

  def handle_cast(:disconnect, socket) do
    socket =
      socket
      |> assign(:status, :disconnected)
      |> assign(:channels, [])

    {:stop, :normal, Slipstream.disconnect(socket)}
  end

  # Private

  defp build_uri(url, agent_id) do
    separator = if String.contains?(url, "?"), do: "&", else: "?"
    "#{url}#{separator}agent_id=#{URI.encode_www_form(agent_id)}"
  end

  defp notify_listeners(message) do
    Registry.dispatch(Pass.Network.Registry, :network_events, fn entries ->
      for {pid, _value} <- entries do
        send(pid, {:pass_network, message})
      end
    end)
  rescue
    ArgumentError -> :ok
  end
end
