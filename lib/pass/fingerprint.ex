defmodule Pass.Fingerprint do
  @moduledoc """
  Structured problem fingerprint for multi-dimensional matching.

  A fingerprint decomposes a problem into orthogonal facets — structural
  (categorical, fast matching) and semantic (text-based, fuzzy matching).
  The agent does the hard work of understanding the problem; the retrieval
  system just matches structured data.
  """

  defstruct [
    :domain,
    :target,
    :error_class,
    :goal,
    :signature,
    ecosystem: [],
    versions: %{},
    constraints: [],
    symptoms: [],
    terms: []
  ]

  @type t :: %__MODULE__{
          domain: String.t() | nil,
          target: String.t() | nil,
          ecosystem: [String.t()],
          versions: %{optional(String.t()) => String.t()},
          error_class: String.t() | nil,
          constraints: [String.t()],
          goal: String.t() | nil,
          symptoms: [String.t()],
          signature: String.t() | nil,
          terms: [String.t()]
        }

  @stopwords ~w(the a an is are was were in on at to for of with and or but not this that it)

  @doc """
  Creates a new Fingerprint from an attrs map.

  Auto-computes the `signature` (SHA-256 of structural facets) and
  `terms` (tokenized goal + symptoms with stopwords removed).
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    fingerprint = struct!(__MODULE__, attrs)

    %{
      fingerprint
      | signature: fingerprint.signature || compute_signature(fingerprint),
        terms:
          fingerprint.terms
          |> then(fn t -> if t == [], do: extract_terms(fingerprint), else: t end)
    }
  end

  @doc """
  Computes a SHA-256 signature from the structural facets only.

  This is used for exact dedup — two fingerprints with the same domain,
  target, sorted ecosystem, and error_class produce the same signature.
  """
  @spec compute_signature(t()) :: String.t()
  def compute_signature(%__MODULE__{} = fp) do
    ecosystem_str = fp.ecosystem |> Enum.sort() |> Enum.join(",")

    [
      "domain:#{fp.domain || ""}",
      "target:#{fp.target || ""}",
      "ecosystem:#{ecosystem_str}",
      "error_class:#{fp.error_class || ""}"
    ]
    |> Enum.join("|")
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc """
  Extracts search terms from goal and symptoms.

  Tokenizes text into lowercase words, removes common stopwords, and deduplicates.
  """
  @spec extract_terms(t()) :: [String.t()]
  def extract_terms(%__MODULE__{} = fp) do
    text = [fp.goal | fp.symptoms] |> Enum.reject(&is_nil/1) |> Enum.join(" ")

    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s]/, " ")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reject(&(&1 in @stopwords))
    |> Enum.uniq()
  end

  @doc """
  Converts a Fingerprint struct to a plain map for JSON/SQLite storage.

  Lists and maps are JSON-encoded as strings.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = fp) do
    %{
      "domain" => fp.domain,
      "target" => fp.target,
      "ecosystem" => Jason.encode!(fp.ecosystem),
      "version_constraints" => Jason.encode!(fp.versions),
      "error_class" => fp.error_class,
      "constraints" => Jason.encode!(fp.constraints),
      "goal" => fp.goal,
      "symptoms" => Jason.encode!(fp.symptoms),
      "signature" => fp.signature,
      "terms" => Jason.encode!(fp.terms)
    }
  end

  @doc """
  Converts a plain map (from JSON/SQLite) back to a Fingerprint struct.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      domain: map["domain"],
      target: map["target"],
      ecosystem: decode_json(map["ecosystem"], []),
      versions: decode_json(map["version_constraints"] || map["versions"], %{}),
      error_class: map["error_class"],
      constraints: decode_json(map["constraints"], []),
      goal: map["goal"],
      symptoms: decode_json(map["symptoms"], []),
      signature: map["signature"],
      terms: decode_json(map["terms"], [])
    }
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
end
