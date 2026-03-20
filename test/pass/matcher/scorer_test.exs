defmodule Pass.Matcher.ScorerTest do
  use ExUnit.Case, async: true

  alias Pass.Fingerprint
  alias Pass.Match
  alias Pass.Matcher.Scorer
  alias Pass.Solution

  defp fp(attrs \\ %{}) do
    defaults = %{
      domain: nil,
      target: nil,
      ecosystem: [],
      versions: %{},
      error_class: nil,
      constraints: [],
      goal: nil,
      symptoms: [],
      terms: [],
      signature: "test"
    }

    struct!(Fingerprint, Map.merge(defaults, attrs))
  end

  defp test_solution do
    Solution.new(%{
      problem_description: "test problem",
      solution_content: "test solution",
      language: "elixir",
      agent_id: "test-agent"
    })
  end

  describe "score/2" do
    test "identical fingerprints score 1.0" do
      q = fp(%{domain: "deployment", target: "fly.io", ecosystem: ["elixir"]})
      assert Scorer.score(q, q) == 1.0
    end

    test "completely different fingerprints score near 0.0" do
      q =
        fp(%{
          domain: "deployment",
          target: "fly.io",
          ecosystem: ["elixir"],
          error_class: "build_failure",
          constraints: ["arm64"],
          goal: "deploy phoenix app",
          symptoms: ["exit code 1"]
        })

      c =
        fp(%{
          domain: "authentication",
          target: "heroku",
          ecosystem: ["python"],
          error_class: "timeout",
          constraints: ["x86"],
          goal: "debug memory leak",
          symptoms: ["slow response"]
        })

      score = Scorer.score(q, c)
      assert score <= 0.15
    end

    test "partial match produces intermediate score" do
      q = fp(%{domain: "deployment", ecosystem: ["elixir", "phoenix"]})
      c = fp(%{domain: "infrastructure", ecosystem: ["elixir", "phoenix", "liveview"]})
      score = Scorer.score(q, c)
      assert score > 0.5
      assert score < 1.0
    end
  end

  describe "score_with_breakdown/3" do
    test "returns a Match struct with all fields" do
      q = fp(%{domain: "deployment"})
      c = fp(%{domain: "deployment"})
      solution = test_solution()

      %Match{} = match = Scorer.score_with_breakdown(q, c, solution)
      assert match.solution == solution
      assert match.fingerprint == c
      assert is_float(match.score)
      assert is_map(match.breakdown)
      assert match.confidence in [:high, :medium, :low]
    end

    test "breakdown contains all 8 facets" do
      q = fp()
      c = fp()
      match = Scorer.score_with_breakdown(q, c, test_solution())

      expected_facets = [
        :domain,
        :target,
        :ecosystem,
        :versions,
        :error_class,
        :constraints,
        :goal,
        :symptoms
      ]

      for facet <- expected_facets do
        assert Map.has_key?(match.breakdown, facet), "missing facet: #{facet}"
        {score, _type, _detail} = match.breakdown[facet]
        assert is_number(score)
      end
    end
  end

  describe "confidence/1" do
    test "high for scores above 0.75" do
      assert Scorer.confidence(0.76) == :high
      assert Scorer.confidence(0.9) == :high
      assert Scorer.confidence(1.0) == :high
    end

    test "medium for scores between 0.5 and 0.75" do
      assert Scorer.confidence(0.5) == :medium
      assert Scorer.confidence(0.6) == :medium
      assert Scorer.confidence(0.75) == :medium
    end

    test "low for scores below 0.5" do
      assert Scorer.confidence(0.49) == :low
      assert Scorer.confidence(0.0) == :low
      assert Scorer.confidence(0.3) == :low
    end
  end
end
