defmodule Pass.Actions.QuerySolutions do
  @moduledoc """
  Jido action that queries the local solution store.
  """

  use Jido.Action,
    name: "query_solutions",
    description: "Queries the Pass solution store for matching solutions",
    schema: [
      problem: [type: :string, doc: "Problem description to search for"],
      language: [type: :string, doc: "Filter by programming language"],
      framework: [type: :string, doc: "Filter by framework"],
      min_trust: [type: :float, doc: "Minimum trust score (0.0-1.0)"],
      store: [type: :atom, doc: "Store GenServer name"]
    ]

  alias Pass.Solution

  @impl true
  def run(params, _context) do
    store = Map.get(params, :store) || Pass.Store

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
