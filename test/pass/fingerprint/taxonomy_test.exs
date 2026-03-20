defmodule Pass.Fingerprint.TaxonomyTest do
  use ExUnit.Case, async: true

  alias Pass.Fingerprint.Taxonomy

  describe "domain_tree/0" do
    test "returns a map with string keys and string-or-nil values" do
      tree = Taxonomy.domain_tree()
      assert is_map(tree)
      assert Map.get(tree, "infrastructure") == nil
      assert Map.get(tree, "deployment") == "infrastructure"
      assert Map.get(tree, "containerization") == "deployment"
    end
  end

  describe "error_tree/0" do
    test "returns a map with string keys and string-or-nil values" do
      tree = Taxonomy.error_tree()
      assert is_map(tree)
      assert Map.get(tree, "failure") == nil
      assert Map.get(tree, "build_failure") == "failure"
      assert Map.get(tree, "timeout") == "degradation"
    end
  end

  describe "domain_similarity/2" do
    test "both nil returns 1.0" do
      assert Taxonomy.domain_similarity(nil, nil) == 1.0
    end

    test "one nil returns 0.5" do
      assert Taxonomy.domain_similarity(nil, "deployment") == 0.5
      assert Taxonomy.domain_similarity("deployment", nil) == 0.5
    end

    test "exact match returns 1.0" do
      assert Taxonomy.domain_similarity("deployment", "deployment") == 1.0
      assert Taxonomy.domain_similarity("security", "security") == 1.0
    end

    test "parent/child returns 0.7" do
      assert Taxonomy.domain_similarity("deployment", "infrastructure") == 0.7
      assert Taxonomy.domain_similarity("infrastructure", "deployment") == 0.7
      assert Taxonomy.domain_similarity("containerization", "deployment") == 0.7
    end

    test "siblings (same parent) returns 0.5" do
      assert Taxonomy.domain_similarity("deployment", "networking") == 0.5
      assert Taxonomy.domain_similarity("deployment", "monitoring") == 0.5
      assert Taxonomy.domain_similarity("authentication", "authorization") == 0.5
    end

    test "same root category returns 0.3" do
      # containerization -> deployment -> infrastructure
      # monitoring -> infrastructure
      # Both share root "infrastructure" but are not parent/child or siblings
      assert Taxonomy.domain_similarity("containerization", "monitoring") == 0.3
      assert Taxonomy.domain_similarity("containerization", "networking") == 0.3
      assert Taxonomy.domain_similarity("unit_testing", "debugging") == 0.3
      assert Taxonomy.domain_similarity("migrations", "caching") == 0.3
    end

    test "different root categories returns 0.0" do
      assert Taxonomy.domain_similarity("deployment", "authentication") == 0.0
      assert Taxonomy.domain_similarity("infrastructure", "security") == 0.0
      assert Taxonomy.domain_similarity("caching", "encryption") == 0.0
    end

    test "unknown domain returns 0.0" do
      assert Taxonomy.domain_similarity("deployment", "banana") == 0.0
      assert Taxonomy.domain_similarity("banana", "deployment") == 0.0
      assert Taxonomy.domain_similarity("banana", "apple") == 0.0
    end

    test "aliases resolve before comparison" do
      # "deploy" -> "deployment"
      assert Taxonomy.domain_similarity("deploy", "deployment") == 1.0
      assert Taxonomy.domain_similarity("deploy", "infrastructure") == 0.7
      assert Taxonomy.domain_similarity("db", "database") == 1.0
      assert Taxonomy.domain_similarity("k8s", "containerization") == 1.0
    end

    test "case insensitive" do
      assert Taxonomy.domain_similarity("Deployment", "DEPLOYMENT") == 1.0
      assert Taxonomy.domain_similarity("Deploy", "deployment") == 1.0
    end
  end

  describe "error_similarity/2" do
    test "both nil returns 1.0" do
      assert Taxonomy.error_similarity(nil, nil) == 1.0
    end

    test "one nil returns 0.5" do
      assert Taxonomy.error_similarity(nil, "timeout") == 0.5
    end

    test "exact match returns 1.0" do
      assert Taxonomy.error_similarity("build_failure", "build_failure") == 1.0
    end

    test "parent/child returns 0.7" do
      assert Taxonomy.error_similarity("build_failure", "failure") == 0.7
      assert Taxonomy.error_similarity("timeout", "degradation") == 0.7
    end

    test "siblings returns 0.5" do
      assert Taxonomy.error_similarity("build_failure", "runtime_crash") == 0.5
      assert Taxonomy.error_similarity("build_failure", "deploy_failure") == 0.5
      assert Taxonomy.error_similarity("timeout", "memory_leak") == 0.5
      assert Taxonomy.error_similarity("type_error", "syntax_error") == 0.5
    end

    test "different root categories returns 0.0" do
      assert Taxonomy.error_similarity("build_failure", "timeout") == 0.0
      assert Taxonomy.error_similarity("failure", "degradation") == 0.0
      assert Taxonomy.error_similarity("type_error", "runtime_crash") == 0.0
    end

    test "aliases resolve before comparison" do
      assert Taxonomy.error_similarity("crash", "runtime_crash") == 1.0
      assert Taxonomy.error_similarity("oom", "memory_leak") == 1.0
      assert Taxonomy.error_similarity("hang", "timeout") == 1.0
    end

    test "unknown error class returns 0.0" do
      assert Taxonomy.error_similarity("build_failure", "unknown_thing") == 0.0
    end
  end

  describe "find_domain/1" do
    test "returns canonical name for known domains" do
      assert Taxonomy.find_domain("deployment") == "deployment"
      assert Taxonomy.find_domain("infrastructure") == "infrastructure"
    end

    test "resolves aliases" do
      assert Taxonomy.find_domain("deploy") == "deployment"
      assert Taxonomy.find_domain("db") == "database"
      assert Taxonomy.find_domain("auth") == "authentication"
      assert Taxonomy.find_domain("perf") == "performance"
      assert Taxonomy.find_domain("ci") == "ci_cd"
      assert Taxonomy.find_domain("k8s") == "containerization"
    end

    test "case insensitive" do
      assert Taxonomy.find_domain("DEPLOY") == "deployment"
      assert Taxonomy.find_domain("Infrastructure") == "infrastructure"
    end

    test "returns nil for unknown" do
      assert Taxonomy.find_domain("banana") == nil
      assert Taxonomy.find_domain(nil) == nil
    end
  end

  describe "find_error_class/1" do
    test "returns canonical name for known error classes" do
      assert Taxonomy.find_error_class("build_failure") == "build_failure"
      assert Taxonomy.find_error_class("timeout") == "timeout"
    end

    test "resolves aliases" do
      assert Taxonomy.find_error_class("crash") == "runtime_crash"
      assert Taxonomy.find_error_class("oom") == "memory_leak"
      assert Taxonomy.find_error_class("hang") == "timeout"
      assert Taxonomy.find_error_class("404") == "permission_error"
    end

    test "returns nil for unknown" do
      assert Taxonomy.find_error_class("banana") == nil
      assert Taxonomy.find_error_class(nil) == nil
    end
  end

  describe "domain_aliases/0" do
    test "returns a map of alias -> canonical name" do
      aliases = Taxonomy.domain_aliases()
      assert is_map(aliases)
      assert aliases["deploy"] == "deployment"
      assert aliases["db"] == "database"
    end
  end

  describe "error_aliases/0" do
    test "returns a map of alias -> canonical name" do
      aliases = Taxonomy.error_aliases()
      assert is_map(aliases)
      assert aliases["crash"] == "runtime_crash"
      assert aliases["oom"] == "memory_leak"
    end
  end
end
