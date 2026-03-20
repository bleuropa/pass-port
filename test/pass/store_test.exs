defmodule Pass.StoreTest do
  use ExUnit.Case, async: true

  alias Pass.Solution
  alias Pass.Store

  setup do
    tmp_dir = System.tmp_dir!()
    db_path = Path.join(tmp_dir, "pass_test_#{:erlang.unique_integer([:positive])}.db")
    store = :"store_#{:erlang.unique_integer([:positive])}"
    {:ok, pid} = Store.start_link(db_path: db_path, name: store)

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
      File.rm(db_path)
    end)

    %{store: store, db_path: db_path}
  end

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

  describe "insert/2" do
    test "inserts a solution and retrieves it by ID", %{store: store} do
      solution = make_solution()
      assert :ok = Store.insert(solution, store)
      assert {:ok, retrieved} = Store.get(solution.id, store)
      assert retrieved.id == solution.id
      assert retrieved.problem_description == solution.problem_description
    end

    test "deduplicates by problem_signature — keeps higher trust", %{store: store} do
      sig = Solution.compute_signature(%{description: "same problem", language: "elixir"})

      low_trust =
        make_solution(%{
          problem_signature: sig,
          problem_description: "same problem",
          trust_score: 0.3
        })

      high_trust =
        make_solution(%{
          problem_signature: sig,
          problem_description: "same problem",
          trust_score: 0.8
        })

      assert :ok = Store.insert(low_trust, store)
      assert :ok = Store.insert(high_trust, store)

      {:ok, results} = Store.query([problem_signature: sig], store)
      assert length(results) == 1
      assert hd(results).trust_score == 0.8
    end

    test "dedup does not replace if existing trust is higher", %{store: store} do
      sig = Solution.compute_signature(%{description: "keep original", language: "elixir"})

      high_trust =
        make_solution(%{
          problem_signature: sig,
          problem_description: "keep original",
          trust_score: 0.9
        })

      low_trust =
        make_solution(%{
          problem_signature: sig,
          problem_description: "keep original",
          trust_score: 0.2
        })

      assert :ok = Store.insert(high_trust, store)
      assert :ok = Store.insert(low_trust, store)

      {:ok, results} = Store.query([problem_signature: sig], store)
      assert length(results) == 1
      assert hd(results).trust_score == 0.9
      assert hd(results).id == high_trust.id
    end
  end

  describe "get/2" do
    test "returns {:error, :not_found} for missing ID", %{store: store} do
      assert {:error, :not_found} = Store.get("nonexistent", store)
    end
  end

  describe "delete/2" do
    test "removes a solution by ID", %{store: store} do
      solution = make_solution()
      :ok = Store.insert(solution, store)
      assert :ok = Store.delete(solution.id, store)
      assert {:error, :not_found} = Store.get(solution.id, store)
    end
  end

  describe "query/2" do
    test "queries by language", %{store: store} do
      :ok = Store.insert(make_solution(%{language: "elixir", problem_description: "a"}), store)
      :ok = Store.insert(make_solution(%{language: "python", problem_description: "b"}), store)

      {:ok, results} = Store.query([language: "elixir"], store)
      assert length(results) == 1
      assert hd(results).language == "elixir"
    end

    test "queries by framework", %{store: store} do
      :ok = Store.insert(make_solution(%{framework: "phoenix", problem_description: "a"}), store)
      :ok = Store.insert(make_solution(%{framework: "rails", problem_description: "b"}), store)

      {:ok, results} = Store.query([framework: "phoenix"], store)
      assert length(results) == 1
      assert hd(results).framework == "phoenix"
    end

    test "queries by min_trust", %{store: store} do
      :ok = Store.insert(make_solution(%{trust_score: 0.2, problem_description: "low"}), store)
      :ok = Store.insert(make_solution(%{trust_score: 0.8, problem_description: "high"}), store)

      {:ok, results} = Store.query([min_trust: 0.5], store)
      assert length(results) == 1
      assert hd(results).trust_score == 0.8
    end

    test "queries by tags (LIKE match)", %{store: store} do
      :ok =
        Store.insert(
          make_solution(%{tags: ["otp", "genserver"], problem_description: "a"}),
          store
        )

      :ok = Store.insert(make_solution(%{tags: ["ecto"], problem_description: "b"}), store)

      {:ok, results} = Store.query([tags: ["genserver"]], store)
      assert length(results) == 1
      assert "otp" in hd(results).tags
    end

    test "returns all solutions with no filters", %{store: store} do
      :ok = Store.insert(make_solution(%{problem_description: "one"}), store)
      :ok = Store.insert(make_solution(%{problem_description: "two"}), store)

      {:ok, results} = Store.query([], store)
      assert length(results) == 2
    end
  end

  describe "stats/1" do
    test "returns correct stats", %{store: store} do
      :ok =
        Store.insert(
          make_solution(%{language: "elixir", trust_score: 0.4, problem_description: "a"}),
          store
        )

      :ok =
        Store.insert(
          make_solution(%{language: "elixir", trust_score: 0.6, problem_description: "b"}),
          store
        )

      :ok =
        Store.insert(
          make_solution(%{language: "python", trust_score: 0.8, problem_description: "c"}),
          store
        )

      {:ok, stats} = Store.stats(store)
      assert stats.total == 3
      assert stats.by_language["elixir"] == 2
      assert stats.by_language["python"] == 1
      assert_in_delta stats.avg_trust, 0.6, 0.01
    end

    test "returns zero stats for empty store", %{store: store} do
      {:ok, stats} = Store.stats(store)
      assert stats.total == 0
      assert stats.by_language == %{}
      assert stats.avg_trust == 0.0
    end
  end
end
