defmodule Pass.Network.Handler do
  @moduledoc """
  Handles incoming solutions from the relay network.

  Deserializes CloudEvents-wrapped solutions, deduplicates by problem_signature,
  and stores them locally.
  """

  require Logger

  alias Pass.Fingerprint
  alias Pass.Solution
  alias Pass.Store

  @doc """
  Processes an incoming solution payload from the network.

  Expects a CloudEvents-style map with a `"data"` key containing
  `"solution"` and optionally `"fingerprint"`.

  Skips storage if we already have a solution with the same problem_signature
  and equal or higher trust score.
  """
  def handle_solution(payload, store \\ Store) do
    with {:ok, solution_data, fingerprint_data} <- extract_data(payload),
         {:ok, solution} <- build_solution(solution_data),
         {:ok, fingerprint} <- build_fingerprint(fingerprint_data) do
      store_if_better(solution, fingerprint, store)
    else
      {:error, reason} ->
        Logger.warning("Failed to handle incoming solution: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Wraps a solution in a CloudEvents envelope for network broadcast.

  Options:
    - `:anonymous` — if true, strips agent_id and signature
  """
  def wrap_for_broadcast(solution, fingerprint, opts \\ []) do
    solution_map = Solution.to_map(solution)

    solution_map =
      if Keyword.get(opts, :anonymous, false) do
        solution_map
        |> Map.put("agent_id", "anonymous")
        |> Map.put("signature", nil)
      else
        solution_map
      end

    fingerprint_map =
      if fingerprint do
        Fingerprint.to_map(fingerprint)
      else
        nil
      end

    %{
      "specversion" => "1.0",
      "type" => "solution.published",
      "source" => "pass://#{solution_map["agent_id"]}",
      "id" => solution_map["id"],
      "time" => solution_map["inserted_at"],
      "datacontenttype" => "application/json",
      "data" => %{
        "solution" => solution_map,
        "fingerprint" => fingerprint_map
      }
    }
  end

  defp extract_data(%{"data" => %{"solution" => solution_data} = data}) do
    {:ok, solution_data, Map.get(data, "fingerprint")}
  end

  defp extract_data(%{"solution" => solution_data} = payload) do
    {:ok, solution_data, Map.get(payload, "fingerprint")}
  end

  defp extract_data(_), do: {:error, :invalid_payload}

  defp build_solution(data) when is_map(data) do
    {:ok, Solution.from_map(data)}
  rescue
    e -> {:error, {:bad_solution, Exception.message(e)}}
  end

  defp build_fingerprint(nil), do: {:ok, nil}

  defp build_fingerprint(data) when is_map(data) do
    {:ok, Fingerprint.from_map(data)}
  rescue
    e -> {:error, {:bad_fingerprint, Exception.message(e)}}
  end

  defp store_if_better(solution, fingerprint, store) do
    case Store.query([problem_signature: solution.problem_signature], store) do
      {:ok, [existing | _]} when existing.trust_score >= solution.trust_score ->
        Logger.debug(
          "Skipping incoming solution — existing trust #{existing.trust_score} >= #{solution.trust_score}"
        )

        {:ok, :skipped}

      _ ->
        case Store.insert(solution, fingerprint, store) do
          :ok ->
            Logger.debug("Stored incoming solution #{solution.id}")
            {:ok, :stored}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end
end
