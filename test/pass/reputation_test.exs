defmodule Pass.ReputationTest do
  use ExUnit.Case, async: true

  alias Pass.Reputation
  alias Pass.Solution
  alias Pass.Store
  alias Pass.Trust

  setup do
    tmp_dir = System.tmp_dir!()
    db_path = Path.join(tmp_dir, "pass_rep_test_#{:erlang.unique_integer([:positive])}.db")
    store = :"store_rep_#{:erlang.unique_integer([:positive])}"
    {:ok, pid} = Store.start_link(db_path: db_path, name: store)

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
      File.rm(db_path)
    end)

    %{store: store}
  end

  describe "score/2" do
    test "new agent starts at 0.5 reputation", %{store: store} do
      assert Reputation.score("unknown-agent", store) == 0.5
    end

    test "unknown agent returns 0.5", %{store: store} do
      assert Reputation.score("never-seen-before", store) == 0.5
    end

    test "contributing increases consistency_score", %{store: store} do
      Reputation.ensure_agent("agent-a", store)

      for _ <- 1..10 do
        Reputation.record_contribution("agent-a", store)
      end

      score = Reputation.score("agent-a", store)
      # consistency_score = min(10/10, 1.0) = 1.0
      # contribution_score = 0/max(10,1) = 0.0
      # reputation = 0.6 * 0.0 + 0.4 * 1.0 = 0.4
      assert_in_delta score, 0.4, 0.01
    end

    test "successful consumptions increase contribution_score", %{store: store} do
      Reputation.ensure_agent("contributor", store)
      Reputation.ensure_agent("consumer", store)

      for _ <- 1..5 do
        Reputation.record_contribution("contributor", store)
      end

      for _ <- 1..5 do
        Reputation.record_consumption("consumer", "contributor", store)
      end

      score = Reputation.score("contributor", store)
      # contributed = 5, successful_consumptions = 5
      # contribution_score = 5/max(5,1) = 1.0
      # consistency_score = min(5/10, 1.0) = 0.5
      # reputation = 0.6 * 1.0 + 0.4 * 0.5 = 0.8
      assert_in_delta score, 0.8, 0.01
    end

    test "score calculation at various ratios", %{store: store} do
      Reputation.ensure_agent("agent-b", store)

      # Contribute 20 solutions
      for _ <- 1..20 do
        Reputation.record_contribution("agent-b", store)
      end

      # 10 successful consumptions by others
      Reputation.ensure_agent("consumer-x", store)

      for _ <- 1..10 do
        Reputation.record_consumption("consumer-x", "agent-b", store)
      end

      score = Reputation.score("agent-b", store)
      # contributed = 20, successful_consumptions = 10
      # contribution_score = 10/20 = 0.5
      # consistency_score = min(20/10, 1.0) = 1.0
      # reputation = 0.6 * 0.5 + 0.4 * 1.0 = 0.7
      assert_in_delta score, 0.7, 0.01
    end

    test "ensure_agent creates agent with defaults", %{store: store} do
      assert :ok = Reputation.ensure_agent("new-agent", store)
      assert {:ok, agent} = Store.get_agent("new-agent", store)
      assert agent["agent_id"] == "new-agent"
      assert agent["reputation"] == 0.5
      assert agent["solutions_contributed"] == 0
    end

    test "ensure_agent is idempotent", %{store: store} do
      assert :ok = Reputation.ensure_agent("dup-agent", store)
      assert :ok = Reputation.ensure_agent("dup-agent", store)
      assert {:ok, _} = Store.get_agent("dup-agent", store)
    end
  end

  describe "trust score with reputation factor" do
    test "trust score incorporates reputation weight", %{store: store} do
      Reputation.ensure_agent("trusted-agent", store)

      for _ <- 1..10 do
        Reputation.record_contribution("trusted-agent", store)
      end

      Reputation.ensure_agent("consumer-y", store)

      for _ <- 1..10 do
        Reputation.record_consumption("consumer-y", "trusted-agent", store)
      end

      reputation = Reputation.score("trusted-agent", store)
      # contribution_score = 10/10 = 1.0, consistency_score = 10/10 = 1.0
      # reputation = 0.6 * 1.0 + 0.4 * 1.0 = 1.0
      assert_in_delta reputation, 1.0, 0.01

      solution =
        Solution.new(%{
          problem_description: "test problem",
          solution_content: "test solution",
          language: "elixir",
          framework: "phoenix",
          agent_id: "trusted-agent",
          verification: %{compiled: true, tests_passed: true, deploy_succeeded: true},
          tags: ["otp"]
        })

      trust_without = Trust.score(solution)
      trust_with = Trust.score(solution, reputation)

      # Both should be high, but with different weight distributions
      assert trust_without > 0.9
      assert trust_with > 0.9

      # Verify the weights changed: score/2 uses 0.35/0.25/0.25/0.15 vs 0.40/0.30/0.30
      # With all components at 1.0, both should equal 1.0
      assert_in_delta trust_with, 1.0, 0.01
    end

    test "low reputation reduces trust score", %{store: store} do
      reputation = Reputation.score("no-contributions", store)
      assert reputation == 0.5

      solution =
        Solution.new(%{
          problem_description: "test problem",
          solution_content: "fix",
          language: "elixir",
          framework: "phoenix",
          agent_id: "no-contributions",
          verification: %{compiled: true, tests_passed: true, deploy_succeeded: true},
          tags: ["test"]
        })

      trust_without = Trust.score(solution)
      trust_with = Trust.score(solution, reputation)

      # score/1: 0.40*1.0 + 0.30*1.0 + 0.30*1.0 = 1.0
      # score/2: 0.35*1.0 + 0.25*1.0 + 0.25*1.0 + 0.15*0.5 = 0.925
      assert_in_delta trust_without, 1.0, 0.01
      assert_in_delta trust_with, 0.925, 0.01
    end
  end
end
