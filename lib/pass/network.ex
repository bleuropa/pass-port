defmodule Pass.Network do
  @moduledoc """
  High-level API for the Pass relay network.

  Manages WebSocket connections to the relay server for solution sharing
  between agents.
  """

  alias Pass.Network.Client

  @doc """
  Connects to the relay server.

  Options:
    - `:agent_id` — required, the agent's identity
    - `:identity` — optional, the keypair for signing
    - `:url` — optional, overrides configured relay URL
  """
  def connect(opts \\ []) do
    client_opts =
      opts
      |> Keyword.put_new(:name, Client)
      |> Keyword.put_new(:url, Application.get_env(:pass, :relay_url))

    case DynamicSupervisor.start_child(Pass.Network.Supervisor, {Client, client_opts}) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Disconnects from the relay server.
  """
  def disconnect do
    Client.disconnect()
  end

  @doc """
  Returns connection status info.
  """
  def status do
    Client.status()
  catch
    :exit, _ -> %{status: :disconnected, agent_id: nil, channels: []}
  end

  @doc """
  Returns true if connected to the relay.
  """
  def connected? do
    status().status == :connected
  end

  @doc """
  Publishes a solution to the network.

  Returns `:ok` or `{:error, reason}`.
  """
  def publish_solution(solution_payload) do
    if GenServer.whereis(Client) do
      Client.publish(solution_payload)
    else
      {:error, :not_connected}
    end
  end

  @doc """
  Subscribes to a language-specific channel.

  Example: `Pass.Network.subscribe("solutions:lang:elixir")`
  """
  def subscribe(topic) do
    Client.subscribe(topic)
  end
end
