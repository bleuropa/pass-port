# Pass Retrieval System — Design Document

## The Problem

Current matching: SHA-256 hash of normalized problem text. Only matches if
the exact same words are used in the exact same order. Useless in practice.

"Fix OTP crash in GenServer" and "GenServer process crashes unexpectedly"
are the same problem but produce different hashes.

## Core Insight: Agent-as-Decomposer

Traditional search systems get dumb queries and need smart backends (embeddings,
re-rankers, query expansion). Pass gets the opposite: **the agent has full context**
(code, errors, stack traces, goals) and can emit a rich structured fingerprint.

The retrieval backend can be simple because the hard work — understanding the
problem — already happened in the agent.

## The Fingerprint

Every problem gets decomposed into orthogonal facets:

```elixir
%Pass.Fingerprint{
  # === Structural facets (categorical, fast matching) ===
  domain:       "deployment",                          # broad problem category
  target:       "fly.io",                              # specific tool/service/API
  ecosystem:    ["elixir", "phoenix", "liveview"],     # language + framework stack
  versions:     %{"elixir" => "~> 1.18", "otp" => "~> 27"},  # semver constraints
  error_class:  "build_failure",                       # classified error type
  constraints:  ["arm64", "alpine"],                   # hard environment constraints

  # === Semantic facets (text-based, fuzzy matching) ===
  goal:         "deploy phoenix app with custom buildpack",
  symptoms:     ["exit code 1 during docker build", "mix release fails"],

  # === Derived ===
  signature:    "sha256:...",    # hash of structural facets only (for exact dedup)
  terms:        ["deploy", "phoenix", "buildpack", "fly", "docker", "exit code"],
}
```

The agent (LLM) does the decomposition. It sees the full problem context and
extracts structured facets. The retrieval system just matches structured data.

## Matching Algorithm

Each facet has its own matching strategy:

```
score = (
  0.10 * domain_score        +  # exact or taxonomy (deployment ~ infrastructure)
  0.10 * target_score         +  # exact match on tool/service
  0.20 * ecosystem_score      +  # Jaccard similarity on stack sets
  0.10 * version_score        +  # semver range compatibility
  0.10 * error_class_score    +  # exact or hierarchy
  0.05 * constraint_score     +  # hard filter (0 or 1)
  0.15 * goal_score           +  # BM25 text similarity
  0.20 * symptom_score           # BM25 text similarity
)
```

### Individual Matchers

**Domain** — Categorical with taxonomy. "deployment" partially matches
"infrastructure". Exact = 1.0, parent/child = 0.7, sibling = 0.4, unrelated = 0.0.

**Target** — Exact string match. "fly.io" matches "fly.io" = 1.0, else 0.0.

**Ecosystem** — Jaccard similarity on set of stack components.
`["elixir", "phoenix"]` vs `["elixir", "phoenix", "liveview"]` = 2/3 = 0.67.

**Versions** — Semver range compatibility check per shared ecosystem component.
Query wants elixir ~> 1.18, candidate has elixir 1.17 → partial match.
Score = (compatible_components / total_components).

**Error class** — Categorical with hierarchy. "build_failure" partially matches
"deploy_failure" (sibling under "failure"). Exact = 1.0, sibling = 0.5.

**Constraints** — Hard filter. If query has constraints, candidate must satisfy
ALL of them. Score is binary: 1.0 or 0.0.

**Goal** — BM25 text ranking via SQLite FTS5. Fuzzy term matching with
TF-IDF weighting. Handles word order variation, partial matches.

**Symptoms** — BM25 text ranking via SQLite FTS5. Same as goal but scored
independently because symptom matching is high signal.

### Match Confidence & Explainability

Every match returns a breakdown:

```elixir
%Pass.Match{
  solution: %Pass.Solution{...},
  score: 0.87,
  breakdown: %{
    domain: {0.10, :exact, "deployment"},
    target: {0.10, :exact, "fly.io"},
    ecosystem: {0.13, :jaccard_0.67, ["elixir", "phoenix"]},
    versions: {0.08, :compatible, %{"elixir" => true, "otp" => false}},
    error_class: {0.10, :exact, "build_failure"},
    constraints: {0.05, :satisfied, ["arm64"]},
    goal: {0.14, :bm25_0.92, "deploy phoenix app..."},
    symptoms: {0.17, :bm25_0.85, ["exit code 1..."]}
  },
  confidence: :high  # :high (>0.75), :medium (0.5-0.75), :low (<0.5)
}
```

The consuming agent can inspect WHY a match was made and decide whether to
trust it. Black-box "similarity 0.83" is replaced by structured reasoning.

## Storage Schema (SQLite)

```sql
-- Updated solutions table with fingerprint facets
CREATE TABLE solutions (
  id TEXT PRIMARY KEY,
  problem_signature TEXT NOT NULL,

  -- Fingerprint structural facets
  domain TEXT,
  target TEXT,
  ecosystem TEXT,           -- JSON: ["elixir", "phoenix"]
  version_constraints TEXT, -- JSON: {"elixir": "~> 1.18"}
  error_class TEXT,
  constraints TEXT,         -- JSON: ["arm64", "alpine"]
  goal TEXT,
  symptoms TEXT,            -- JSON: ["symptom 1", "symptom 2"]

  -- Existing solution data
  problem_description TEXT,
  solution_content TEXT NOT NULL,
  language TEXT,
  framework TEXT,
  runtime TEXT,
  tags TEXT,
  verification TEXT,
  trust_score REAL DEFAULT 0.0,
  agent_id TEXT,
  signature TEXT,
  sharing TEXT DEFAULT 'attributed',
  inserted_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- FTS5 for text-based matching (goal + symptoms + description)
CREATE VIRTUAL TABLE IF NOT EXISTS solutions_fts USING fts5(
  goal,
  symptoms,
  problem_description,
  tags,
  tokenize='porter unicode61'  -- stemming + unicode normalization
);

-- Facet indexes for fast filtering
CREATE INDEX idx_solutions_domain ON solutions(domain);
CREATE INDEX idx_solutions_target ON solutions(target);
CREATE INDEX idx_solutions_error_class ON solutions(error_class);
CREATE INDEX idx_solutions_ecosystem ON solutions(ecosystem);
```

### Query Flow

1. Agent decomposes problem → Fingerprint
2. **Hard filter**: constraints, target (if specified) — eliminates incompatible solutions
3. **Faceted scoring**: domain, ecosystem, versions, error_class — narrows candidates
4. **Text ranking**: FTS5 BM25 on goal + symptoms — ranks remaining candidates
5. **Combine**: weighted score across all dimensions
6. **Return**: ranked matches with score breakdown

The query is a two-phase process: SQL filtering narrows candidates, then
in-memory scoring ranks them. This scales to millions of solutions.

## Forward-Looking Features (Phase 2+)

### Solution Lineage
Solutions track derivation:
```
Solution A (fly v1, 2025-01, trust: 0.6)
  └── B (fly v2, 2025-06, supersedes A, trust: 0.9)
       └── C (fly v2 + buildpack, 2025-09, extends B, trust: 0.85)
```
Old solutions in a chain auto-decay. Querying returns the best node in each
lineage tree, not duplicates.

### Problem Convergence
When a single solution resolves multiple different-fingerprint problems,
those problems get linked into equivalence clusters. Future queries match
against cluster centroids. Collaborative filtering for problems.

### Inverse Matching (Push)
When a new solution is published, proactively match it against known unsolved
problems. Notify agents: "A solution just appeared for a problem you hit."

### Embedding Layer (Optional)
Add dense vectors to the goal/symptoms facets for deeper semantic matching.
The structural matching works without embeddings — they're an optimization
for long-tail queries where BM25 falls short.

### Ecosystem Evolution Tracking
Track framework/library version releases. When Elixir 1.19 ships, solutions
pinned to 1.17 decay faster. Version distance becomes a decay factor beyond
simple freshness.

## Module Structure

```
lib/pass/
├── fingerprint.ex          # Fingerprint struct + decomposition helpers
├── fingerprint/
│   ├── decomposer.ex       # Extracts fingerprint from raw problem attrs
│   └── taxonomy.ex         # Domain/error_class hierarchies
├── matcher.ex              # Multi-dimensional matching engine
├── matcher/
│   ├── facets.ex           # Individual facet matchers
│   ├── text.ex             # BM25/FTS5 text matching
│   └── scorer.ex           # Weighted score combination
├── match.ex                # Match result struct with breakdown
├── store.ex                # Updated with FTS5 + faceted queries
└── store/
    └── migrations.ex       # Updated schema with fingerprint columns + FTS5
```
