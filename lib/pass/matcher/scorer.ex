defmodule Pass.Matcher.Scorer do
  @moduledoc """
  Weighted score combination for fingerprint matching.

  Computes a final score from individual facet scores using configurable weights.
  """

  alias Pass.Fingerprint
  alias Pass.Match
  alias Pass.Matcher.Facets

  @weights %{
    domain: 0.10,
    target: 0.10,
    ecosystem: 0.20,
    versions: 0.10,
    error_class: 0.10,
    constraints: 0.05,
    goal: 0.15,
    symptoms: 0.20
  }

  @spec score(Fingerprint.t(), Fingerprint.t()) :: float()
  def score(query, candidate) do
    breakdown = compute_breakdown(query, candidate)

    breakdown
    |> Enum.map(fn {facet, {raw_score, _type, _detail}} -> @weights[facet] * raw_score end)
    |> Enum.sum()
    |> Float.round(4)
  end

  @spec score_with_breakdown(Fingerprint.t(), Fingerprint.t(), Pass.Solution.t()) :: Match.t()
  def score_with_breakdown(query, candidate, solution) do
    breakdown = compute_breakdown(query, candidate)

    total =
      breakdown
      |> Enum.map(fn {facet, {raw_score, _type, _detail}} -> @weights[facet] * raw_score end)
      |> Enum.sum()
      |> Float.round(4)

    %Match{
      solution: solution,
      fingerprint: candidate,
      score: total,
      breakdown: breakdown,
      confidence: confidence(total)
    }
  end

  @spec confidence(float()) :: :high | :medium | :low
  def confidence(score) when score > 0.75, do: :high
  def confidence(score) when score >= 0.5, do: :medium
  def confidence(_score), do: :low

  defp compute_breakdown(query, candidate) do
    %{
      domain: Facets.domain_score(query, candidate),
      target: Facets.target_score(query, candidate),
      ecosystem: Facets.ecosystem_score(query, candidate),
      versions: Facets.version_score(query, candidate),
      error_class: Facets.error_class_score(query, candidate),
      constraints: Facets.constraint_score(query, candidate),
      goal: Facets.goal_score(query, candidate),
      symptoms: Facets.symptom_score(query, candidate)
    }
  end
end
