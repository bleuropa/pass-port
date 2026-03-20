defmodule Pass.TrustTest do
  use ExUnit.Case, async: true

  alias Pass.Solution
  alias Pass.Trust

  defp make_solution(overrides \\ %{}) do
    base = %{
      problem_description: "Fix GenServer timeout",
      solution_content: "defmodule Fix do\nend",
      language: "elixir",
      framework: "phoenix",
      agent_id: "agent-001"
    }

    Solution.new(Map.merge(base, overrides))
  end

  describe "verification_score/1" do
    test "returns 0.0 when nothing is verified" do
      solution =
        make_solution(%{
          verification: %{compiled: false, tests_passed: false, deploy_succeeded: false}
        })

      assert Trust.verification_score(solution) == 0.0
    end

    test "returns 0.4 for compiled only" do
      solution =
        make_solution(%{
          verification: %{compiled: true, tests_passed: false, deploy_succeeded: false}
        })

      assert Trust.verification_score(solution) == 0.4
    end

    test "returns 0.8 for compiled and tests_passed" do
      solution =
        make_solution(%{
          verification: %{compiled: true, tests_passed: true, deploy_succeeded: false}
        })

      assert Trust.verification_score(solution) == 0.8
    end

    test "returns 1.0 for fully verified" do
      solution =
        make_solution(%{
          verification: %{compiled: true, tests_passed: true, deploy_succeeded: true}
        })

      assert Trust.verification_score(solution) == 1.0
    end
  end

  describe "completeness_score/1" do
    test "returns 1.0 for fully complete metadata" do
      solution = make_solution(%{tags: ["otp"]})
      assert Trust.completeness_score(solution) == 1.0
    end

    test "returns 0.8 without tags" do
      solution = make_solution(%{tags: []})
      assert Trust.completeness_score(solution) == 0.8
    end

    test "returns 0.3 with only language" do
      solution = make_solution(%{framework: nil, tags: [], problem_description: ""})
      # language=0.3
      assert Trust.completeness_score(solution) == 0.3
    end

    test "returns 0.0 with no metadata" do
      solution = make_solution(%{language: "", framework: nil, tags: [], problem_description: ""})
      assert Trust.completeness_score(solution) == 0.0
    end
  end

  describe "freshness_score/1" do
    test "returns 1.0 for solution inserted just now" do
      solution = make_solution()
      assert Trust.freshness_score(solution) == 1.0
    end

    test "returns 0.8 for solution inserted 15 days ago" do
      solution = make_solution(%{inserted_at: DateTime.add(DateTime.utc_now(), -15, :day)})
      assert Trust.freshness_score(solution) == 0.8
    end

    test "returns 0.5 for solution inserted 60 days ago" do
      solution = make_solution(%{inserted_at: DateTime.add(DateTime.utc_now(), -60, :day)})
      assert Trust.freshness_score(solution) == 0.5
    end

    test "returns 0.3 for solution inserted 120 days ago" do
      solution = make_solution(%{inserted_at: DateTime.add(DateTime.utc_now(), -120, :day)})
      assert Trust.freshness_score(solution) == 0.3
    end
  end

  describe "score/1" do
    test "returns high score for fully verified, complete, fresh solution" do
      solution =
        make_solution(%{
          verification: %{compiled: true, tests_passed: true, deploy_succeeded: true},
          tags: ["otp"]
        })

      score = Trust.score(solution)
      # 0.40 * 1.0 + 0.30 * 1.0 + 0.30 * 1.0 = 1.0
      assert_in_delta score, 1.0, 0.01
    end

    test "returns low score for unverified, incomplete, old solution" do
      solution =
        make_solution(%{
          verification: %{compiled: false, tests_passed: false, deploy_succeeded: false},
          language: "",
          framework: nil,
          tags: [],
          problem_description: "",
          inserted_at: DateTime.add(DateTime.utc_now(), -120, :day)
        })

      score = Trust.score(solution)
      # 0.40 * 0.0 + 0.30 * 0.0 + 0.30 * 0.3 = 0.09
      assert_in_delta score, 0.09, 0.01
    end

    test "score is between 0.0 and 1.0" do
      solution = make_solution()
      score = Trust.score(solution)
      assert score >= 0.0
      assert score <= 1.0
    end
  end
end
