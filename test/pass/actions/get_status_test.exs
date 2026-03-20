defmodule Pass.Actions.GetStatusTest do
  use ExUnit.Case, async: true

  alias Pass.Actions.GetStatus
  alias Pass.Identity
  alias Pass.Solution
  alias Pass.Store

  setup do
    tmp_dir = System.tmp_dir!()
    suffix = :erlang.unique_integer([:positive])

    # Set up identity
    identity_path = Path.join(tmp_dir, "pass_test_status_identity_#{suffix}.json")
    keypair = Identity.generate_keypair()
    :ok = Identity.save_keypair(keypair, identity_path)

    # Set up store
    db_path = Path.join(tmp_dir, "pass_test_status_#{suffix}.db")
    store = :"store_status_#{suffix}"
    {:ok, pid} = Store.start_link(db_path: db_path, name: store)

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
      File.rm(db_path)
      File.rm(identity_path)
    end)

    %{store: store, identity_path: identity_path, keypair: keypair}
  end

  test "returns status with identity and empty store", %{
    store: store,
    identity_path: identity_path
  } do
    assert {:ok, result} = GetStatus.run(%{identity_path: identity_path, store: store}, %{})
    assert result.agent_id =~ ~r/^pass_/
    assert result.identity_initialized == true
    assert result.contributions == 0
    assert result.network_status == :local
  end

  test "returns correct contribution count", %{store: store, identity_path: identity_path} do
    :ok =
      Store.insert(
        Solution.new(%{
          problem_description: "test",
          solution_content: "# test",
          language: "elixir",
          agent_id: "agent-001"
        }),
        store
      )

    assert {:ok, result} = GetStatus.run(%{identity_path: identity_path, store: store}, %{})
    assert result.contributions == 1
  end

  test "handles missing identity gracefully", %{store: store} do
    params = %{identity_path: "/tmp/nonexistent_identity.json", store: store}
    assert {:ok, result} = GetStatus.run(params, %{})
    assert result.agent_id == nil
    assert result.identity_initialized == false
  end
end
