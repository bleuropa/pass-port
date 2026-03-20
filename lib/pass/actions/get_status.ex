defmodule Pass.Actions.GetStatus do
  @moduledoc """
  Jido action that returns the current Pass agent status.
  """

  use Jido.Action,
    name: "get_status",
    description: "Returns the current Pass agent status including identity and store stats",
    schema: [
      store: [type: :atom, doc: "Store GenServer name"]
    ]

  alias Pass.Identity

  @impl true
  def run(params, _context) do
    identity_path = Map.get(params, :identity_path) || Identity.default_identity_path()
    store = Map.get(params, :store) || Pass.Store

    agent_id =
      case Identity.load_keypair(identity_path) do
        {:ok, keys} -> Identity.agent_id(keys.public_key)
        {:error, _} -> nil
      end

    stats =
      try do
        case Pass.Store.stats(store) do
          {:ok, s} -> s
          {:error, _} -> nil
        end
      catch
        :exit, _ -> nil
      end

    if stats do
      {:ok,
       %{
         agent_id: agent_id,
         identity_initialized: agent_id != nil,
         contributions: stats.total,
         by_language: stats.by_language,
         avg_trust: stats.avg_trust,
         network_status: :local
       }}
    else
      {:ok,
       %{
         agent_id: agent_id,
         identity_initialized: agent_id != nil,
         contributions: 0,
         by_language: %{},
         avg_trust: 0.0,
         network_status: :local
       }}
    end
  end
end
