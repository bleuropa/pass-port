defmodule Pass.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    mode = Application.get_env(:pass, :serve_mode)

    children = base_children() ++ mode_children(mode)

    result = Supervisor.start_link(children, strategy: :one_for_one, name: Pass.Supervisor)

    if mode in [:mcp, :http] || match?({:http, _}, mode) do
      maybe_auto_connect()
    end

    result
  end

  defp base_children do
    children = [
      {Registry, keys: :duplicate, name: Pass.Network.Registry},
      {DynamicSupervisor, name: Pass.Network.Supervisor, strategy: :one_for_one}
    ]

    children =
      if pass_initialized?() do
        children ++ [{Pass.Store, db_path: store_path()}]
      else
        children
      end

    children
  end

  defp mode_children(:mcp) do
    Jido.MCP.Server.server_children(Pass.MCP.Server, transport: :stdio)
  end

  defp mode_children({:http, port}) do
    [{Bandit, plug: Pass.HTTP.Router, port: port}]
  end

  defp mode_children(_), do: []

  defp pass_initialized? do
    File.exists?(store_path())
  end

  defp store_path do
    Path.expand("~/.pass/solutions.db")
  end

  defp maybe_auto_connect do
    config = Pass.Config.load()

    if config["auto_connect"] && pass_initialized?() do
      identity_path = Pass.Identity.default_identity_path()

      case Pass.Identity.load_keypair(identity_path) do
        {:ok, keys} ->
          agent_id = Pass.Identity.agent_id(keys.public_key)
          url = config["relay_url"]
          Pass.Network.connect(agent_id: agent_id, identity: keys, url: url)

        {:error, _} ->
          :ok
      end
    end
  end
end
