defmodule Pass.StoreTest do
  use ExUnit.Case, async: true

  alias Pass.Fingerprint
  alias Pass.Solution
  alias Pass.Store

  setup do
    tmp_dir = System.tmp_dir!()
    db_path = Path.join(tmp_dir, "pass_test_#{:erlang.unique_integer([:positive])}.db")
    store = :"store_#{:erlang.unique_integer([:positive])}"
    {:ok, pid} = Store.start_link(db_path: db_path, name: store)

    on_exit(fn ->
      try do
        if Process.alive?(pid), do: GenServer.stop(pid)
      catch
        :exit, _ -> :ok
      end

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

  defp make_fingerprint(overrides \\ %{}) do
    base = %{
      domain: "deployment",
      target: "fly.io",
      ecosystem: ["elixir", "phoenix"],
      error_class: "build_failure",
      goal: "deploy phoenix app with custom buildpack",
      symptoms: ["exit code 1 during docker build", "mix release fails"]
    }

    Fingerprint.new(Map.merge(base, overrides))
  end

  describe "insert/2" do
    test "inserts a solution and retrieves it by ID", %{store: store} do
      solution = make_solution()
      assert :ok = Store.insert(solution, nil, store)
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

      assert :ok = Store.insert(low_trust, nil, store)
      assert :ok = Store.insert(high_trust, nil, store)

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

      assert :ok = Store.insert(high_trust, nil, store)
      assert :ok = Store.insert(low_trust, nil, store)

      {:ok, results} = Store.query([problem_signature: sig], store)
      assert length(results) == 1
      assert hd(results).trust_score == 0.9
      assert hd(results).id == high_trust.id
    end

    test "inserts with fingerprint data stored correctly", %{store: store} do
      solution = make_solution(%{problem_description: "deploy issue"})
      fingerprint = make_fingerprint()

      assert :ok = Store.insert(solution, fingerprint, store)

      {:ok, results} = Store.search(%{domain: "deployment"}, [], store)
      assert length(results) == 1
      {retrieved, fp_map} = hd(results)
      assert retrieved.id == solution.id
      assert fp_map["domain"] == "deployment"
      assert fp_map["target"] == "fly.io"
      assert fp_map["error_class"] == "build_failure"
      assert fp_map["goal"] == "deploy phoenix app with custom buildpack"
    end

    test "insert without fingerprint still works (backward compat)", %{store: store} do
      solution = make_solution()
      assert :ok = Store.insert(solution, nil, store)
      assert {:ok, retrieved} = Store.get(solution.id, store)
      assert retrieved.id == solution.id
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
      :ok = Store.insert(solution, nil, store)
      assert :ok = Store.delete(solution.id, store)
      assert {:error, :not_found} = Store.get(solution.id, store)
    end
  end

  describe "query/2" do
    test "queries by language", %{store: store} do
      :ok =
        Store.insert(make_solution(%{language: "elixir", problem_description: "a"}), nil, store)

      :ok =
        Store.insert(make_solution(%{language: "python", problem_description: "b"}), nil, store)

      {:ok, results} = Store.query([language: "elixir"], store)
      assert length(results) == 1
      assert hd(results).language == "elixir"
    end

    test "queries by framework", %{store: store} do
      :ok =
        Store.insert(make_solution(%{framework: "phoenix", problem_description: "a"}), nil, store)

      :ok =
        Store.insert(make_solution(%{framework: "rails", problem_description: "b"}), nil, store)

      {:ok, results} = Store.query([framework: "phoenix"], store)
      assert length(results) == 1
      assert hd(results).framework == "phoenix"
    end

    test "queries by min_trust", %{store: store} do
      :ok =
        Store.insert(make_solution(%{trust_score: 0.2, problem_description: "low"}), nil, store)

      :ok =
        Store.insert(make_solution(%{trust_score: 0.8, problem_description: "high"}), nil, store)

      {:ok, results} = Store.query([min_trust: 0.5], store)
      assert length(results) == 1
      assert hd(results).trust_score == 0.8
    end

    test "queries by tags (LIKE match)", %{store: store} do
      :ok =
        Store.insert(
          make_solution(%{tags: ["otp", "genserver"], problem_description: "a"}),
          nil,
          store
        )

      :ok = Store.insert(make_solution(%{tags: ["ecto"], problem_description: "b"}), nil, store)

      {:ok, results} = Store.query([tags: ["genserver"]], store)
      assert length(results) == 1
      assert "otp" in hd(results).tags
    end

    test "returns all solutions with no filters", %{store: store} do
      :ok = Store.insert(make_solution(%{problem_description: "one"}), nil, store)
      :ok = Store.insert(make_solution(%{problem_description: "two"}), nil, store)

      {:ok, results} = Store.query([], store)
      assert length(results) == 2
    end
  end

  describe "search/3" do
    test "filters by domain", %{store: store} do
      sol1 = make_solution(%{problem_description: "deploy issue"})
      fp1 = make_fingerprint(%{domain: "deployment"})

      sol2 = make_solution(%{problem_description: "test issue"})
      fp2 = make_fingerprint(%{domain: "testing", target: "exunit"})

      :ok = Store.insert(sol1, fp1, store)
      :ok = Store.insert(sol2, fp2, store)

      {:ok, results} = Store.search(%{domain: "deployment"}, [], store)
      assert length(results) == 1
      {solution, _fp} = hd(results)
      assert solution.id == sol1.id
    end

    test "filters by target", %{store: store} do
      sol1 = make_solution(%{problem_description: "fly deploy"})
      fp1 = make_fingerprint(%{target: "fly.io"})

      sol2 = make_solution(%{problem_description: "heroku deploy"})
      fp2 = make_fingerprint(%{target: "heroku"})

      :ok = Store.insert(sol1, fp1, store)
      :ok = Store.insert(sol2, fp2, store)

      {:ok, results} = Store.search(%{target: "fly.io"}, [], store)
      assert length(results) == 1
      {solution, _fp} = hd(results)
      assert solution.id == sol1.id
    end

    test "filters by error_class", %{store: store} do
      sol1 = make_solution(%{problem_description: "build fail"})
      fp1 = make_fingerprint(%{error_class: "build_failure"})

      sol2 = make_solution(%{problem_description: "runtime crash"})
      fp2 = make_fingerprint(%{error_class: "runtime_crash"})

      :ok = Store.insert(sol1, fp1, store)
      :ok = Store.insert(sol2, fp2, store)

      {:ok, results} = Store.search(%{error_class: "build_failure"}, [], store)
      assert length(results) == 1
      {solution, _fp} = hd(results)
      assert solution.id == sol1.id
    end

    test "filters by multiple facets", %{store: store} do
      sol1 = make_solution(%{problem_description: "deploy fly build"})

      fp1 =
        make_fingerprint(%{domain: "deployment", target: "fly.io", error_class: "build_failure"})

      sol2 = make_solution(%{problem_description: "deploy heroku build"})

      fp2 =
        make_fingerprint(%{domain: "deployment", target: "heroku", error_class: "build_failure"})

      :ok = Store.insert(sol1, fp1, store)
      :ok = Store.insert(sol2, fp2, store)

      {:ok, results} = Store.search(%{domain: "deployment", target: "fly.io"}, [], store)
      assert length(results) == 1
      {solution, _fp} = hd(results)
      assert solution.id == sol1.id
    end

    test "returns fingerprint map with results", %{store: store} do
      solution = make_solution(%{problem_description: "fp test"})
      fingerprint = make_fingerprint(%{goal: "test goal retrieval"})

      :ok = Store.insert(solution, fingerprint, store)

      {:ok, [{_sol, fp_map}]} = Store.search(%{domain: "deployment"}, [], store)
      assert fp_map["goal"] == "test goal retrieval"
      assert fp_map["domain"] == "deployment"
    end

    test "respects min_trust option", %{store: store} do
      sol_low = make_solution(%{problem_description: "low trust", trust_score: 0.2})
      sol_high = make_solution(%{problem_description: "high trust", trust_score: 0.9})
      fp = make_fingerprint(%{domain: "deployment"})

      :ok = Store.insert(sol_low, fp, store)
      :ok = Store.insert(sol_high, fp, store)

      {:ok, results} = Store.search(%{domain: "deployment"}, [min_trust: 0.5], store)
      assert length(results) == 1
      {solution, _fp} = hd(results)
      assert solution.trust_score == 0.9
    end

    test "returns all when no facets provided", %{store: store} do
      sol1 = make_solution(%{problem_description: "first"})
      sol2 = make_solution(%{problem_description: "second"})
      fp = make_fingerprint()

      :ok = Store.insert(sol1, fp, store)
      :ok = Store.insert(sol2, fp, store)

      {:ok, results} = Store.search(%{}, [], store)
      assert length(results) == 2
    end
  end

  describe "fts_search/3" do
    test "finds solutions by text similarity", %{store: store} do
      sol1 = make_solution(%{problem_description: "deploy phoenix app to fly.io"})
      fp1 = make_fingerprint(%{goal: "deploy phoenix application with custom buildpack"})

      sol2 = make_solution(%{problem_description: "fix ecto migration error"})
      fp2 = make_fingerprint(%{goal: "resolve database migration conflict", domain: "database"})

      :ok = Store.insert(sol1, fp1, store)
      :ok = Store.insert(sol2, fp2, store)

      {:ok, results} = Store.fts_search("deploy phoenix", [], store)
      assert results != []
      assert hd(results).id == sol1.id
    end

    test "respects limit option", %{store: store} do
      for i <- 1..5 do
        sol = make_solution(%{problem_description: "deploy issue #{i}"})
        fp = make_fingerprint(%{goal: "deploy application number #{i}"})
        :ok = Store.insert(sol, fp, store)
      end

      {:ok, results} = Store.fts_search("deploy", [limit: 2], store)
      assert length(results) <= 2
    end

    test "returns empty list when no matches", %{store: store} do
      sol = make_solution(%{problem_description: "unrelated problem"})
      fp = make_fingerprint(%{goal: "fix authentication bug"})
      :ok = Store.insert(sol, fp, store)

      {:ok, results} = Store.fts_search("kubernetes helm chart", [], store)
      assert results == []
    end
  end

  describe "stats/1" do
    test "returns correct stats including fingerprinted count", %{store: store} do
      :ok =
        Store.insert(
          make_solution(%{language: "elixir", trust_score: 0.4, problem_description: "a"}),
          make_fingerprint(%{domain: "deployment"}),
          store
        )

      :ok =
        Store.insert(
          make_solution(%{language: "elixir", trust_score: 0.6, problem_description: "b"}),
          nil,
          store
        )

      :ok =
        Store.insert(
          make_solution(%{language: "python", trust_score: 0.8, problem_description: "c"}),
          make_fingerprint(%{goal: "fix python issue"}),
          store
        )

      {:ok, stats} = Store.stats(store)
      assert stats.total == 3
      assert stats.by_language["elixir"] == 2
      assert stats.by_language["python"] == 1
      assert_in_delta stats.avg_trust, 0.6, 0.01
      assert stats.fingerprinted == 2
    end

    test "returns zero stats for empty store", %{store: store} do
      {:ok, stats} = Store.stats(store)
      assert stats.total == 0
      assert stats.by_language == %{}
      assert stats.avg_trust == 0.0
      assert stats.fingerprinted == 0
    end
  end

  describe "migration versioning" do
    test "fresh database gets both v1 and v2 migrations", %{db_path: _db_path} do
      fresh_path =
        Path.join(System.tmp_dir!(), "pass_fresh_#{:erlang.unique_integer([:positive])}.db")

      fresh_store = :"store_fresh_#{:erlang.unique_integer([:positive])}"

      {:ok, pid} = Store.start_link(db_path: fresh_path, name: fresh_store)

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
        File.rm(fresh_path)
      end)

      # Should be able to insert with fingerprint (v2 columns exist)
      solution = make_solution(%{problem_description: "migration test"})
      fingerprint = make_fingerprint()
      assert :ok = Store.insert(solution, fingerprint, fresh_store)

      # Should be able to search (FTS5 exists)
      {:ok, results} = Store.search(%{domain: "deployment"}, [], fresh_store)
      assert length(results) == 1
    end
  end
end
