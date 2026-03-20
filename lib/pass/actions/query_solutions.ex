defmodule Pass.Actions.QuerySolutions do
  @moduledoc """
  Jido action that queries the local solution store.
  """

  use Jido.Action,
    name: "query_solutions",
    description: "Queries the Pass solution store for matching solutions",
    schema: [
      problem: [type: :string, doc: "Problem description to search for (legacy)"],
      language: [type: :string, doc: "Filter by programming language"],
      framework: [type: :string, doc: "Filter by framework"],
      min_trust: [type: :float, doc: "Minimum trust score (0.0-1.0)"],
      domain: [type: :string, doc: "Problem domain for fingerprint matching"],
      target: [type: :string, doc: "Target tool/service"],
      ecosystem: [type: {:list, :string}, doc: "Language/framework stack"],
      error_class: [type: :string, doc: "Classified error type"],
      goal: [type: :string, doc: "Goal description"],
      symptoms: [type: {:list, :string}, doc: "Observable symptoms"],
      min_score: [type: :float, doc: "Minimum match score (0.0-1.0, default 0.3)"],
      limit: [type: :integer, doc: "Max results (default 10)"],
      store: [type: :atom, doc: "Store GenServer name"]
    ]

  alias Pass.Fingerprint
  alias Pass.Fingerprint.Decomposer
  alias Pass.Matcher
  alias Pass.Solution

  @fingerprint_keys [:domain, :target, :ecosystem, :error_class, :goal, :symptoms]

  @impl true
  def run(params, _context) do
    store = Map.get(params, :store) || Pass.Store

    if has_fingerprint_fields?(params) do
      run_fingerprint_query(params, store)
    else
      run_legacy_query(params, store)
    end
  end

  defp has_fingerprint_fields?(params) do
    Enum.any?(@fingerprint_keys, &Map.has_key?(params, &1))
  end

  defp run_fingerprint_query(params, store) do
    query_fp = Decomposer.decompose(params)

    search_map = %{
      domain: query_fp.domain,
      target: query_fp.target,
      error_class: query_fp.error_class
    }

    search_opts = if mt = Map.get(params, :min_trust), do: [min_trust: mt], else: []

    case Pass.Store.search(search_map, search_opts, store) do
      {:ok, candidates} ->
        typed_candidates =
          Enum.map(candidates, fn {solution, fp_map} ->
            {solution, Fingerprint.from_map(fp_map)}
          end)

        match_opts = [
          min_score: Map.get(params, :min_score, 0.3),
          limit: Map.get(params, :limit, 10)
        ]

        matches = Matcher.match(query_fp, typed_candidates, match_opts)

        {:ok, %{matches: matches, count: length(matches)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_legacy_query(params, store) do
    filters = build_filters(params)

    case Pass.Store.query(filters, store) do
      {:ok, solutions} ->
        results = Enum.map(solutions, &Map.from_struct/1)
        {:ok, %{solutions: results, count: length(results)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_filters(params) do
    filters = []

    filters =
      if problem = Map.get(params, :problem) do
        sig =
          Solution.compute_signature(%{
            description: problem,
            language: Map.get(params, :language, "")
          })

        [{:problem_signature, sig} | filters]
      else
        filters
      end

    filters =
      if lang = Map.get(params, :language), do: [{:language, lang} | filters], else: filters

    filters = if fw = Map.get(params, :framework), do: [{:framework, fw} | filters], else: filters
    filters = if mt = Map.get(params, :min_trust), do: [{:min_trust, mt} | filters], else: filters

    filters
  end
end
