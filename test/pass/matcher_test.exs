defmodule Pass.MatcherTest do
  use ExUnit.Case, async: true

  alias Pass.Fingerprint
  alias Pass.Match
  alias Pass.Matcher
  alias Pass.Solution

  defp fp(attrs) do
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

  defp solution(id \\ "sol-1") do
    Solution.new(%{
      id: id,
      problem_description: "test problem #{id}",
      solution_content: "test solution #{id}",
      language: "elixir",
      agent_id: "test-agent"
    })
  end

  describe "match/2" do
    test "returns matches sorted by score descending" do
      query = fp(%{domain: "deployment", ecosystem: ["elixir", "phoenix"]})

      candidates = [
        {solution("sol-1"), fp(%{domain: "authentication", ecosystem: ["python"]})},
        {solution("sol-2"), fp(%{domain: "deployment", ecosystem: ["elixir", "phoenix"]})},
        {solution("sol-3"), fp(%{domain: "infrastructure", ecosystem: ["elixir"]})}
      ]

      results = Matcher.match(query, candidates)

      assert results != []
      scores = Enum.map(results, & &1.score)
      assert scores == Enum.sort(scores, :desc)

      # Best match should be the exact domain + ecosystem match
      best = hd(results)
      assert best.solution.id == "sol-2"
    end

    test "returns empty list when no candidates" do
      query = fp(%{domain: "deployment"})
      assert Matcher.match(query, []) == []
    end

    test "filters out low-scoring matches by default (min_score: 0.3)" do
      query =
        fp(%{
          domain: "deployment",
          target: "fly.io",
          ecosystem: ["elixir"],
          error_class: "build_failure",
          constraints: ["arm64"],
          goal: "deploy phoenix app",
          symptoms: ["exit code 1"]
        })

      candidates = [
        {solution("bad"),
         fp(%{
           domain: "authentication",
           target: "heroku",
           ecosystem: ["python"],
           error_class: "timeout",
           constraints: ["x86"],
           goal: "debug memory leak",
           symptoms: ["slow response"]
         })}
      ]

      results = Matcher.match(query, candidates)
      assert results == []
    end
  end

  describe "match/3 with options" do
    test "respects min_score option" do
      query = fp(%{domain: "deployment", ecosystem: ["elixir"]})

      candidates = [
        {solution("sol-1"), fp(%{domain: "deployment", ecosystem: ["elixir"]})},
        {solution("sol-2"), fp(%{domain: "infrastructure", ecosystem: ["elixir"]})}
      ]

      strict = Matcher.match(query, candidates, min_score: 0.95)
      relaxed = Matcher.match(query, candidates, min_score: 0.0)

      assert length(relaxed) >= length(strict)
    end

    test "respects limit option" do
      query = fp(%{domain: "deployment"})

      candidates =
        for i <- 1..5 do
          {solution("sol-#{i}"), fp(%{domain: "deployment"})}
        end

      results = Matcher.match(query, candidates, limit: 2)
      assert length(results) <= 2
    end
  end

  describe "best_match/2" do
    test "returns the highest scoring match" do
      query = fp(%{domain: "deployment", ecosystem: ["elixir", "phoenix"]})

      candidates = [
        {solution("sol-1"), fp(%{domain: "authentication", ecosystem: ["python"]})},
        {solution("sol-2"), fp(%{domain: "deployment", ecosystem: ["elixir", "phoenix"]})}
      ]

      %Match{} = best = Matcher.best_match(query, candidates)
      assert best.solution.id == "sol-2"
    end

    test "returns nil when no matches above threshold" do
      query =
        fp(%{
          domain: "deployment",
          target: "fly.io",
          ecosystem: ["elixir"],
          error_class: "build_failure",
          constraints: ["arm64"],
          goal: "deploy phoenix app",
          symptoms: ["exit code 1"]
        })

      candidates = [
        {solution("bad"),
         fp(%{
           domain: "authentication",
           target: "heroku",
           ecosystem: ["python"],
           error_class: "timeout",
           constraints: ["x86"],
           goal: "debug memory leak",
           symptoms: ["slow response"]
         })}
      ]

      assert Matcher.best_match(query, candidates) == nil
    end

    test "returns nil for empty candidates" do
      query = fp(%{domain: "deployment"})
      assert Matcher.best_match(query, []) == nil
    end
  end

  describe "end-to-end confidence" do
    test "perfect match has high confidence" do
      query =
        fp(%{
          domain: "deployment",
          target: "fly.io",
          ecosystem: ["elixir", "phoenix"],
          error_class: "build_failure",
          goal: "deploy phoenix app",
          symptoms: ["exit code 1"]
        })

      candidate =
        fp(%{
          domain: "deployment",
          target: "fly.io",
          ecosystem: ["elixir", "phoenix"],
          error_class: "build_failure",
          goal: "deploy phoenix app",
          symptoms: ["exit code 1"]
        })

      [match] = Matcher.match(query, [{solution(), candidate}], min_score: 0.0)
      assert match.confidence == :high
      assert match.score == 1.0
    end
  end
end
