defmodule Pass.Fingerprint.Decomposer do
  @moduledoc """
  Smart extraction of fingerprint facets from raw problem attributes.

  The decomposer infers structural facets (domain, target, error_class)
  from textual descriptions when they aren't explicitly provided. This
  bridges the gap between unstructured problem reports and the structured
  fingerprint format used for retrieval.
  """

  alias Pass.Fingerprint

  @domain_keywords [
    {"deployment", ~w(deploy deployment deploying deployed ship shipping release releasing)},
    {"performance", ~w(slow performance latency throughput bottleneck lag)},
    {"authentication", ~w(auth authentication login logout session token oauth)},
    {"database", ~w(db database query sql migration schema table index)},
    {"testing", ~w(test testing spec assertion expect)},
    {"runtime", ~w(crash error exception fault panic abort segfault)}
  ]

  @target_keywords [
    {"fly.io", ~w(fly fly.io flyctl)},
    {"heroku", ~w(heroku)},
    {"aws", ~w(aws amazon ec2 s3 lambda ecs)},
    {"postgres", ~w(postgres postgresql psql pg)},
    {"redis", ~w(redis)},
    {"github", ~w(github gh actions)},
    {"docker", ~w(docker dockerfile container)},
    {"kubernetes", ~w(kubernetes k8s kubectl helm)},
    {"vercel", ~w(vercel)},
    {"nginx", ~w(nginx)}
  ]

  @error_class_patterns [
    {"build_failure", ["exit code", "build fail", "compile error"]},
    {"timeout", ["timeout", "timed out", "deadline"]},
    {"memory_leak", ["oom", "out of memory", "memory leak", "killed"]},
    {"runtime_crash", ["crash", "crashed", "segfault", "panic", "abort"]},
    {"permission_error", ["permission", "denied", "forbidden", "unauthorized", "403"]}
  ]

  @doc """
  Decomposes raw attributes into a Fingerprint.

  Explicitly provided facets are used as-is. Missing facets are inferred
  from textual fields (goal, symptoms, description).
  """
  @spec decompose(map()) :: Fingerprint.t()
  def decompose(attrs) when is_map(attrs) do
    text = build_search_text(attrs)

    Fingerprint.new(%{
      domain: get_attr(attrs, :domain) || infer_domain(text),
      target: get_attr(attrs, :target) || infer_target(text),
      ecosystem: build_ecosystem(attrs),
      versions: build_versions(attrs),
      error_class: get_attr(attrs, :error_class) || infer_error_class(attrs),
      goal: get_attr(attrs, :goal),
      symptoms: get_attr(attrs, :symptoms) || [],
      constraints: get_attr(attrs, :constraints) || []
    })
  end

  @doc """
  Converts legacy Solution-style attrs to a Fingerprint.

  Maps `problem_description` to `goal`, `language`/`framework` to `ecosystem`, etc.
  """
  @spec decompose_from_legacy(map()) :: Fingerprint.t()
  def decompose_from_legacy(attrs) when is_map(attrs) do
    mapped = %{
      goal: get_attr(attrs, :problem_description) || get_attr(attrs, :description),
      symptoms: get_attr(attrs, :symptoms) || [],
      constraints: get_attr(attrs, :constraints) || [],
      domain: get_attr(attrs, :domain),
      target: get_attr(attrs, :target),
      error_class: get_attr(attrs, :error_class)
    }

    language = get_attr(attrs, :language)
    framework = get_attr(attrs, :framework)
    runtime = get_attr(attrs, :runtime)

    ecosystem =
      [language, framework, runtime]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&String.downcase/1)

    versions =
      if runtime do
        %{"runtime" => runtime}
      else
        %{}
      end

    mapped
    |> Map.put(:ecosystem, ecosystem)
    |> Map.put(:versions, versions)
    |> decompose()
  end

  defp build_search_text(attrs) do
    [
      get_attr(attrs, :goal),
      get_attr(attrs, :description),
      attrs |> get_attr(:symptoms) |> List.wrap() |> Enum.join(" ")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> String.downcase()
  end

  defp infer_domain(text) do
    @domain_keywords
    |> Enum.find_value(fn {domain, keywords} ->
      if Enum.any?(keywords, &String.contains?(text, &1)), do: domain
    end)
  end

  defp infer_target(text) do
    @target_keywords
    |> Enum.find_value(fn {target, keywords} ->
      if Enum.any?(keywords, &String.contains?(text, &1)), do: target
    end)
  end

  defp infer_error_class(attrs) do
    symptoms = get_attr(attrs, :symptoms) || []
    text = symptoms |> Enum.join(" ") |> String.downcase()

    @error_class_patterns
    |> Enum.find_value(fn {error_class, patterns} ->
      if Enum.any?(patterns, &String.contains?(text, &1)), do: error_class
    end)
  end

  defp build_ecosystem(attrs) do
    explicit = get_attr(attrs, :ecosystem) || []

    detected =
      [
        get_attr(attrs, :language),
        get_attr(attrs, :framework)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&String.downcase/1)

    (explicit ++ detected)
    |> Enum.uniq()
  end

  defp build_versions(attrs) do
    explicit = get_attr(attrs, :versions) || %{}

    runtime = get_attr(attrs, :runtime)

    if runtime do
      Map.put_new(explicit, "runtime", runtime)
    else
      explicit
    end
  end

  defp get_attr(attrs, key) when is_atom(key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end
end
