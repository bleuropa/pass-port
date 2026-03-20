defmodule Pass.Solution do
  @moduledoc """
  Core struct representing a verified solution in the Pass network.

  Solutions are content-addressed by problem signature — a deterministic SHA-256
  hash of the normalized problem description, language, and framework.
  """

  alias Pass.Fingerprint

  @enforce_keys [
    :id,
    :problem_signature,
    :problem_description,
    :solution_content,
    :language,
    :agent_id
  ]
  defstruct [
    :id,
    :problem_signature,
    :problem_description,
    :solution_content,
    :language,
    :framework,
    :runtime,
    :agent_id,
    :signature,
    :fingerprint,
    :inserted_at,
    :updated_at,
    tags: [],
    verification: %{compiled: false, tests_passed: false, deploy_succeeded: false},
    trust_score: 0.0,
    sharing: :attributed
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          problem_signature: String.t(),
          problem_description: String.t(),
          solution_content: String.t(),
          language: String.t(),
          framework: String.t() | nil,
          runtime: String.t() | nil,
          tags: [String.t()],
          verification: %{
            compiled: boolean(),
            tests_passed: boolean(),
            deploy_succeeded: boolean()
          },
          trust_score: float(),
          agent_id: String.t(),
          signature: String.t() | nil,
          fingerprint: Pass.Fingerprint.t() | nil,
          sharing: :local | :anonymous | :attributed,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @doc """
  Computes a deterministic SHA-256 problem signature from a map of problem attributes.

  Keys are sorted and string values are downcased to ensure the same logical problem
  always produces the same hash regardless of key order or casing.

  ## Examples

      iex> Pass.Solution.compute_signature(%{description: "Fix OTP crash", language: "Elixir"})
      iex> Pass.Solution.compute_signature(%{language: "elixir", description: "fix otp crash"})
      # Both return the same hash
  """
  @spec compute_signature(map()) :: String.t()
  def compute_signature(attrs) when is_map(attrs) do
    attrs
    |> Enum.map(fn {k, v} -> {normalize_key(k), normalize_value(v)} end)
    |> Enum.sort_by(fn {k, _v} -> k end)
    |> Enum.map_join("|", fn {k, v} -> "#{k}:#{v}" end)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp normalize_key(k) when is_atom(k), do: Atom.to_string(k)
  defp normalize_key(k) when is_binary(k), do: String.downcase(k)

  defp normalize_value(v) when is_binary(v), do: String.downcase(v)
  defp normalize_value(v), do: to_string(v)

  @doc """
  Creates a new Solution struct from an attrs map.

  Auto-generates a UUID v4 `id` and sets `inserted_at`/`updated_at` to `DateTime.utc_now/0`.
  The `problem_signature` is computed automatically from the attrs if not provided.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    now = DateTime.utc_now()

    problem_sig =
      Map.get(attrs, :problem_signature) || Map.get(attrs, "problem_signature") ||
        compute_signature(extract_signature_input(attrs))

    fingerprint =
      Map.get(attrs, :fingerprint) || maybe_build_fingerprint(attrs)

    struct!(
      __MODULE__,
      Map.merge(attrs, %{
        id: Map.get(attrs, :id) || Map.get(attrs, "id") || generate_uuid(),
        problem_signature: problem_sig,
        fingerprint: fingerprint,
        inserted_at: Map.get(attrs, :inserted_at) || now,
        updated_at: Map.get(attrs, :updated_at) || now
      })
    )
  end

  defp extract_signature_input(attrs) do
    map =
      Map.take(attrs, [
        :description,
        :problem_description,
        :language,
        :framework,
        "description",
        "problem_description",
        "language",
        "framework"
      ])

    normalize_description_key(map)
  end

  defp normalize_description_key(map) do
    cond do
      Map.has_key?(map, :description) ->
        map

      Map.has_key?(map, "description") ->
        map

      Map.has_key?(map, :problem_description) ->
        map
        |> Map.put(:description, map[:problem_description])
        |> Map.delete(:problem_description)

      Map.has_key?(map, "problem_description") ->
        map
        |> Map.put("description", map["problem_description"])
        |> Map.delete("problem_description")

      true ->
        map
    end
  end

  @doc """
  Converts a Solution struct to a plain map suitable for JSON/SQLite storage.

  DateTimes are converted to ISO8601 strings, atoms to strings.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = solution) do
    %{
      "id" => solution.id,
      "problem_signature" => solution.problem_signature,
      "problem_description" => solution.problem_description,
      "solution_content" => solution.solution_content,
      "language" => solution.language,
      "framework" => solution.framework,
      "runtime" => solution.runtime,
      "tags" => Jason.encode!(solution.tags),
      "verification" => Jason.encode!(solution.verification),
      "trust_score" => solution.trust_score,
      "agent_id" => solution.agent_id,
      "signature" => solution.signature,
      "sharing" => Atom.to_string(solution.sharing),
      "fingerprint" => encode_fingerprint(solution.fingerprint),
      "inserted_at" => DateTime.to_iso8601(solution.inserted_at),
      "updated_at" => DateTime.to_iso8601(solution.updated_at)
    }
  end

  @doc """
  Converts a plain map (from JSON/SQLite) back to a Solution struct.

  Parses ISO8601 strings back to DateTimes, string sharing values back to atoms.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      id: map["id"],
      problem_signature: map["problem_signature"],
      problem_description: map["problem_description"],
      solution_content: map["solution_content"],
      language: map["language"],
      framework: map["framework"],
      runtime: map["runtime"],
      tags: decode_json(map["tags"], []),
      verification: decode_verification(map["verification"]),
      trust_score: map["trust_score"] || 0.0,
      agent_id: map["agent_id"],
      signature: map["signature"],
      fingerprint: decode_fingerprint(map["fingerprint"]),
      sharing: parse_sharing(map["sharing"]),
      inserted_at: parse_datetime!(map["inserted_at"]),
      updated_at: parse_datetime!(map["updated_at"])
    }
  end

  defp generate_uuid do
    <<a::48, _::4, b::12, _::2, c::62>> = :crypto.strong_rand_bytes(16)

    <<a::48, 4::4, b::12, 2::2, c::62>>
    |> Base.encode16(case: :lower)
    |> then(fn hex ->
      <<g1::binary-size(8), g2::binary-size(4), g3::binary-size(4), g4::binary-size(4),
        g5::binary-size(12)>> = hex

      "#{g1}-#{g2}-#{g3}-#{g4}-#{g5}"
    end)
  end

  defp decode_json(val, default) when is_binary(val) do
    case Jason.decode(val) do
      {:ok, decoded} -> decoded
      _ -> default
    end
  end

  defp decode_json(val, _default) when is_list(val), do: val
  defp decode_json(val, _default) when is_map(val), do: val
  defp decode_json(_val, default), do: default

  defp decode_verification(val) when is_binary(val) do
    case Jason.decode(val) do
      {:ok, map} -> atomize_verification(map)
      _ -> %{compiled: false, tests_passed: false, deploy_succeeded: false}
    end
  end

  defp decode_verification(val) when is_map(val), do: atomize_verification(val)

  defp decode_verification(_),
    do: %{compiled: false, tests_passed: false, deploy_succeeded: false}

  defp atomize_verification(map) do
    %{
      compiled: Map.get(map, :compiled, Map.get(map, "compiled", false)),
      tests_passed: Map.get(map, :tests_passed, Map.get(map, "tests_passed", false)),
      deploy_succeeded: Map.get(map, :deploy_succeeded, Map.get(map, "deploy_succeeded", false))
    }
  end

  defp parse_sharing("local"), do: :local
  defp parse_sharing("anonymous"), do: :anonymous
  defp parse_sharing("attributed"), do: :attributed
  defp parse_sharing(val) when is_atom(val), do: val
  defp parse_sharing(_), do: :attributed

  defp parse_datetime!(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      {:error, _} -> DateTime.utc_now()
    end
  end

  defp parse_datetime!(%DateTime{} = dt), do: dt
  defp parse_datetime!(nil), do: DateTime.utc_now()

  defp maybe_build_fingerprint(attrs) do
    has_fingerprint_fields =
      Enum.any?(
        [:domain, :target, :ecosystem, :error_class, :goal, :symptoms],
        &(Map.has_key?(attrs, &1) or Map.has_key?(attrs, Atom.to_string(&1)))
      )

    has_legacy_fields =
      Map.has_key?(attrs, :problem_description) or Map.has_key?(attrs, "problem_description")

    cond do
      has_fingerprint_fields ->
        Fingerprint.Decomposer.decompose(attrs)

      has_legacy_fields ->
        Fingerprint.Decomposer.decompose_from_legacy(attrs)

      true ->
        nil
    end
  end

  defp encode_fingerprint(nil), do: nil

  defp encode_fingerprint(%Fingerprint{} = fp) do
    fp |> Fingerprint.to_map() |> Jason.encode!()
  end

  defp decode_fingerprint(nil), do: nil

  defp decode_fingerprint(val) when is_binary(val) do
    case Jason.decode(val) do
      {:ok, map} -> Fingerprint.from_map(map)
      _ -> nil
    end
  end

  defp decode_fingerprint(%{} = map), do: Fingerprint.from_map(map)
end
