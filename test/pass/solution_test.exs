defmodule Pass.SolutionTest do
  use ExUnit.Case, async: true

  alias Pass.Solution

  @valid_attrs %{
    problem_description: "Fix GenServer timeout on high load",
    solution_content: "defmodule MyFix do\n  # ...\nend",
    language: "elixir",
    framework: "phoenix",
    agent_id: "agent-abc-123"
  }

  describe "new/1" do
    test "creates a solution with auto-generated ID and timestamps" do
      solution = Solution.new(@valid_attrs)

      assert solution.id != nil

      assert String.match?(
               solution.id,
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
             )

      assert %DateTime{} = solution.inserted_at
      assert %DateTime{} = solution.updated_at
      assert solution.problem_description == "Fix GenServer timeout on high load"
      assert solution.language == "elixir"
      assert solution.framework == "phoenix"
      assert solution.agent_id == "agent-abc-123"
    end

    test "auto-computes problem_signature from description, language, framework" do
      solution = Solution.new(@valid_attrs)
      assert solution.problem_signature != nil
      assert byte_size(solution.problem_signature) == 64
    end

    test "uses provided problem_signature if given" do
      attrs = Map.put(@valid_attrs, :problem_signature, "custom-sig")
      solution = Solution.new(attrs)
      assert solution.problem_signature == "custom-sig"
    end

    test "applies default values" do
      solution = Solution.new(@valid_attrs)

      assert solution.tags == []
      assert solution.trust_score == 0.0
      assert solution.sharing == :attributed

      assert solution.verification == %{
               compiled: false,
               tests_passed: false,
               deploy_succeeded: false
             }

      assert solution.signature == nil
      assert solution.runtime == nil
    end
  end

  describe "compute_signature/1" do
    test "returns a 64-char lowercase hex SHA-256 hash" do
      sig = Solution.compute_signature(%{description: "test", language: "elixir"})
      assert byte_size(sig) == 64
      assert String.match?(sig, ~r/^[0-9a-f]{64}$/)
    end

    test "is deterministic — same input produces same hash" do
      input = %{description: "Fix OTP crash", language: "elixir", framework: "phoenix"}
      sig1 = Solution.compute_signature(input)
      sig2 = Solution.compute_signature(input)
      assert sig1 == sig2
    end

    test "normalizes key order — different ordering produces same hash" do
      sig1 = Solution.compute_signature(%{description: "bug fix", language: "elixir"})
      sig2 = Solution.compute_signature(%{language: "elixir", description: "bug fix"})
      assert sig1 == sig2
    end

    test "normalizes string casing" do
      sig1 = Solution.compute_signature(%{description: "Fix Bug", language: "Elixir"})
      sig2 = Solution.compute_signature(%{description: "fix bug", language: "elixir"})
      assert sig1 == sig2
    end

    test "handles atom keys the same as string keys" do
      sig1 = Solution.compute_signature(%{description: "test", language: "elixir"})
      sig2 = Solution.compute_signature(%{"description" => "test", "language" => "elixir"})
      assert sig1 == sig2
    end

    test "different input produces different hash" do
      sig1 = Solution.compute_signature(%{description: "fix crash", language: "elixir"})
      sig2 = Solution.compute_signature(%{description: "add feature", language: "elixir"})
      assert sig1 != sig2
    end
  end

  describe "to_map/1 and from_map/1" do
    test "round-trips a solution through map serialization" do
      original = Solution.new(@valid_attrs)
      map = Solution.to_map(original)
      restored = Solution.from_map(map)

      assert restored.id == original.id
      assert restored.problem_signature == original.problem_signature
      assert restored.problem_description == original.problem_description
      assert restored.solution_content == original.solution_content
      assert restored.language == original.language
      assert restored.framework == original.framework
      assert restored.runtime == original.runtime
      assert restored.tags == original.tags
      assert restored.verification == original.verification
      assert restored.trust_score == original.trust_score
      assert restored.agent_id == original.agent_id
      assert restored.signature == original.signature
      assert restored.sharing == original.sharing
      assert DateTime.compare(restored.inserted_at, original.inserted_at) == :eq
      assert DateTime.compare(restored.updated_at, original.updated_at) == :eq
    end

    test "to_map converts DateTimes to ISO8601 strings" do
      solution = Solution.new(@valid_attrs)
      map = Solution.to_map(solution)

      assert is_binary(map["inserted_at"])
      assert {:ok, _, _} = DateTime.from_iso8601(map["inserted_at"])
    end

    test "to_map converts sharing atom to string" do
      solution = Solution.new(@valid_attrs)
      map = Solution.to_map(solution)
      assert map["sharing"] == "attributed"
    end

    test "to_map JSON-encodes tags and verification" do
      solution = Solution.new(Map.merge(@valid_attrs, %{tags: ["otp", "genserver"]}))
      map = Solution.to_map(solution)

      assert is_binary(map["tags"])
      assert {:ok, ["otp", "genserver"]} = Jason.decode(map["tags"])

      assert is_binary(map["verification"])
      assert {:ok, %{"compiled" => false}} = Jason.decode(map["verification"])
    end

    test "from_map handles already-decoded tags and verification" do
      original = Solution.new(@valid_attrs)
      map = Solution.to_map(original)

      decoded_map =
        map
        |> Map.put("tags", Jason.decode!(map["tags"]))
        |> Map.put("verification", Jason.decode!(map["verification"]))

      restored = Solution.from_map(decoded_map)
      assert restored.tags == original.tags
      assert restored.verification == original.verification
    end
  end
end
