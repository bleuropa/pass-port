defmodule Pass.FingerprintTest do
  use ExUnit.Case, async: true

  alias Pass.Fingerprint

  describe "new/1" do
    test "creates a fingerprint with auto-computed signature and terms" do
      fp =
        Fingerprint.new(%{
          domain: "deployment",
          target: "fly.io",
          ecosystem: ["elixir", "phoenix"],
          error_class: "build_failure",
          goal: "deploy phoenix app with custom buildpack",
          symptoms: ["exit code 1 during docker build"]
        })

      assert fp.domain == "deployment"
      assert fp.target == "fly.io"
      assert fp.ecosystem == ["elixir", "phoenix"]
      assert fp.error_class == "build_failure"
      assert fp.signature != nil
      assert byte_size(fp.signature) == 64
      assert is_list(fp.terms)
      assert "deploy" in fp.terms
      assert "phoenix" in fp.terms
      assert "buildpack" in fp.terms
    end

    test "preserves explicit signature if provided" do
      fp = Fingerprint.new(%{domain: "testing", signature: "custom-sig"})
      assert fp.signature == "custom-sig"
    end

    test "preserves explicit terms if provided" do
      fp = Fingerprint.new(%{domain: "testing", terms: ["custom", "terms"]})
      assert fp.terms == ["custom", "terms"]
    end

    test "defaults lists and maps to empty" do
      fp = Fingerprint.new(%{})
      assert fp.ecosystem == []
      assert fp.versions == %{}
      assert fp.constraints == []
      assert fp.symptoms == []
      assert fp.terms == []
    end
  end

  describe "compute_signature/1" do
    test "returns a 64-char lowercase hex SHA-256 hash" do
      fp = %Fingerprint{domain: "deployment", target: "fly.io", ecosystem: ["elixir"]}
      sig = Fingerprint.compute_signature(fp)
      assert byte_size(sig) == 64
      assert String.match?(sig, ~r/^[0-9a-f]{64}$/)
    end

    test "is deterministic" do
      fp = %Fingerprint{domain: "deployment", target: "fly.io", ecosystem: ["elixir", "phoenix"]}
      assert Fingerprint.compute_signature(fp) == Fingerprint.compute_signature(fp)
    end

    test "sorts ecosystem for consistency" do
      fp1 = %Fingerprint{domain: "deployment", ecosystem: ["phoenix", "elixir"]}
      fp2 = %Fingerprint{domain: "deployment", ecosystem: ["elixir", "phoenix"]}
      assert Fingerprint.compute_signature(fp1) == Fingerprint.compute_signature(fp2)
    end

    test "only uses structural facets" do
      fp1 = %Fingerprint{domain: "deployment", goal: "deploy app"}
      fp2 = %Fingerprint{domain: "deployment", goal: "ship application"}
      assert Fingerprint.compute_signature(fp1) == Fingerprint.compute_signature(fp2)
    end

    test "different structural facets produce different signatures" do
      fp1 = %Fingerprint{domain: "deployment"}
      fp2 = %Fingerprint{domain: "runtime"}
      assert Fingerprint.compute_signature(fp1) != Fingerprint.compute_signature(fp2)
    end
  end

  describe "extract_terms/1" do
    test "tokenizes goal and symptoms into lowercase terms" do
      fp = %Fingerprint{goal: "Deploy Phoenix App", symptoms: ["Exit Code 1"]}
      terms = Fingerprint.extract_terms(fp)
      assert "deploy" in terms
      assert "phoenix" in terms
      assert "app" in terms
      assert "exit" in terms
      assert "code" in terms
      assert "1" in terms
    end

    test "removes stopwords" do
      fp = %Fingerprint{goal: "the app is not working in production"}
      terms = Fingerprint.extract_terms(fp)
      refute "the" in terms
      refute "is" in terms
      refute "not" in terms
      refute "in" in terms
      assert "app" in terms
      assert "working" in terms
      assert "production" in terms
    end

    test "deduplicates terms" do
      fp = %Fingerprint{goal: "crash crash crash", symptoms: ["crash again"]}
      terms = Fingerprint.extract_terms(fp)
      assert Enum.count(terms, &(&1 == "crash")) == 1
    end

    test "returns empty list when goal and symptoms are nil/empty" do
      fp = %Fingerprint{}
      assert Fingerprint.extract_terms(fp) == []
    end

    test "strips non-alphanumeric characters" do
      fp = %Fingerprint{goal: "error: can't compile (mix)"}
      terms = Fingerprint.extract_terms(fp)
      assert "error" in terms
      assert "can" in terms
      assert "t" in terms
      assert "compile" in terms
      assert "mix" in terms
    end
  end

  describe "to_map/1 and from_map/1" do
    test "round-trips a fingerprint through map serialization" do
      original =
        Fingerprint.new(%{
          domain: "deployment",
          target: "fly.io",
          ecosystem: ["elixir", "phoenix"],
          versions: %{"elixir" => "~> 1.18", "otp" => "~> 27"},
          error_class: "build_failure",
          constraints: ["arm64"],
          goal: "deploy phoenix app",
          symptoms: ["exit code 1"]
        })

      map = Fingerprint.to_map(original)
      restored = Fingerprint.from_map(map)

      assert restored.domain == original.domain
      assert restored.target == original.target
      assert restored.ecosystem == original.ecosystem
      assert restored.versions == original.versions
      assert restored.error_class == original.error_class
      assert restored.constraints == original.constraints
      assert restored.goal == original.goal
      assert restored.symptoms == original.symptoms
      assert restored.signature == original.signature
      assert restored.terms == original.terms
    end

    test "to_map JSON-encodes lists and maps" do
      fp =
        Fingerprint.new(%{
          ecosystem: ["elixir", "phoenix"],
          versions: %{"elixir" => "~> 1.18"},
          constraints: ["arm64"],
          symptoms: ["error 1"],
          terms: ["elixir", "deploy"]
        })

      map = Fingerprint.to_map(fp)

      assert is_binary(map["ecosystem"])
      assert {:ok, ["elixir", "phoenix"]} = Jason.decode(map["ecosystem"])
      assert is_binary(map["versions"])
      assert {:ok, %{"elixir" => "~> 1.18"}} = Jason.decode(map["versions"])
      assert is_binary(map["constraints"])
      assert is_binary(map["symptoms"])
      assert is_binary(map["terms"])
    end

    test "from_map handles already-decoded values" do
      map = %{
        "domain" => "testing",
        "target" => nil,
        "ecosystem" => ["elixir"],
        "versions" => %{},
        "error_class" => nil,
        "constraints" => [],
        "goal" => "test something",
        "symptoms" => [],
        "signature" => "abc123",
        "terms" => ["test", "something"]
      }

      fp = Fingerprint.from_map(map)
      assert fp.domain == "testing"
      assert fp.ecosystem == ["elixir"]
      assert fp.terms == ["test", "something"]
    end
  end
end
