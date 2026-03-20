defmodule Pass.Integration.NetworkTest do
  @moduledoc """
  Integration test simulating end-to-end solution sharing between two agents.

  Tests the full pipeline: create solution -> wrap for broadcast -> simulate
  relay delivery -> handler processes -> solution appears in remote store.

  Uses a single Slipstream test client to verify the WebSocket publish flow,
  and the Handler module directly to verify the receive/store flow.
  """
  use Slipstream.SocketTest

  alias Pass.Fingerprint
  alias Pass.Network.Client
  alias Pass.Network.Handler
  alias Pass.Solution
  alias Pass.Store

  @lobby "solutions:lobby"

  setup do
    tmp_dir = System.tmp_dir!()
    suffix = :erlang.unique_integer([:positive])

    # Node A store — the publisher
    db_a = Path.join(tmp_dir, "pass_integ_a_#{suffix}.db")
    store_a = :"integ_store_a_#{suffix}"
    {:ok, pid_a} = Store.start_link(db_path: db_a, name: store_a)

    # Node B store — the consumer
    db_b = Path.join(tmp_dir, "pass_integ_b_#{suffix}.db")
    store_b = :"integ_store_b_#{suffix}"
    {:ok, pid_b} = Store.start_link(db_path: db_b, name: store_b)

    # Slipstream test client for Node A
    client_a =
      start_supervised!(
        {Client,
         agent_id: "agent_alpha",
         url: "ws://localhost:4000/socket/agent/websocket",
         test_mode?: true,
         name: :"integ_client_a_#{suffix}"}
      )

    on_exit(fn ->
      for pid <- [pid_a, pid_b] do
        try do
          if Process.alive?(pid), do: GenServer.stop(pid)
        catch
          :exit, _ -> :ok
        end
      end

      File.rm(db_a)
      File.rm(db_b)
    end)

    %{
      store_a: store_a,
      store_b: store_b,
      client_a: client_a
    }
  end

  defp make_solution(overrides \\ %{}) do
    base = %{
      problem_description: "Fix GenServer timeout in production",
      solution_content:
        "defmodule Fix do\n  def handle_call(_, _, state), do: {:reply, :ok, state}\nend",
      language: "elixir",
      framework: "phoenix",
      agent_id: "agent_alpha"
    }

    Solution.new(Map.merge(base, overrides))
  end

  defp make_fingerprint(overrides \\ %{}) do
    base = %{
      domain: "runtime",
      target: "otp",
      ecosystem: ["elixir", "phoenix"],
      error_class: "timeout",
      goal: "prevent genserver timeouts under load"
    }

    Fingerprint.new(Map.merge(base, overrides))
  end

  describe "end-to-end: publish from A, receive on B" do
    test "full pipeline: A publishes -> relay -> B stores solution with fingerprint", ctx do
      # 1. Connect Node A to the relay
      accept_connect(ctx.client_a)
      assert_join(@lobby, _, :ok)

      # 2. Node A creates a solution and wraps it for broadcast
      solution = make_solution()
      fingerprint = make_fingerprint()
      envelope = Handler.wrap_for_broadcast(solution, fingerprint)

      # 3. Store locally on A
      :ok = Store.insert(solution, fingerprint, ctx.store_a)

      # 4. Node A publishes to the relay
      Client.publish(envelope, ctx.client_a)
      assert_push(@lobby, "publish_solution", ^envelope)

      # 5. Relay broadcasts to Node B (simulated — this is what the relay does)
      #    Node B's handler processes the incoming payload
      {:ok, :stored} = Handler.handle_solution(envelope, ctx.store_b)

      # 6. Verify Node B has the solution
      {:ok, solutions_b} = Store.query([], ctx.store_b)
      assert length(solutions_b) == 1

      stored = hd(solutions_b)
      assert stored.problem_description == "Fix GenServer timeout in production"
      assert stored.language == "elixir"
      assert stored.framework == "phoenix"
      assert stored.agent_id == "agent_alpha"

      # 7. Verify fingerprint was stored on B
      {:ok, [{_sol, fp_map}]} = Store.search(%{domain: "runtime"}, [], ctx.store_b)
      assert fp_map["domain"] == "runtime"
      assert fp_map["target"] == "otp"
      assert fp_map["error_class"] == "timeout"
      assert fp_map["goal"] == "prevent genserver timeouts under load"
    end

    test "agent_id on received solution matches the publisher", ctx do
      accept_connect(ctx.client_a)
      assert_join(@lobby, _, :ok)

      solution = make_solution(%{agent_id: "agent_alpha"})
      envelope = Handler.wrap_for_broadcast(solution, nil)

      {:ok, :stored} = Handler.handle_solution(envelope, ctx.store_b)

      {:ok, [stored]} = Store.query([], ctx.store_b)
      assert stored.agent_id == "agent_alpha"
    end

    test "bidirectional: both nodes can publish and receive", ctx do
      accept_connect(ctx.client_a)
      assert_join(@lobby, _, :ok)

      # A publishes a solution
      sol_a = make_solution(%{problem_description: "problem from A", agent_id: "agent_alpha"})
      env_a = Handler.wrap_for_broadcast(sol_a, nil)

      # B receives A's solution
      {:ok, :stored} = Handler.handle_solution(env_a, ctx.store_b)

      # B publishes a different solution
      sol_b =
        make_solution(%{
          problem_description: "problem from B",
          agent_id: "agent_beta",
          solution_content: "# beta fix"
        })

      env_b = Handler.wrap_for_broadcast(sol_b, nil)

      # A receives B's solution
      {:ok, :stored} = Handler.handle_solution(env_b, ctx.store_a)

      # Verify A has B's solution
      {:ok, solutions_a} = Store.query([], ctx.store_a)
      assert Enum.any?(solutions_a, &(&1.agent_id == "agent_beta"))

      # Verify B has A's solution
      {:ok, solutions_b} = Store.query([], ctx.store_b)
      assert Enum.any?(solutions_b, &(&1.agent_id == "agent_alpha"))
    end
  end

  describe "privacy: sharing controls" do
    test "local sharing — solution stays on publisher, never broadcast", ctx do
      accept_connect(ctx.client_a)
      assert_join(@lobby, _, :ok)

      solution = make_solution(%{sharing: :local})
      assert solution.sharing == :local

      # Store locally on A
      :ok = Store.insert(solution, nil, ctx.store_a)

      # Verify A has it
      {:ok, [stored_a]} = Store.query([], ctx.store_a)
      assert stored_a.id == solution.id

      # B never receives it — no broadcast was made
      {:ok, solutions_b} = Store.query([], ctx.store_b)
      assert solutions_b == []
    end

    test "anonymous sharing — B receives solution without agent_id", ctx do
      accept_connect(ctx.client_a)
      assert_join(@lobby, _, :ok)

      solution = make_solution(%{sharing: :anonymous, agent_id: "agent_alpha"})
      fingerprint = make_fingerprint()

      # Wrap with anonymous flag (as the PublishSolution action would)
      envelope = Handler.wrap_for_broadcast(solution, fingerprint, anonymous: true)

      # Verify the envelope strips identity
      assert envelope["data"]["solution"]["agent_id"] == "anonymous"
      assert envelope["data"]["solution"]["signature"] == nil
      assert envelope["source"] == "pass://anonymous"

      # B receives the anonymous broadcast
      {:ok, :stored} = Handler.handle_solution(envelope, ctx.store_b)

      {:ok, [stored]} = Store.query([], ctx.store_b)
      assert stored.agent_id == "anonymous"

      # The solution content is still there
      assert stored.problem_description == "Fix GenServer timeout in production"
      assert stored.language == "elixir"
    end

    test "attributed sharing — B receives solution with full identity", ctx do
      accept_connect(ctx.client_a)
      assert_join(@lobby, _, :ok)

      solution = make_solution(%{sharing: :attributed, agent_id: "agent_alpha"})
      envelope = Handler.wrap_for_broadcast(solution, nil)

      assert envelope["data"]["solution"]["agent_id"] == "agent_alpha"

      {:ok, :stored} = Handler.handle_solution(envelope, ctx.store_b)

      {:ok, [stored]} = Store.query([], ctx.store_b)
      assert stored.agent_id == "agent_alpha"
    end
  end

  describe "deduplication across nodes" do
    test "same solution received twice — B only stores one copy", ctx do
      accept_connect(ctx.client_a)
      assert_join(@lobby, _, :ok)

      solution = make_solution()
      fingerprint = make_fingerprint()
      envelope = Handler.wrap_for_broadcast(solution, fingerprint)

      # B receives the solution twice (network retry, duplicate relay)
      {:ok, :stored} = Handler.handle_solution(envelope, ctx.store_b)
      {:ok, :skipped} = Handler.handle_solution(envelope, ctx.store_b)

      {:ok, solutions} = Store.query([], ctx.store_b)
      assert length(solutions) == 1
    end

    test "higher-trust version replaces lower-trust on B", ctx do
      accept_connect(ctx.client_a)
      assert_join(@lobby, _, :ok)

      low_trust = make_solution(%{trust_score: 0.3})
      low_trust = struct!(Solution, Map.put(Map.from_struct(low_trust), :trust_score, 0.3))

      high_trust =
        make_solution(%{
          problem_description: low_trust.problem_description,
          language: low_trust.language,
          trust_score: 0.9,
          solution_content: "# improved fix"
        })

      high_trust =
        high_trust
        |> Map.from_struct()
        |> Map.put(:problem_signature, low_trust.problem_signature)
        |> Map.put(:trust_score, 0.9)
        |> then(&struct!(Solution, &1))

      env_low = Handler.wrap_for_broadcast(low_trust, nil)
      env_high = Handler.wrap_for_broadcast(high_trust, nil)

      # B receives low trust first, then high trust
      {:ok, :stored} = Handler.handle_solution(env_low, ctx.store_b)
      {:ok, :stored} = Handler.handle_solution(env_high, ctx.store_b)

      {:ok, solutions} =
        Store.query([problem_signature: low_trust.problem_signature], ctx.store_b)

      assert length(solutions) == 1
      assert hd(solutions).trust_score == 0.9
    end

    test "lower-trust version does NOT replace higher-trust on B", ctx do
      accept_connect(ctx.client_a)
      assert_join(@lobby, _, :ok)

      high_trust = make_solution(%{trust_score: 0.9})
      high_trust = struct!(Solution, Map.put(Map.from_struct(high_trust), :trust_score, 0.9))

      low_trust =
        make_solution(%{
          problem_description: high_trust.problem_description,
          language: high_trust.language,
          trust_score: 0.2
        })

      low_trust =
        low_trust
        |> Map.from_struct()
        |> Map.put(:problem_signature, high_trust.problem_signature)
        |> Map.put(:trust_score, 0.2)
        |> then(&struct!(Solution, &1))

      env_high = Handler.wrap_for_broadcast(high_trust, nil)
      env_low = Handler.wrap_for_broadcast(low_trust, nil)

      {:ok, :stored} = Handler.handle_solution(env_high, ctx.store_b)
      {:ok, :skipped} = Handler.handle_solution(env_low, ctx.store_b)

      {:ok, [stored]} =
        Store.query([problem_signature: high_trust.problem_signature], ctx.store_b)

      assert stored.trust_score == 0.9
    end
  end

  describe "WebSocket client integration" do
    test "client connects and joins lobby", ctx do
      accept_connect(ctx.client_a)
      assert_join(@lobby, _, :ok)

      info = Client.status(ctx.client_a)
      assert info.status == :connected
      assert @lobby in info.channels
      assert info.agent_id == "agent_alpha"
    end

    test "client publishes CloudEvents envelope to lobby", ctx do
      accept_connect(ctx.client_a)
      assert_join(@lobby, _, :ok)

      solution = make_solution()
      envelope = Handler.wrap_for_broadcast(solution, nil)

      Client.publish(envelope, ctx.client_a)
      assert_push(@lobby, "publish_solution", ^envelope)
    end

    test "CloudEvents envelope round-trips correctly through wrap and handle", ctx do
      accept_connect(ctx.client_a)
      assert_join(@lobby, _, :ok)

      solution = make_solution()
      fingerprint = make_fingerprint()

      # Wrap for broadcast
      envelope = Handler.wrap_for_broadcast(solution, fingerprint)

      # Verify CloudEvents structure
      assert envelope["specversion"] == "1.0"
      assert envelope["type"] == "solution.published"
      assert envelope["source"] == "pass://agent_alpha"
      assert envelope["data"]["solution"]["language"] == "elixir"
      assert envelope["data"]["fingerprint"]["domain"] == "runtime"

      # Process through handler into store
      {:ok, :stored} = Handler.handle_solution(envelope, ctx.store_b)

      {:ok, [stored]} = Store.query([], ctx.store_b)
      assert stored.problem_description == solution.problem_description
      assert stored.solution_content == solution.solution_content
    end
  end
end
