defmodule Pass.HTTP.Router do
  @moduledoc """
  HTTP API router for Pass, serving the same actions available via MCP.

  Endpoints:
    POST /api/publish    — publish a solution
    POST /api/query      — query for solutions
    GET  /api/status     — agent status
    GET  /health         — health check
  """

  use Plug.Router

  alias Pass.Actions.GetStatus
  alias Pass.Actions.PublishSolution
  alias Pass.Actions.QuerySolutions
  alias Pass.Match
  alias Pass.Solution

  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(:dispatch)

  post "/api/publish" do
    case PublishSolution.run(atomize_keys(conn.body_params), %{}) do
      {:ok, result} ->
        send_json(conn, 200, result)

      {:error, reason} ->
        send_json(conn, 422, %{error: to_string(reason)})
    end
  end

  post "/api/query" do
    case QuerySolutions.run(atomize_keys(conn.body_params), %{}) do
      {:ok, result} ->
        send_json(conn, 200, serialize_result(result))

      {:error, reason} ->
        send_json(conn, 422, %{error: to_string(reason)})
    end
  end

  get "/api/status" do
    {:ok, result} = GetStatus.run(%{}, %{})
    send_json(conn, 200, result)
  end

  get "/health" do
    send_json(conn, 200, %{status: "ok"})
  end

  match _ do
    send_json(conn, 404, %{error: "not found"})
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end

  @allowed_keys ~w(
    problem_description solution_content language framework runtime tags
    verification domain target ecosystem versions error_class constraints
    goal symptoms problem min_trust min_score limit store
  )a

  defp atomize_keys(map) when is_map(map) do
    allowed_strings = Map.new(@allowed_keys, fn k -> {Atom.to_string(k), k} end)

    Map.new(map, fn
      {k, v} when is_binary(k) ->
        case Map.fetch(allowed_strings, k) do
          {:ok, atom_key} -> {atom_key, v}
          :error -> {k, v}
        end

      {k, v} ->
        {k, v}
    end)
  end

  defp serialize_result(%{matches: matches} = result) when is_list(matches) do
    %{result | matches: Enum.map(matches, &serialize_match/1)}
  end

  defp serialize_result(result), do: result

  defp serialize_match(%Match{} = m) do
    %{
      score: m.score,
      confidence: m.confidence,
      breakdown: m.breakdown,
      solution: if(m.solution, do: Solution.to_map(m.solution), else: nil)
    }
  end

  defp serialize_match(other), do: other
end
