defmodule Pass.Matcher.Facets do
  @moduledoc """
  Individual facet matchers for fingerprint comparison.

  Each function takes two fingerprints (query and candidate) and returns
  a `{score, match_type, detail}` tuple.
  """

  alias Pass.Fingerprint
  alias Pass.Fingerprint.Taxonomy

  @spec domain_score(Fingerprint.t(), Fingerprint.t()) :: {float(), atom(), term()}
  def domain_score(%Fingerprint{domain: q}, %Fingerprint{domain: c}) do
    score = Taxonomy.domain_similarity(q, c)
    type = match_type_for_score(score)
    {score, type, %{query: q, candidate: c}}
  end

  @spec target_score(Fingerprint.t(), Fingerprint.t()) :: {float(), atom(), term()}
  def target_score(%Fingerprint{target: q}, %Fingerprint{target: c}) do
    cond do
      q == nil or c == nil -> {1.0, :no_constraint, nil}
      q == c -> {1.0, :exact, c}
      true -> {0.0, :mismatch, %{query: q, candidate: c}}
    end
  end

  @spec ecosystem_score(Fingerprint.t(), Fingerprint.t()) :: {float(), atom(), term()}
  def ecosystem_score(%Fingerprint{ecosystem: q}, %Fingerprint{ecosystem: c}) do
    q_set = MapSet.new(q)
    c_set = MapSet.new(c)

    if MapSet.size(q_set) == 0 and MapSet.size(c_set) == 0 do
      {1.0, :no_constraint, []}
    else
      intersection = MapSet.intersection(q_set, c_set) |> MapSet.size()
      union = MapSet.union(q_set, c_set) |> MapSet.size()
      jaccard = intersection / union

      {jaccard, :"jaccard_#{Float.round(jaccard, 2)}",
       MapSet.to_list(MapSet.intersection(q_set, c_set))}
    end
  end

  @spec version_score(Fingerprint.t(), Fingerprint.t()) :: {float(), atom(), term()}
  def version_score(%Fingerprint{versions: q}, %Fingerprint{versions: c}) do
    shared_keys = Map.keys(q) |> Enum.filter(&Map.has_key?(c, &1))

    if shared_keys == [] do
      {1.0, :no_constraint, %{}}
    else
      results =
        Map.new(shared_keys, fn key ->
          {key, version_compat(q[key], c[key])}
        end)

      avg = results |> Map.values() |> Enum.sum() |> Kernel./(length(shared_keys))
      {avg, :version_check, results}
    end
  end

  @spec error_class_score(Fingerprint.t(), Fingerprint.t()) :: {float(), atom(), term()}
  def error_class_score(%Fingerprint{error_class: q}, %Fingerprint{error_class: c}) do
    score = Taxonomy.error_similarity(q, c)
    type = match_type_for_score(score)
    {score, type, %{query: q, candidate: c}}
  end

  @spec constraint_score(Fingerprint.t(), Fingerprint.t()) :: {float(), atom(), term()}
  def constraint_score(%Fingerprint{constraints: q}, %Fingerprint{constraints: c}) do
    if q == [] do
      {1.0, :no_constraint, []}
    else
      q_set = MapSet.new(q)
      c_set = MapSet.new(c)

      if MapSet.subset?(q_set, c_set) do
        {1.0, :satisfied, q}
      else
        {0.0, :unsatisfied, %{missing: MapSet.difference(q_set, c_set) |> MapSet.to_list()}}
      end
    end
  end

  @spec goal_score(Fingerprint.t(), Fingerprint.t()) :: {float(), atom(), term()}
  def goal_score(%Fingerprint{} = query, %Fingerprint{} = candidate) do
    q_terms = goal_terms(query)
    c_terms = goal_terms(candidate)
    term_jaccard(q_terms, c_terms, :goal_overlap)
  end

  @spec symptom_score(Fingerprint.t(), Fingerprint.t()) :: {float(), atom(), term()}
  def symptom_score(%Fingerprint{} = query, %Fingerprint{} = candidate) do
    q_terms = symptom_terms(query)
    c_terms = symptom_terms(candidate)
    term_jaccard(q_terms, c_terms, :symptom_overlap)
  end

  defp goal_terms(%Fingerprint{goal: nil}), do: MapSet.new()

  defp goal_terms(%Fingerprint{goal: goal}) do
    goal |> tokenize() |> MapSet.new()
  end

  defp symptom_terms(%Fingerprint{symptoms: []}), do: MapSet.new()

  defp symptom_terms(%Fingerprint{symptoms: symptoms}) do
    symptoms |> Enum.join(" ") |> tokenize() |> MapSet.new()
  end

  defp tokenize(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s]/, " ")
    |> String.split(~r/\s+/, trim: true)
  end

  defp term_jaccard(q_set, c_set, label) do
    if MapSet.size(q_set) == 0 and MapSet.size(c_set) == 0 do
      {1.0, :no_constraint, []}
    else
      intersection = MapSet.intersection(q_set, c_set) |> MapSet.size()
      union = MapSet.union(q_set, c_set) |> MapSet.size()
      score = intersection / union
      {score, label, MapSet.to_list(MapSet.intersection(q_set, c_set))}
    end
  end

  defp version_compat(q_ver, c_ver) do
    q_major = extract_major(q_ver)
    c_major = extract_major(c_ver)

    cond do
      q_major == nil or c_major == nil -> 0.5
      q_major == c_major -> 1.0
      abs(q_major - c_major) == 1 -> 0.5
      true -> 0.2
    end
  end

  defp extract_major(version_str) do
    case Regex.run(~r/(\d+)/, version_str) do
      [_, major] -> String.to_integer(major)
      _ -> nil
    end
  end

  defp match_type_for_score(score) do
    cond do
      score == 1.0 -> :exact
      score >= 0.7 -> :parent_child
      score >= 0.5 -> :sibling
      score >= 0.3 -> :same_root
      score > 0.0 -> :partial
      true -> :mismatch
    end
  end
end
