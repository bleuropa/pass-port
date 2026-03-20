defmodule Pass.Actions.QuerySolutionsTest do
  use ExUnit.Case, async: true

  alias Pass.Actions.QuerySolutions
  alias Pass.Fingerprint
  alias Pass.Solution
  alias Pass.Store

  setup do
    tmp_dir = System.tmp_dir!()
    suffix = :erlang.unique_integer([:positive])
    db_path = Path.join(tmp_dir, "pass_test_query_#{suffix}.db")
    store = :"store_query_#{suffix}"
    {:ok, pid} = Store.start_link(db_path: db_path, name: store)

    # Seed legacy solutions (no fingerprint)
    :ok =
      Store.insert(
        Solution.new(%{
          problem_description: "Fix crash",
          solution_content: "# fix",
          language: "elixir",
          framework: "phoenix",
          agent_id: "agent-001",
          trust_score: 0.8
        }),
        store
      )

    :ok =
      Store.insert(
        Solution.new(%{
          problem_description: "Add feature",
          solution_content: "# feature",
          language: "python",
          agent_id: "agent-002",
          trust_score: 0.3
        }),
        store
      )

    # Seed fingerprinted solutions
    deploy_fp =
      Fingerprint.new(%{
        domain: "deployment",
        target: "fly.io",
        ecosystem: ["elixir", "phoenix"],
        error_class: "build_failure",
        goal: "deploy phoenix app to fly.io",
        symptoms: ["exit code 1 during docker build"]
      })

    :ok =
      Store.insert(
        Solution.new(%{
          problem_description: "Fix fly.io deploy",
          solution_content: "# fix dockerfile",
          language: "elixir",
          framework: "phoenix",
          agent_id: "agent-003",
          trust_score: 0.9
        }),
        deploy_fp,
        store
      )

    db_fp =
      Fingerprint.new(%{
        domain: "database",
        target: "postgres",
        ecosystem: ["elixir", "ecto"],
        error_class: "timeout",
        goal: "fix ecto query timeout",
        symptoms: ["DBConnection.ConnectionError"]
      })

    :ok =
      Store.insert(
        Solution.new(%{
          problem_description: "Ecto timeout fix",
          solution_content: "# increase pool",
          language: "elixir",
          agent_id: "agent-004",
          trust_score: 0.7
        }),
        db_fp,
        store
      )

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
      File.rm(db_path)
    end)

    %{store: store}
  end

  describe "legacy query" do
    test "queries by language", %{store: store} do
      assert {:ok, result} = QuerySolutions.run(%{language: "elixir", store: store}, %{})
      assert result.count >= 1
      assert Enum.all?(result.solutions, &(&1.language == "elixir"))
    end

    test "queries by min_trust", %{store: store} do
      assert {:ok, result} = QuerySolutions.run(%{min_trust: 0.5, store: store}, %{})
      assert result.count >= 1
      assert Enum.all?(result.solutions, &(&1.trust_score >= 0.5))
    end

    test "returns all when no filters", %{store: store} do
      assert {:ok, result} = QuerySolutions.run(%{store: store}, %{})
      assert result.count == 4
    end
  end

  describe "fingerprint query" do
    test "query with domain finds matching solutions", %{store: store} do
      params = %{
        domain: "deployment",
        target: "fly.io",
        ecosystem: ["elixir", "phoenix"],
        store: store
      }

      assert {:ok, result} = QuerySolutions.run(params, %{})
      assert result.count >= 1
      assert Enum.any?(result.matches, fn m -> m.solution.problem_description =~ "fly.io" end)
    end

    test "query with partial fingerprint (just domain + ecosystem) finds matches", %{
      store: store
    } do
      params = %{
        domain: "database",
        ecosystem: ["elixir"],
        store: store
      }

      assert {:ok, result} = QuerySolutions.run(params, %{})
      assert result.count >= 1
    end

    test "publish old-style, query new-style finds match via legacy fingerprint", %{
      store: store
    } do
      # The legacy solution "Fix crash" was auto-fingerprinted by Solution.new
      # Query with fingerprint facets should still find it via decomposed fields
      params = %{
        domain: "deployment",
        target: "fly.io",
        error_class: "build_failure",
        store: store
      }

      assert {:ok, result} = QuerySolutions.run(params, %{})
      assert result.count >= 1
      assert Enum.all?(result.matches, fn m -> m.score > 0.0 end)
    end

    test "matches include score breakdown", %{store: store} do
      params = %{
        domain: "deployment",
        ecosystem: ["elixir"],
        store: store
      }

      assert {:ok, result} = QuerySolutions.run(params, %{})
      assert result.count >= 1
      match = hd(result.matches)
      assert match.score > 0.0
      assert match.confidence in [:high, :medium, :low]
      assert is_map(match.breakdown)
    end
  end
end
