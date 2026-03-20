defmodule Pass.Reputation do
  @moduledoc """
  Agent reputation scoring based on contribution and consumption patterns.

  Tracks how much an agent contributes solutions and how successfully those
  solutions are consumed by others.
  """

  alias Pass.Store

  @doc """
  Computes a reputation score (0.0-1.0) for an agent.

  Returns 0.5 for unknown agents.
  """
  @spec score(String.t()) :: float()
  def score(agent_id), do: score(agent_id, Store)

  @spec score(String.t(), GenServer.server()) :: float()
  def score(agent_id, server) do
    case Store.get_agent(agent_id, server) do
      {:ok, agent} -> compute_reputation(agent)
      {:error, :not_found} -> 0.5
    end
  end

  @doc """
  Records that an agent contributed a solution.
  """
  @spec record_contribution(String.t(), GenServer.server()) :: :ok | {:error, term()}
  def record_contribution(agent_id, server \\ Store) do
    ensure_agent(agent_id, server)
    Store.update_agent_stats(agent_id, %{"solutions_contributed" => 1}, server)
  end

  @doc """
  Records a successful consumption: increments solutions_consumed for the consumer
  and successful_consumptions for the contributor.
  """
  @spec record_consumption(String.t(), String.t(), GenServer.server()) :: :ok | {:error, term()}
  def record_consumption(consumer_id, contributor_id, server \\ Store) do
    ensure_agent(consumer_id, server)
    ensure_agent(contributor_id, server)
    :ok = Store.update_agent_stats(consumer_id, %{"solutions_consumed" => 1}, server)
    :ok = Store.update_agent_stats(contributor_id, %{"successful_consumptions" => 1}, server)
    :ok
  end

  @doc """
  Creates an agent record if one doesn't already exist.
  """
  @spec ensure_agent(String.t(), GenServer.server()) :: :ok
  def ensure_agent(agent_id, server \\ Store) do
    case Store.get_agent(agent_id, server) do
      {:ok, _} ->
        :ok

      {:error, :not_found} ->
        Store.upsert_agent(%{agent_id: agent_id}, server)
    end
  end

  defp compute_reputation(agent) do
    contributed = get_int(agent, "solutions_contributed")
    successful = get_int(agent, "successful_consumptions")

    contribution_score = successful / max(contributed, 1)
    consistency_score = min(contributed / 10, 1.0)

    reputation = 0.6 * contribution_score + 0.4 * consistency_score

    reputation
    |> max(0.0)
    |> min(1.0)
    |> Float.round(4)
  end

  defp get_int(agent, key) do
    val = agent[key]

    cond do
      is_integer(val) -> val
      is_float(val) -> trunc(val)
      true -> 0
    end
  end
end
