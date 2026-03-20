defmodule Pass.Network.HandlerTest do
  use ExUnit.Case, async: true

  alias Pass.Fingerprint
  alias Pass.Network.Handler
  alias Pass.Solution
  alias Pass.Store

  setup do
    tmp_dir = System.tmp_dir!()
    suffix = :erlang.unique_integer([:positive])
    db_path = Path.join(tmp_dir, "pass_handler_test_#{suffix}.db")
    store = :"handler_store_#{suffix}"
    {:ok, pid} = Store.start_link(db_path: db_path, name: store)

    on_exit(fn ->
      try do
        if Process.alive?(pid), do: GenServer.stop(pid)
      catch
        :exit, _ -> :ok
      end

      File.rm(db_path)
    end)

    %{store: store}
  end

  defp make_solution(attrs \\ %{}) do
    defaults = %{
      problem_description: "Test problem",
      solution_content: "# test fix",
      language: "elixir",
      agent_id: "pass_test123"
    }

    Solution.new(Map.merge(defaults, attrs))
  end

  defp make_fingerprint do
    Fingerprint.new(%{
      domain: "runtime",
      target: "otp",
      ecosystem: ["elixir"],
      error_class: "crash"
    })
  end

  defp wrap_payload(solution, fingerprint \\ nil) do
    Handler.wrap_for_broadcast(solution, fingerprint)
  end

  test "stores an incoming solution from CloudEvents payload", %{store: store} do
    solution = make_solution()
    payload = wrap_payload(solution)

    assert {:ok, :stored} = Handler.handle_solution(payload, store)

    {:ok, [stored]} = Store.query([], store)
    assert stored.problem_description == "Test problem"
    assert stored.language == "elixir"
  end

  test "stores solution with fingerprint", %{store: store} do
    solution = make_solution()
    fingerprint = make_fingerprint()
    payload = wrap_payload(solution, fingerprint)

    assert {:ok, :stored} = Handler.handle_solution(payload, store)

    {:ok, [{_sol, fp_map}]} = Store.search(%{domain: "runtime"}, [], store)
    assert fp_map["target"] == "otp"
  end

  test "skips solution with lower trust than existing", %{store: store} do
    # Insert high-trust solution first
    high_trust =
      make_solution(%{trust_score: 0.9})
      |> Map.from_struct()
      |> Map.put(:trust_score, 0.9)
      |> then(&struct!(Solution, &1))

    Store.insert(high_trust, nil, store)

    # Try to insert same problem_signature with lower trust
    low_trust =
      make_solution(%{
        problem_description: high_trust.problem_description,
        language: high_trust.language,
        trust_score: 0.3
      })

    # Ensure same problem_signature
    low_trust =
      struct!(
        Solution,
        Map.put(Map.from_struct(low_trust), :problem_signature, high_trust.problem_signature)
      )

    low_trust = struct!(Solution, Map.put(Map.from_struct(low_trust), :trust_score, 0.3))

    payload = wrap_payload(low_trust)
    assert {:ok, :skipped} = Handler.handle_solution(payload, store)

    # Verify original is still there
    {:ok, [existing]} = Store.query([problem_signature: high_trust.problem_signature], store)
    assert existing.trust_score == 0.9
  end

  test "replaces solution with higher trust", %{store: store} do
    low_trust =
      make_solution(%{trust_score: 0.2})
      |> Map.from_struct()
      |> Map.put(:trust_score, 0.2)
      |> then(&struct!(Solution, &1))

    Store.insert(low_trust, nil, store)

    high_trust =
      make_solution(%{
        problem_description: low_trust.problem_description,
        language: low_trust.language,
        trust_score: 0.8,
        solution_content: "# better fix"
      })

    high_trust =
      struct!(
        Solution,
        Map.put(Map.from_struct(high_trust), :problem_signature, low_trust.problem_signature)
      )

    high_trust = struct!(Solution, Map.put(Map.from_struct(high_trust), :trust_score, 0.8))

    payload = wrap_payload(high_trust)
    assert {:ok, :stored} = Handler.handle_solution(payload, store)
  end

  test "handles payload without CloudEvents wrapper", %{store: store} do
    solution = make_solution()
    solution_map = Solution.to_map(solution)

    payload = %{"solution" => solution_map}
    assert {:ok, :stored} = Handler.handle_solution(payload, store)
  end

  test "returns error for invalid payload" do
    assert {:error, :invalid_payload} = Handler.handle_solution(%{"bad" => "data"})
  end

  test "wrap_for_broadcast produces valid CloudEvents envelope" do
    solution = make_solution()
    fingerprint = make_fingerprint()

    envelope = Handler.wrap_for_broadcast(solution, fingerprint)

    assert envelope["specversion"] == "1.0"
    assert envelope["type"] == "solution.published"
    assert envelope["source"] =~ "pass://"
    assert envelope["datacontenttype"] == "application/json"
    assert envelope["data"]["solution"]["language"] == "elixir"
    assert envelope["data"]["fingerprint"]["domain"] == "runtime"
  end

  test "wrap_for_broadcast with anonymous strips agent_id" do
    solution = make_solution(%{agent_id: "pass_secret_agent"})

    envelope = Handler.wrap_for_broadcast(solution, nil, anonymous: true)

    assert envelope["data"]["solution"]["agent_id"] == "anonymous"
    assert envelope["data"]["solution"]["signature"] == nil
  end
end
