defmodule Pass.Matcher.FacetsTest do
  use ExUnit.Case, async: true

  alias Pass.Fingerprint
  alias Pass.Matcher.Facets

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

  describe "domain_score/2" do
    test "exact match returns 1.0" do
      {score, :exact, _} =
        Facets.domain_score(fp(%{domain: "deployment"}), fp(%{domain: "deployment"}))

      assert score == 1.0
    end

    test "parent/child returns 0.7" do
      {score, :parent_child, _} =
        Facets.domain_score(fp(%{domain: "deployment"}), fp(%{domain: "infrastructure"}))

      assert score == 0.7
    end

    test "siblings returns 0.5" do
      {score, :sibling, _} =
        Facets.domain_score(fp(%{domain: "deployment"}), fp(%{domain: "networking"}))

      assert score == 0.5
    end

    test "unrelated returns 0.0" do
      {score, :mismatch, _} =
        Facets.domain_score(fp(%{domain: "deployment"}), fp(%{domain: "authentication"}))

      assert score == 0.0
    end

    test "both nil returns 1.0" do
      {score, :exact, _} = Facets.domain_score(fp(), fp())
      assert score == 1.0
    end

    test "one nil returns 0.5" do
      {score, :sibling, _} = Facets.domain_score(fp(%{domain: "deployment"}), fp())
      assert score == 0.5
    end
  end

  describe "target_score/2" do
    test "exact match returns 1.0" do
      {1.0, :exact, "fly.io"} =
        Facets.target_score(fp(%{target: "fly.io"}), fp(%{target: "fly.io"}))
    end

    test "mismatch returns 0.0" do
      {score, :mismatch, _} =
        Facets.target_score(fp(%{target: "fly.io"}), fp(%{target: "heroku"}))

      assert score == 0.0
    end

    test "either nil returns 1.0 (no constraint)" do
      {1.0, :no_constraint, nil} = Facets.target_score(fp(%{target: "fly.io"}), fp())
      {1.0, :no_constraint, nil} = Facets.target_score(fp(), fp(%{target: "fly.io"}))
      {1.0, :no_constraint, nil} = Facets.target_score(fp(), fp())
    end
  end

  describe "ecosystem_score/2" do
    test "identical sets return 1.0" do
      q = fp(%{ecosystem: ["elixir", "phoenix"]})
      c = fp(%{ecosystem: ["elixir", "phoenix"]})
      {score, _, _} = Facets.ecosystem_score(q, c)
      assert score == 1.0
    end

    test "partial overlap returns Jaccard" do
      q = fp(%{ecosystem: ["elixir", "phoenix"]})
      c = fp(%{ecosystem: ["elixir", "phoenix", "liveview"]})
      {score, _, _} = Facets.ecosystem_score(q, c)
      assert_in_delta score, 0.667, 0.01
    end

    test "no overlap returns 0.0" do
      q = fp(%{ecosystem: ["python"]})
      c = fp(%{ecosystem: ["elixir"]})
      {score, _, _} = Facets.ecosystem_score(q, c)
      assert score == 0.0
    end

    test "both empty returns 1.0" do
      {1.0, :no_constraint, []} = Facets.ecosystem_score(fp(), fp())
    end
  end

  describe "version_score/2" do
    test "same major version returns 1.0" do
      q = fp(%{versions: %{"elixir" => "~> 1.18"}})
      c = fp(%{versions: %{"elixir" => "~> 1.17"}})
      {score, :version_check, _} = Facets.version_score(q, c)
      assert score == 1.0
    end

    test "adjacent major versions returns 0.5" do
      q = fp(%{versions: %{"elixir" => "~> 2.0"}})
      c = fp(%{versions: %{"elixir" => "~> 1.18"}})
      {score, :version_check, _} = Facets.version_score(q, c)
      assert score == 0.5
    end

    test "distant major versions returns 0.2" do
      q = fp(%{versions: %{"elixir" => "~> 3.0"}})
      c = fp(%{versions: %{"elixir" => "~> 1.18"}})
      {score, :version_check, _} = Facets.version_score(q, c)
      assert score == 0.2
    end

    test "no shared keys returns 1.0" do
      q = fp(%{versions: %{"elixir" => "~> 1.18"}})
      c = fp(%{versions: %{"otp" => "~> 27"}})
      {1.0, :no_constraint, %{}} = Facets.version_score(q, c)
    end

    test "both empty returns 1.0" do
      {1.0, :no_constraint, %{}} = Facets.version_score(fp(), fp())
    end

    test "averages across multiple shared components" do
      q = fp(%{versions: %{"elixir" => "~> 1.18", "otp" => "~> 27"}})
      c = fp(%{versions: %{"elixir" => "~> 1.17", "otp" => "~> 26"}})
      {score, :version_check, _} = Facets.version_score(q, c)
      # elixir: major 1 vs 1 -> 1.0; otp: major 27 vs 26 -> adjacent -> 0.5
      assert_in_delta score, 0.75, 0.01
    end
  end

  describe "error_class_score/2" do
    test "exact match returns 1.0" do
      {1.0, :exact, _} =
        Facets.error_class_score(
          fp(%{error_class: "build_failure"}),
          fp(%{error_class: "build_failure"})
        )
    end

    test "sibling returns 0.5" do
      {0.5, :sibling, _} =
        Facets.error_class_score(
          fp(%{error_class: "build_failure"}),
          fp(%{error_class: "deploy_failure"})
        )
    end

    test "unrelated returns 0.0" do
      {score, :mismatch, _} =
        Facets.error_class_score(
          fp(%{error_class: "build_failure"}),
          fp(%{error_class: "timeout"})
        )

      assert score == 0.0
    end

    test "both nil returns 1.0" do
      {1.0, :exact, _} = Facets.error_class_score(fp(), fp())
    end
  end

  describe "constraint_score/2" do
    test "no query constraints returns 1.0" do
      {1.0, :no_constraint, []} =
        Facets.constraint_score(fp(), fp(%{constraints: ["arm64"]}))
    end

    test "satisfied constraints return 1.0" do
      {1.0, :satisfied, _} =
        Facets.constraint_score(
          fp(%{constraints: ["arm64"]}),
          fp(%{constraints: ["arm64", "alpine"]})
        )
    end

    test "unsatisfied constraints return 0.0" do
      {score, :unsatisfied, _} =
        Facets.constraint_score(
          fp(%{constraints: ["arm64", "alpine"]}),
          fp(%{constraints: ["arm64"]})
        )

      assert score == 0.0
    end
  end

  describe "goal_score/2" do
    test "identical goals return 1.0" do
      q = fp(%{goal: "deploy phoenix app"})
      c = fp(%{goal: "deploy phoenix app"})
      {score, :goal_overlap, _} = Facets.goal_score(q, c)
      assert score == 1.0
    end

    test "partial overlap returns positive score" do
      q = fp(%{goal: "deploy phoenix app"})
      c = fp(%{goal: "deploy elixir app to cloud"})
      {score, :goal_overlap, _} = Facets.goal_score(q, c)
      assert score > 0.0
      assert score < 1.0
    end

    test "no overlap returns 0.0" do
      q = fp(%{goal: "deploy phoenix"})
      c = fp(%{goal: "debug memory leak"})
      {score, :goal_overlap, _} = Facets.goal_score(q, c)
      assert score == 0.0
    end

    test "both nil returns 1.0" do
      {1.0, :no_constraint, []} = Facets.goal_score(fp(), fp())
    end
  end

  describe "symptom_score/2" do
    test "matching symptoms return positive score" do
      q = fp(%{symptoms: ["exit code 1", "docker build fails"]})
      c = fp(%{symptoms: ["exit code 1 during build", "docker error"]})
      {score, :symptom_overlap, _} = Facets.symptom_score(q, c)
      assert score > 0.0
    end

    test "no symptoms returns 1.0" do
      {1.0, :no_constraint, []} = Facets.symptom_score(fp(), fp())
    end

    test "no overlap returns 0.0" do
      q = fp(%{symptoms: ["timeout error"]})
      c = fp(%{symptoms: ["syntax invalid"]})
      {score, :symptom_overlap, _} = Facets.symptom_score(q, c)
      assert score == 0.0
    end
  end
end
