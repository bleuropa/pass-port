defmodule Pass.Matcher do
  @moduledoc """
  Multi-dimensional matching engine for fingerprint-based solution retrieval.

  Takes a query fingerprint and a list of `{solution, fingerprint}` candidates,
  scores each candidate across all facets, and returns ranked matches.
  """

  alias Pass.Fingerprint
  alias Pass.Match
  alias Pass.Matcher.Scorer

  @default_opts [min_score: 0.3, limit: 10]

  @spec match(Fingerprint.t(), [{Pass.Solution.t(), Fingerprint.t()}]) :: [Match.t()]
  def match(query, candidates) do
    match(query, candidates, [])
  end

  @spec match(Fingerprint.t(), [{Pass.Solution.t(), Fingerprint.t()}], keyword()) :: [Match.t()]
  def match(%Fingerprint{} = query, candidates, opts) when is_list(candidates) do
    opts = Keyword.merge(@default_opts, opts)
    min_score = Keyword.fetch!(opts, :min_score)
    limit = Keyword.fetch!(opts, :limit)

    candidates
    |> Enum.map(fn {solution, fingerprint} ->
      Scorer.score_with_breakdown(query, fingerprint, solution)
    end)
    |> Enum.filter(&(&1.score >= min_score))
    |> Enum.sort_by(& &1.score, :desc)
    |> Enum.take(limit)
  end

  @spec best_match(Fingerprint.t(), [{Pass.Solution.t(), Fingerprint.t()}]) :: Match.t() | nil
  def best_match(query, candidates) do
    case match(query, candidates, limit: 1) do
      [best] -> best
      [] -> nil
    end
  end
end
