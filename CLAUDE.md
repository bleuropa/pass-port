# Pass — Agent-to-Agent Network

## What is Pass?

Pass is a CLI and protocol that connects AI coding agents across users — sharing verified solutions, discovering capabilities, and collaborating on behalf of their humans. Built on the Jido ecosystem for Elixir.

*Product spec: ~/projects/loom/docs/product-weft.md* (originally called "Weft", renamed to "Pass")

## Build Commands

```bash
# Set up PATH for correct Erlang/Elixir
export PATH="/Users/brandonleuropa/.local/share/mise/installs/erlang/28.4/bin:/Users/brandonleuropa/.local/share/mise/installs/elixir/1.20.0-rc.3-otp-28/bin:$PATH"

# Install deps
mix deps.get

# Compile
mix compile 2>&1 | tee /tmp/pass_compile.log

# Test
mix test 2>&1 | tee /tmp/pass_test.log

# Precommit
mix precommit 2>&1 | tee /tmp/pass_precommit.log

# Format
mix format
```

## Important

- **Never run slow commands** without piping to a log file (see above)
- Commit subjects must be **fully lowercase**
- Run `mix format` before committing

## Architecture (Phase 1 — MVP)

```
lib/pass/
├── application.ex          # OTP supervision tree
├── cli.ex                  # CLI entry point (init, serve, status)
├── identity.ex             # Ed25519 keypair generation & signing
├── store.ex                # SQLite solution store (Exqlite)
├── store/
│   └── migrations.ex       # SQLite schema setup
├── solution.ex             # Solution struct & problem signature hashing
├── trust.ex                # Trust scoring engine
├── actions/                # Jido actions (MCP tools)
│   ├── publish_solution.ex
│   ├── query_solutions.ex
│   └── get_status.ex
└── mcp/
    └── server.ex           # MCP server via jido_mcp
```

## Key Dependencies

- `jido` / `jido_action` / `jido_signal` / `jido_mcp` — Agent runtime & MCP integration
- `exqlite` — SQLite (zero config, ships with binary)
- `ed25519` — Agent identity keypairs
- `burrito` — Single binary packaging
- `owl` — CLI rendering

## Phase 1 Scope

- CLI: `pass init`, `pass serve --mcp`, `pass serve --http`, `pass status`
- Local SQLite solution store with problem signature hashing & dedup
- Ed25519 keypair identity generated on `pass init`
- MCP server exposing actions as tools
- Basic trust scoring (automated verification only)
- Single-user value: persistent agent memory across sessions
