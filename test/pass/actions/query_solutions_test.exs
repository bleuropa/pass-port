defmodule Pass.Actions.QuerySolutionsTest do
  use ExUnit.Case, async: true

  alias Pass.Actions.QuerySolutions
  alias Pass.Solution
  alias Pass.Store

  setup do
    tmp_dir = System.tmp_dir!()
    suffix = :erlang.unique_integer([:positive])
    db_path = Path.join(tmp_dir, "pass_test_query_#{suffix}.db")
    store = :"store_query_#{suffix}"
    {:ok, pid} = Store.start_link(db_path: db_path, name: store)

    # Seed some solutions
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

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
      File.rm(db_path)
    end)

    %{store: store}
  end

  test "queries by language", %{store: store} do
    assert {:ok, result} = QuerySolutions.run(%{language: "elixir", store: store}, %{})
    assert result.count == 1
    assert hd(result.solutions).language == "elixir"
  end

  test "queries by min_trust", %{store: store} do
    assert {:ok, result} = QuerySolutions.run(%{min_trust: 0.5, store: store}, %{})
    assert result.count == 1
    assert hd(result.solutions).trust_score >= 0.5
  end

  test "returns all when no filters", %{store: store} do
    assert {:ok, result} = QuerySolutions.run(%{store: store}, %{})
    assert result.count == 2
  end
end
