defmodule Pass.Actions.PublishSolution do
  @moduledoc """
  Jido action that publishes a solution to the local store.

  Computes the problem signature, creates the Solution struct, scores trust,
  signs with the agent identity, and inserts into the store.
  """

  use Jido.Action,
    name: "publish_solution",
    description: "Publishes a verified solution to the Pass network",
    schema: [
      problem_description: [
        type: :string,
        required: true,
        doc: "Human-readable problem description"
      ],
      solution_content: [type: :string, required: true, doc: "The solution code or content"],
      language: [type: :string, required: true, doc: "Programming language (e.g., elixir)"],
      framework: [type: :string, doc: "Framework (e.g., phoenix)"],
      runtime: [type: :string, doc: "Runtime version"],
      tags: [type: {:list, :string}, default: [], doc: "Tags for categorization"],
      verification: [type: :map, default: %{}, doc: "Verification results map"],
      domain: [type: :string, doc: "Problem domain (e.g., deployment, runtime)"],
      target: [type: :string, doc: "Target tool/service (e.g., fly.io, heroku)"],
      ecosystem: [type: {:list, :string}, doc: "Language/framework stack"],
      versions: [type: :map, doc: "Version constraints map"],
      error_class: [type: :string, doc: "Classified error type"],
      constraints: [type: {:list, :string}, doc: "Hard environment constraints"],
      goal: [type: :string, doc: "Goal description for fingerprint matching"],
      symptoms: [type: {:list, :string}, doc: "Observable symptoms"],
      identity_path: [type: :string, doc: "Path to identity file"],
      store: [type: :atom, doc: "Store GenServer name"]
    ]

  alias Pass.Fingerprint.Decomposer
  alias Pass.Identity
  alias Pass.Solution
  alias Pass.Trust

  @impl true
  def run(params, _context) do
    identity_path = Map.get(params, :identity_path) || Identity.default_identity_path()
    store = Map.get(params, :store) || Pass.Store

    with {:ok, keys} <- Identity.load_keypair(identity_path) do
      agent_id = Identity.agent_id(keys.public_key)

      verification = normalize_verification(Map.get(params, :verification, %{}))

      fingerprint = build_fingerprint(params)

      solution =
        Solution.new(%{
          problem_description: params.problem_description,
          solution_content: params.solution_content,
          language: params.language,
          framework: Map.get(params, :framework),
          runtime: Map.get(params, :runtime),
          tags: Map.get(params, :tags, []),
          verification: verification,
          agent_id: agent_id,
          fingerprint: fingerprint
        })

      trust_score = Trust.score(solution)
      solution = %{solution | trust_score: trust_score}

      sig_data = solution.id <> solution.solution_content
      signature = Identity.sign(sig_data, keys.secret_key) |> Base.encode64()
      solution = %{solution | signature: signature}

      case Pass.Store.insert(solution, fingerprint, store) do
        :ok -> {:ok, Map.from_struct(solution)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp build_fingerprint(params) do
    has_fingerprint_fields =
      Enum.any?(
        [:domain, :target, :ecosystem, :error_class, :goal, :symptoms],
        &Map.has_key?(params, &1)
      )

    if has_fingerprint_fields do
      Decomposer.decompose(params)
    else
      Decomposer.decompose_from_legacy(params)
    end
  end

  defp normalize_verification(v) when is_map(v) do
    %{
      compiled: Map.get(v, :compiled, Map.get(v, "compiled", false)),
      tests_passed: Map.get(v, :tests_passed, Map.get(v, "tests_passed", false)),
      deploy_succeeded: Map.get(v, :deploy_succeeded, Map.get(v, "deploy_succeeded", false))
    }
  end
end
