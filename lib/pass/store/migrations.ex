defmodule Pass.Store.Migrations do
  @moduledoc """
  Versioned SQLite schema migrations for the Pass solution store.

  Uses a `schema_version` table to track which migrations have been applied.
  Each version is run only once, and new databases get all migrations in order.
  """

  @current_version 3

  @doc """
  Runs all pending migrations on the given Exqlite connection.

  Checks the current schema version and applies any newer migrations.
  """
  @spec run(Exqlite.Sqlite3.db()) :: :ok
  def run(conn) do
    ensure_version_table(conn)
    current = get_version(conn)

    if current < 1, do: migrate_v1(conn)
    if current < 2, do: migrate_v2(conn)
    if current < 3, do: migrate_v3(conn)

    set_version(conn, @current_version)
    :ok
  end

  defp ensure_version_table(conn) do
    :ok =
      Exqlite.Sqlite3.execute(conn, """
      CREATE TABLE IF NOT EXISTS schema_version (
        version INTEGER PRIMARY KEY
      )
      """)
  end

  defp get_version(conn) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT MAX(version) FROM schema_version")

    try do
      case Exqlite.Sqlite3.step(conn, stmt) do
        {:row, [nil]} -> 0
        {:row, [v]} -> v
        :done -> 0
      end
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end

  defp set_version(conn, version) do
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(conn, "INSERT OR REPLACE INTO schema_version (version) VALUES (?1)")

    :ok = Exqlite.Sqlite3.bind(stmt, [version])
    :done = Exqlite.Sqlite3.step(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)
  end

  # v1: Original schema — solutions table + basic indexes
  defp migrate_v1(conn) do
    :ok =
      Exqlite.Sqlite3.execute(conn, """
      CREATE TABLE IF NOT EXISTS solutions (
        id TEXT PRIMARY KEY,
        problem_signature TEXT NOT NULL,
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
      )
      """)

    :ok =
      Exqlite.Sqlite3.execute(
        conn,
        "CREATE INDEX IF NOT EXISTS idx_solutions_problem_signature ON solutions(problem_signature)"
      )

    :ok =
      Exqlite.Sqlite3.execute(
        conn,
        "CREATE INDEX IF NOT EXISTS idx_solutions_language ON solutions(language)"
      )

    :ok =
      Exqlite.Sqlite3.execute(
        conn,
        "CREATE INDEX IF NOT EXISTS idx_solutions_trust_score ON solutions(trust_score)"
      )
  end

  # v3: Agents table for reputation tracking
  defp migrate_v3(conn) do
    :ok =
      Exqlite.Sqlite3.execute(conn, """
      CREATE TABLE IF NOT EXISTS agents (
        agent_id TEXT PRIMARY KEY,
        public_key TEXT,
        reputation REAL DEFAULT 0.5,
        solutions_contributed INTEGER DEFAULT 0,
        solutions_consumed INTEGER DEFAULT 0,
        successful_consumptions INTEGER DEFAULT 0,
        first_seen TEXT NOT NULL,
        last_seen TEXT NOT NULL
      )
      """)
  end

  # v2: Fingerprint columns + FTS5 + facet indexes
  defp migrate_v2(conn) do
    columns = [
      "domain TEXT",
      "target TEXT",
      "ecosystem TEXT",
      "version_constraints TEXT",
      "error_class TEXT",
      "constraints TEXT",
      "goal TEXT",
      "symptoms TEXT",
      "terms TEXT"
    ]

    for col <- columns do
      :ok = Exqlite.Sqlite3.execute(conn, "ALTER TABLE solutions ADD COLUMN #{col}")
    end

    :ok =
      Exqlite.Sqlite3.execute(conn, """
      CREATE VIRTUAL TABLE IF NOT EXISTS solutions_fts USING fts5(
        goal,
        symptoms,
        problem_description,
        tags,
        content='',
        tokenize='porter unicode61'
      )
      """)

    :ok =
      Exqlite.Sqlite3.execute(
        conn,
        "CREATE INDEX IF NOT EXISTS idx_solutions_domain ON solutions(domain)"
      )

    :ok =
      Exqlite.Sqlite3.execute(
        conn,
        "CREATE INDEX IF NOT EXISTS idx_solutions_target ON solutions(target)"
      )

    :ok =
      Exqlite.Sqlite3.execute(
        conn,
        "CREATE INDEX IF NOT EXISTS idx_solutions_error_class ON solutions(error_class)"
      )

    :ok =
      Exqlite.Sqlite3.execute(
        conn,
        "CREATE INDEX IF NOT EXISTS idx_solutions_ecosystem ON solutions(ecosystem)"
      )
  end
end
