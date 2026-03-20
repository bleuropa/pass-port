defmodule Pass.Fingerprint.Taxonomy do
  @moduledoc """
  Domain and error class taxonomies for hierarchical similarity matching.

  Each taxonomy is a flat map of `%{node => parent}` where root nodes have
  parent `nil`. Similarity is computed by walking ancestor chains to find
  the relationship between two nodes.
  """

  @domain_tree %{
    # Root categories
    "infrastructure" => nil,
    "development" => nil,
    "data" => nil,
    "security" => nil,
    "performance" => nil,
    # Infrastructure children
    "deployment" => "infrastructure",
    "networking" => "infrastructure",
    "monitoring" => "infrastructure",
    # Deployment children
    "containerization" => "deployment",
    "ci_cd" => "deployment",
    "cloud_hosting" => "deployment",
    # Networking children
    "dns" => "networking",
    "load_balancing" => "networking",
    # Development children
    "testing" => "development",
    "debugging" => "development",
    "tooling" => "development",
    # Testing children
    "unit_testing" => "testing",
    "integration_testing" => "testing",
    # Data children
    "database" => "data",
    "caching" => "data",
    "search" => "data",
    # Database children
    "migrations" => "database",
    "queries" => "database",
    "indexing" => "database",
    # Security children
    "authentication" => "security",
    "authorization" => "security",
    "encryption" => "security",
    # Performance children
    "optimization" => "performance",
    "profiling" => "performance",
    "scaling" => "performance"
  }

  @error_tree %{
    # Root categories
    "failure" => nil,
    "error" => nil,
    "degradation" => nil,
    # Failure children
    "build_failure" => "failure",
    "runtime_crash" => "failure",
    "deploy_failure" => "failure",
    "test_failure" => "failure",
    # Error children
    "type_error" => "error",
    "syntax_error" => "error",
    "validation_error" => "error",
    "permission_error" => "error",
    # Degradation children
    "timeout" => "degradation",
    "memory_leak" => "degradation",
    "slow_query" => "degradation",
    "rate_limit" => "degradation"
  }

  @domain_aliases %{
    "deploy" => "deployment",
    "db" => "database",
    "auth" => "authentication",
    "perf" => "performance",
    "ci" => "ci_cd",
    "cd" => "ci_cd",
    "k8s" => "containerization",
    "kubernetes" => "containerization",
    "docker" => "containerization",
    "container" => "containerization",
    "net" => "networking",
    "network" => "networking",
    "cache" => "caching",
    "test" => "testing",
    "debug" => "debugging",
    "tools" => "tooling",
    "scale" => "scaling",
    "optimize" => "optimization",
    "profile" => "profiling",
    "encrypt" => "encryption",
    "authz" => "authorization",
    "infra" => "infrastructure",
    "dev" => "development",
    "sec" => "security",
    "index" => "indexing",
    "query" => "queries",
    "migrate" => "migrations",
    "migration" => "migrations",
    "hosting" => "cloud_hosting",
    "cloud" => "cloud_hosting",
    "lb" => "load_balancing"
  }

  @error_aliases %{
    "crash" => "runtime_crash",
    "oom" => "memory_leak",
    "out_of_memory" => "memory_leak",
    "404" => "permission_error",
    "403" => "permission_error",
    "hang" => "timeout",
    "hung" => "timeout",
    "slow" => "slow_query",
    "type" => "type_error",
    "syntax" => "syntax_error",
    "validation" => "validation_error",
    "permission" => "permission_error",
    "build" => "build_failure",
    "compile" => "build_failure",
    "deploy" => "deploy_failure",
    "test" => "test_failure",
    "limit" => "rate_limit",
    "throttle" => "rate_limit",
    "leak" => "memory_leak"
  }

  @doc "Returns the domain taxonomy as `%{node => parent}` map."
  @spec domain_tree() :: %{String.t() => String.t() | nil}
  def domain_tree, do: @domain_tree

  @doc "Returns the error class taxonomy as `%{node => parent}` map."
  @spec error_tree() :: %{String.t() => String.t() | nil}
  def error_tree, do: @error_tree

  @doc "Returns the domain alias map."
  @spec domain_aliases() :: %{String.t() => String.t()}
  def domain_aliases, do: @domain_aliases

  @doc "Returns the error class alias map."
  @spec error_aliases() :: %{String.t() => String.t()}
  def error_aliases, do: @error_aliases

  @doc """
  Computes similarity (0.0-1.0) between two domain strings.

  - Both nil -> 1.0
  - One nil -> 0.5
  - Exact match -> 1.0
  - Parent/child -> 0.7
  - Siblings (same parent) -> 0.5
  - Same root category -> 0.3
  - Unrelated -> 0.0
  """
  @spec domain_similarity(String.t() | nil, String.t() | nil) :: float()
  def domain_similarity(a, b) do
    similarity(
      resolve(a, @domain_aliases, @domain_tree),
      resolve(b, @domain_aliases, @domain_tree),
      @domain_tree
    )
  end

  @doc """
  Computes similarity (0.0-1.0) between two error class strings.

  Same scoring logic as `domain_similarity/2`.
  """
  @spec error_similarity(String.t() | nil, String.t() | nil) :: float()
  def error_similarity(a, b) do
    similarity(
      resolve(a, @error_aliases, @error_tree),
      resolve(b, @error_aliases, @error_tree),
      @error_tree
    )
  end

  @doc """
  Resolves a string to its canonical domain name.

  Handles aliases and is case-insensitive. Returns `nil` for unknown strings.
  """
  @spec find_domain(String.t() | nil) :: String.t() | nil
  def find_domain(nil), do: nil

  def find_domain(input) when is_binary(input) do
    case resolve(input, @domain_aliases, @domain_tree) do
      :unknown -> nil
      canonical -> canonical
    end
  end

  @doc """
  Resolves a string to its canonical error class name.

  Handles aliases and is case-insensitive. Returns `nil` for unknown strings.
  """
  @spec find_error_class(String.t() | nil) :: String.t() | nil
  def find_error_class(nil), do: nil

  def find_error_class(input) when is_binary(input) do
    case resolve(input, @error_aliases, @error_tree) do
      :unknown -> nil
      canonical -> canonical
    end
  end

  defp resolve(nil, _aliases, _tree), do: nil

  defp resolve(input, aliases, tree) do
    normalized = String.downcase(input)

    cond do
      Map.has_key?(tree, normalized) ->
        normalized

      Map.has_key?(aliases, normalized) ->
        Map.fetch!(aliases, normalized)

      true ->
        :unknown
    end
  end

  defp similarity(nil, nil, _tree), do: 1.0
  defp similarity(nil, _b, _tree), do: 0.5
  defp similarity(_a, nil, _tree), do: 0.5
  defp similarity(:unknown, _, _tree), do: 0.0
  defp similarity(_, :unknown, _tree), do: 0.0
  defp similarity(a, a, _tree), do: 1.0

  defp similarity(a, b, tree) do
    if not Map.has_key?(tree, a) or not Map.has_key?(tree, b) do
      0.0
    else
      relationship_score(a, b, tree)
    end
  end

  defp relationship_score(a, b, tree) do
    cond do
      b == Map.get(tree, a) or a == Map.get(tree, b) ->
        0.7

      Map.get(tree, a) == Map.get(tree, b) and Map.get(tree, a) != nil ->
        0.5

      root(ancestors(a, tree)) == root(ancestors(b, tree)) and
          root(ancestors(a, tree)) != nil ->
        0.3

      true ->
        0.0
    end
  end

  defp ancestors(node, tree) do
    case Map.get(tree, node) do
      nil -> [node]
      parent -> [node | ancestors(parent, tree)]
    end
  end

  defp root(ancestors), do: List.last(ancestors)
end
