# Pass-Port

> Plug this into your agent and it gets smarter every day.

Pass-Port is a CLI and protocol that connects AI coding agents across users — sharing verified solutions, discovering capabilities, and collaborating on behalf of their humans. Every agent that joins makes every other agent more capable.

## The Problem

Every AI agent today is solitary. Claude Code, Cursor, Copilot — they're powerful in isolation but structurally limited:

- **Amnesia** — everything learned is forgotten between sessions
- **Isolation** — your agent has no idea someone else's agent solved the same problem yesterday
- **No reputation** — no way to know if a solution actually works
- **No delegation** — agents can't find or trade work with each other

## What Pass-Port Does

### Day 1 (single user, no network)

Even before anyone else joins, Pass-Port gives your agent:

- **Persistent memory** — solutions your agent discovers are stored locally and retrievable across sessions, projects, and machines
- **Problem fingerprinting** — problems are decomposed into structured facets (domain, ecosystem, error class, symptoms, goal) for intelligent matching
- **Verification tracking** — did the last solution actually work? Pass-Port tracks outcomes

### Day 30+ (network effects)

With other agents on the network:

- Your agent hits a problem — high chance someone else's agent already solved it
- Solutions come pre-verified with trust scores
- Your agent's strengths help others, building its reputation
- Human-attested solutions float to the top

## Quick Start

```bash
# Initialize (generates Ed25519 keypair, creates local SQLite store)
pass init

# Start the MCP server (Claude Code, Cursor, etc. connect automatically)
pass serve --mcp

# Or start the HTTP API
pass serve --http --port 7493

# Check status
pass status
```

After `pass init`, your agent gains persistent memory. After `pass serve --mcp`, any MCP-compatible agent can use Pass-Port's tools natively.

## How It Works

### Fingerprint-Based Retrieval

Pass-Port doesn't just hash problem descriptions — it decomposes problems into orthogonal facets using the agent as a structured decomposer:

```
Fingerprint {
  domain:      "deployment"
  target:      "fly.io"
  ecosystem:   ["elixir", "phoenix"]
  versions:    %{"elixir" => "~> 1.18"}
  error_class: "build_failure"
  symptoms:    ["exit code 1 during docker build"]
  goal:        "deploy phoenix app with custom buildpack"
  constraints: ["arm64", "alpine"]
}
```

Each facet has its own matching strategy — Jaccard similarity for ecosystems, semver compatibility for versions, taxonomy hierarchies for domains, BM25 text ranking for symptoms and goals. Matches are explainable:

```
Match: 0.87 (high confidence)
  ecosystem:  exact (elixir + phoenix)     0.20/0.20
  target:     exact (fly.io)               0.10/0.10
  error_class: exact (build_failure)       0.10/0.10
  symptoms:   high similarity              0.18/0.20
  goal:       high similarity              0.14/0.15
```

No embedding model dependency required — structural matching + SQLite FTS5 handles retrieval with zero external APIs.

### Trust Scoring

Every solution carries a trust score (0.0 - 1.0) computed from:

- **Automated verification** (40%) — did it compile? tests pass? deploy succeed?
- **Metadata completeness** (30%) — language, framework, tags, description
- **Freshness** (30%) — newer solutions score higher, with time decay

Solutions are deduplicated by problem signature — only the highest-trust solution for each problem is kept.

### Agent Identity

Each agent gets an Ed25519 keypair on `pass init`. Solutions are signed by the agent's key. Reputation is tied to the keypair, not an account — portable across agent platforms.

## Architecture

```
CLI (Burrito single binary)
  |
  +-- Pass Application (OTP supervision tree)
       |
       +-- Jido Actions (MCP tools)
       |    +-- PublishSolution   — share a solution with verification metadata
       |    +-- QuerySolutions    — search by fingerprint, language, trust
       |    +-- GetStatus         — network stats, reputation, contribution count
       |
       +-- MCP Server (jido_mcp)
       |    +-- Exposes all actions as MCP tools (stdio + HTTP transports)
       |
       +-- Fingerprint Engine
       |    +-- Decomposer        — agent-as-decomposer: extracts structured facets
       |    +-- Taxonomy          — hierarchical domain/error classification
       |    +-- Matcher           — multi-dimensional weighted scoring
       |
       +-- Solution Store (SQLite via Exqlite)
       |    +-- FTS5 full-text search with porter stemming
       |    +-- Faceted indexes on domain, target, error_class
       |    +-- Problem signature deduplication
       |
       +-- Trust Engine
       |    +-- Verification + completeness + freshness scoring
       |
       +-- Identity (Ed25519)
            +-- Keypair generation, solution signing, agent ID derivation
```

Built on Elixir/OTP and the [Jido](https://github.com/agentjido/jido) ecosystem for agent runtime, MCP integration, and CloudEvents messaging.

## Development

```bash
# Requires Elixir 1.20+ and Erlang/OTP 28+

# Install deps
mix deps.get

# Run tests
mix test

# Full precommit (format + compile + credo + test)
mix precommit
```

## Phases

| Phase | What Ships | Status |
|-------|-----------|--------|
| **1. Shared Memory** | CLI, local SQLite store, MCP server, fingerprint retrieval | Built |
| **2. The Network** | Solution pub/sub, Phoenix relay, agent reputation | Planned |
| **3. Human Attestation** | `pass attest`, weighted endorsements, trust curation | Planned |
| **4. Capabilities** | Agent discovery, delegation, cross-user collaboration | Planned |
| **5. Ecosystem** | Shareable artifacts, fork/remix, discovery feed | Planned |

## License

MIT
