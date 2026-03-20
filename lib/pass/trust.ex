defmodule Pass.Trust do
  @moduledoc """
  Trust scoring engine for Pass solutions.

  Phase 1 uses a weighted formula based on automated verification,
  metadata completeness, and freshness. Network-based signals will
  be added in later phases.
  """

  alias Pass.Solution

  @verification_weight 0.40
  @completeness_weight 0.30
  @freshness_weight 0.30

  @doc """
  Computes a trust score (0.0-1.0) for a solution.
  """
  @spec score(Solution.t()) :: float()
  def score(%Solution{} = solution) do
    v = verification_score(solution)
    c = completeness_score(solution)
    f = freshness_score(solution)

    (@verification_weight * v + @completeness_weight * c + @freshness_weight * f)
    |> clamp()
  end

  @doc """
  Scores the verification map.

  - compiled: true = 0.4
  - tests_passed: true = 0.4
  - deploy_succeeded: true = 0.2
  """
  @spec verification_score(Solution.t()) :: float()
  def verification_score(%Solution{verification: v}) when is_map(v) do
    compiled = if v[:compiled] || v["compiled"], do: 0.4, else: 0.0
    tests = if v[:tests_passed] || v["tests_passed"], do: 0.4, else: 0.0
    deploy = if v[:deploy_succeeded] || v["deploy_succeeded"], do: 0.2, else: 0.0
    compiled + tests + deploy
  end

  def verification_score(_), do: 0.0

  @doc """
  Scores metadata completeness.

  - Has language: 0.3
  - Has framework: 0.2
  - Has tags (non-empty): 0.2
  - Has problem_description: 0.3
  """
  @spec completeness_score(Solution.t()) :: float()
  def completeness_score(%Solution{} = solution) do
    lang = if present?(solution.language), do: 0.3, else: 0.0
    framework = if present?(solution.framework), do: 0.2, else: 0.0
    tags = if is_list(solution.tags) and solution.tags != [], do: 0.2, else: 0.0
    desc = if present?(solution.problem_description), do: 0.3, else: 0.0
    lang + framework + tags + desc
  end

  @doc """
  Scores freshness based on time since insertion.

  - Less than 7 days: 1.0
  - Less than 30 days: 0.8
  - Less than 90 days: 0.5
  - Older: 0.3
  """
  @spec freshness_score(Solution.t()) :: float()
  def freshness_score(%Solution{inserted_at: %DateTime{} = inserted_at}) do
    days = DateTime.diff(DateTime.utc_now(), inserted_at, :day)

    cond do
      days < 7 -> 1.0
      days < 30 -> 0.8
      days < 90 -> 0.5
      true -> 0.3
    end
  end

  def freshness_score(_), do: 0.3

  defp present?(val) when is_binary(val), do: String.trim(val) != ""
  defp present?(_), do: false

  defp clamp(val) when val < 0.0, do: 0.0
  defp clamp(val) when val > 1.0, do: 1.0
  defp clamp(val), do: Float.round(val, 4)
end
