defmodule Pass.MatchTest do
  use ExUnit.Case, async: true

  alias Pass.Match

  describe "Match struct" do
    test "can be created with all fields" do
      match = %Match{
        solution: nil,
        fingerprint: nil,
        score: 0.85,
        breakdown: %{domain: {1.0, :exact, "deployment"}},
        confidence: :high
      }

      assert match.score == 0.85
      assert match.confidence == :high
    end

    test "defaults all fields to nil" do
      match = %Match{}
      assert match.solution == nil
      assert match.fingerprint == nil
      assert match.score == nil
      assert match.breakdown == nil
      assert match.confidence == nil
    end
  end
end
