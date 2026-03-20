defmodule Pass.Fingerprint.DecomposerTest do
  use ExUnit.Case, async: true

  alias Pass.Fingerprint
  alias Pass.Fingerprint.Decomposer

  describe "decompose/1" do
    test "uses explicit facets when provided" do
      fp =
        Decomposer.decompose(%{
          domain: "deployment",
          target: "fly.io",
          ecosystem: ["elixir"],
          error_class: "build_failure",
          goal: "deploy app",
          symptoms: ["exit code 1"],
          constraints: ["arm64"]
        })

      assert %Fingerprint{} = fp
      assert fp.domain == "deployment"
      assert fp.target == "fly.io"
      assert fp.ecosystem == ["elixir"]
      assert fp.error_class == "build_failure"
      assert fp.goal == "deploy app"
      assert fp.symptoms == ["exit code 1"]
      assert fp.constraints == ["arm64"]
      assert fp.signature != nil
      assert fp.terms != []
    end

    test "infers domain from goal keywords" do
      assert Decomposer.decompose(%{goal: "deploy my app to production"}).domain == "deployment"
      assert Decomposer.decompose(%{goal: "app crashes on startup"}).domain == "runtime"

      assert Decomposer.decompose(%{goal: "slow response times and high latency"}).domain ==
               "performance"

      assert Decomposer.decompose(%{goal: "fix failing tests"}).domain == "testing"
      assert Decomposer.decompose(%{goal: "auth login broken"}).domain == "authentication"
      assert Decomposer.decompose(%{goal: "database migration fails"}).domain == "database"
    end

    test "infers target from goal keywords" do
      assert Decomposer.decompose(%{goal: "deploy to fly.io"}).target == "fly.io"
      assert Decomposer.decompose(%{goal: "heroku build fails"}).target == "heroku"
      assert Decomposer.decompose(%{goal: "aws lambda timeout"}).target == "aws"
      assert Decomposer.decompose(%{goal: "postgres connection pool"}).target == "postgres"
      assert Decomposer.decompose(%{goal: "redis cache issues"}).target == "redis"
      assert Decomposer.decompose(%{goal: "docker build errors"}).target == "docker"
    end

    test "infers error_class from symptoms" do
      assert Decomposer.decompose(%{symptoms: ["exit code 1 during build"]}).error_class ==
               "build_failure"

      assert Decomposer.decompose(%{symptoms: ["request timed out"]}).error_class == "timeout"

      assert Decomposer.decompose(%{symptoms: ["OOM killed by kernel"]}).error_class ==
               "memory_leak"

      assert Decomposer.decompose(%{symptoms: ["process crashed"]}).error_class == "runtime_crash"

      assert Decomposer.decompose(%{symptoms: ["permission denied"]}).error_class ==
               "permission_error"
    end

    test "builds ecosystem from language and framework attrs" do
      fp = Decomposer.decompose(%{language: "Elixir", framework: "Phoenix", goal: "test"})
      assert "elixir" in fp.ecosystem
      assert "phoenix" in fp.ecosystem
    end

    test "merges explicit ecosystem with detected language/framework" do
      fp =
        Decomposer.decompose(%{
          ecosystem: ["liveview"],
          language: "Elixir",
          framework: "Phoenix",
          goal: "test"
        })

      assert "liveview" in fp.ecosystem
      assert "elixir" in fp.ecosystem
      assert "phoenix" in fp.ecosystem
    end

    test "deduplicates ecosystem entries" do
      fp =
        Decomposer.decompose(%{
          ecosystem: ["elixir"],
          language: "elixir",
          goal: "test"
        })

      assert Enum.count(fp.ecosystem, &(&1 == "elixir")) == 1
    end

    test "builds versions from explicit versions and runtime" do
      fp = Decomposer.decompose(%{versions: %{"elixir" => "~> 1.18"}, runtime: "OTP 27"})
      assert fp.versions["elixir"] == "~> 1.18"
      assert fp.versions["runtime"] == "OTP 27"
    end

    test "returns nil facets when nothing can be inferred" do
      fp = Decomposer.decompose(%{goal: "something vague"})
      assert fp.domain == nil
      assert fp.target == nil
      assert fp.error_class == nil
    end

    test "handles string keys in attrs" do
      fp =
        Decomposer.decompose(%{
          "domain" => "testing",
          "target" => "github",
          "goal" => "fix CI"
        })

      assert fp.domain == "testing"
      assert fp.target == "github"
      assert fp.goal == "fix CI"
    end
  end

  describe "decompose_from_legacy/1" do
    test "maps problem_description to goal" do
      fp =
        Decomposer.decompose_from_legacy(%{
          problem_description: "Fix GenServer timeout on high load",
          language: "elixir",
          framework: "phoenix"
        })

      assert fp.goal == "Fix GenServer timeout on high load"
    end

    test "maps language and framework to ecosystem" do
      fp =
        Decomposer.decompose_from_legacy(%{
          problem_description: "test problem",
          language: "elixir",
          framework: "phoenix"
        })

      assert "elixir" in fp.ecosystem
      assert "phoenix" in fp.ecosystem
    end

    test "maps runtime to versions" do
      fp =
        Decomposer.decompose_from_legacy(%{
          problem_description: "test problem",
          language: "elixir",
          runtime: "OTP 27"
        })

      assert fp.versions["runtime"] == "OTP 27"
    end

    test "infers domain from legacy description" do
      fp =
        Decomposer.decompose_from_legacy(%{
          problem_description: "deploy app to production",
          language: "elixir"
        })

      assert fp.domain == "deployment"
    end

    test "falls back to description when problem_description is missing" do
      fp =
        Decomposer.decompose_from_legacy(%{
          description: "crash in GenServer",
          language: "elixir"
        })

      assert fp.goal == "crash in GenServer"
      assert fp.domain == "runtime"
    end

    test "produces a valid fingerprint with signature and terms" do
      fp =
        Decomposer.decompose_from_legacy(%{
          problem_description: "Fix OTP crash in GenServer",
          language: "elixir",
          framework: "phoenix"
        })

      assert fp.signature != nil
      assert byte_size(fp.signature) == 64
      assert is_list(fp.terms)
      assert "fix" in fp.terms
      assert "otp" in fp.terms
      assert "genserver" in fp.terms
    end
  end
end
