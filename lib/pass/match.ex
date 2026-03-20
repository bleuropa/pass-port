defmodule Pass.Match do
  @moduledoc """
  Result struct for a fingerprint match, including the weighted score,
  per-facet breakdown, and confidence level.
  """

  defstruct [
    :solution,
    :fingerprint,
    :score,
    :breakdown,
    :confidence
  ]

  @type match_detail :: {float(), atom(), term()}

  @type t :: %__MODULE__{
          solution: Pass.Solution.t(),
          fingerprint: Pass.Fingerprint.t(),
          score: float(),
          breakdown: %{atom() => match_detail()},
          confidence: :high | :medium | :low
        }
end
