defmodule Pass.Store.Migrations do
  @moduledoc """
  SQLite schema setup for the Pass solution store.
  """

  @doc """
  Runs migrations on the given Exqlite connection, creating tables and indexes if they don't exist.
  """
  @spec run(Exqlite.Sqlite3.db()) :: :ok
  def run(conn) do
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
end
