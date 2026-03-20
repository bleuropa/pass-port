defmodule Pass.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    mode = Application.get_env(:pass, :serve_mode)

    children = base_children() ++ mode_children(mode)

    opts = [strategy: :one_for_one, name: Pass.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp base_children do
    if pass_initialized?() do
      [{Pass.Store, db_path: store_path()}]
    else
      []
    end
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
end
