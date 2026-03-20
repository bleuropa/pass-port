defmodule Pass.Actions.PublishSolutionTest do
  use ExUnit.Case, async: true

  alias Pass.Actions.PublishSolution
  alias Pass.Identity
  alias Pass.Store

  setup do
    tmp_dir = System.tmp_dir!()
    suffix = :erlang.unique_integer([:positive])

    # Set up identity
    identity_path = Path.join(tmp_dir, "pass_test_identity_#{suffix}.json")
    keypair = Identity.generate_keypair()
    :ok = Identity.save_keypair(keypair, identity_path)

    # Set up store
    db_path = Path.join(tmp_dir, "pass_test_pub_#{suffix}.db")
    store = :"store_pub_#{suffix}"
    {:ok, pid} = Store.start_link(db_path: db_path, name: store)

    on_exit(fn ->
      try do
        if Process.alive?(pid), do: GenServer.stop(pid)
      catch
        :exit, _ -> :ok
      end

      File.rm(db_path)
      File.rm(identity_path)
    end)

    %{store: store, identity_path: identity_path, keypair: keypair}
  end

  test "publishes a solution and returns it", %{store: store, identity_path: identity_path} do
    params = %{
      problem_description: "Fix GenServer timeout",
      solution_content: "defmodule Fix do\nend",
      language: "elixir",
      framework: "phoenix",
      tags: ["otp"],
      verification: %{compiled: true, tests_passed: true, deploy_succeeded: false},
      identity_path: identity_path,
      store: store
    }

    assert {:ok, result} = PublishSolution.run(params, %{})
    assert result.id != nil
    assert result.problem_description == "Fix GenServer timeout"
    assert result.language == "elixir"
    assert result.trust_score > 0.0
    assert result.signature != nil
    assert result.agent_id =~ ~r/^pass_/
  end

  test "solution is stored and retrievable", %{store: store, identity_path: identity_path} do
    params = %{
      problem_description: "Handle Ecto timeout",
      solution_content: "# ecto fix",
      language: "elixir",
      identity_path: identity_path,
      store: store
    }

    {:ok, result} = PublishSolution.run(params, %{})
    {:ok, retrieved} = Store.get(result.id, store)
    assert retrieved.problem_description == "Handle Ecto timeout"
  end

  test "returns error when identity is missing", %{store: store} do
    params = %{
      problem_description: "test",
      solution_content: "test",
      language: "elixir",
      identity_path: "/tmp/nonexistent_identity.json",
      store: store
    }

    assert {:error, :not_found} = PublishSolution.run(params, %{})
  end

  test "publishes with fingerprint attrs and stores them", %{
    store: store,
    identity_path: identity_path
  } do
    params = %{
      problem_description: "Deploy fails on fly.io",
      solution_content: "# fix dockerfile",
      language: "elixir",
      framework: "phoenix",
      domain: "deployment",
      target: "fly.io",
      ecosystem: ["elixir", "phoenix"],
      error_class: "build_failure",
      goal: "deploy phoenix app to fly.io",
      symptoms: ["exit code 1 during docker build"],
      identity_path: identity_path,
      store: store
    }

    assert {:ok, result} = PublishSolution.run(params, %{})
    assert result.fingerprint != nil
    assert result.fingerprint.domain == "deployment"
    assert result.fingerprint.target == "fly.io"
    assert result.fingerprint.error_class == "build_failure"

    {:ok, [{_sol, fp_map}]} = Store.search(%{domain: "deployment"}, [], store)
    assert fp_map["target"] == "fly.io"
  end

  test "publishes legacy-style attrs and auto-generates fingerprint", %{
    store: store,
    identity_path: identity_path
  } do
    params = %{
      problem_description: "GenServer crashes on timeout",
      solution_content: "# fix timeout",
      language: "elixir",
      identity_path: identity_path,
      store: store
    }

    assert {:ok, result} = PublishSolution.run(params, %{})
    assert result.fingerprint != nil
    assert "elixir" in result.fingerprint.ecosystem
  end
end
