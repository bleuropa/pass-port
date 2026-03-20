defmodule Pass.Store do
  @moduledoc """
  SQLite-backed solution store using Exqlite.

  Manages a local database of solutions at `~/.pass/solutions.db`.
  Supports insert (with dedup by problem_signature), query, get, delete, and stats.
  """

  use GenServer

  alias Pass.Solution
  alias Pass.Store.Migrations

  @columns ~w(id problem_signature problem_description solution_content language framework runtime tags verification trust_score agent_id signature sharing inserted_at updated_at)

  # Client API

  @doc """
  Starts the Store GenServer.

  Options:
    - `:db_path` — path to the SQLite database file (default: `~/.pass/solutions.db`)
    - `:name` — GenServer name (default: `Pass.Store`)
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Inserts a solution. Deduplicates by problem_signature — if a solution with the same
  problem_signature exists and the new one has a higher trust_score, it replaces it.
  """
  @spec insert(Solution.t(), GenServer.server()) :: :ok | {:error, term()}
  def insert(%Solution{} = solution, server \\ __MODULE__) do
    GenServer.call(server, {:insert, solution})
  end

  @doc """
  Queries solutions by keyword filters.

  Supported filters:
    - `:problem_signature` — exact match
    - `:language` — exact match
    - `:framework` — exact match
    - `:tags` — list of tags, matches if solution contains any
    - `:min_trust` — minimum trust_score (float)
  """
  @spec query(keyword(), GenServer.server()) :: {:ok, [Solution.t()]} | {:error, term()}
  def query(filters \\ [], server \\ __MODULE__) do
    GenServer.call(server, {:query, filters})
  end

  @doc "Gets a solution by ID."
  @spec get(String.t(), GenServer.server()) :: {:ok, Solution.t()} | {:error, :not_found}
  def get(id, server \\ __MODULE__) do
    GenServer.call(server, {:get, id})
  end

  @doc "Deletes a solution by ID."
  @spec delete(String.t(), GenServer.server()) :: :ok | {:error, term()}
  def delete(id, server \\ __MODULE__) do
    GenServer.call(server, {:delete, id})
  end

  @doc """
  Returns store statistics.

  Returns `%{total: integer, by_language: map, avg_trust: float}`.
  """
  @spec stats(GenServer.server()) :: {:ok, map()}
  def stats(server \\ __MODULE__) do
    GenServer.call(server, :stats)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    db_path = Keyword.get(opts, :db_path, default_db_path())
    ensure_dir(db_path)

    case Exqlite.Sqlite3.open(db_path) do
      {:ok, conn} ->
        :ok = Exqlite.Sqlite3.execute(conn, "PRAGMA journal_mode=WAL")
        :ok = Migrations.run(conn)
        {:ok, %{conn: conn, db_path: db_path}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:insert, %Solution{} = solution}, _from, state) do
    result = do_insert(state.conn, solution)
    {:reply, result, state}
  end

  def handle_call({:query, filters}, _from, state) do
    result = do_query(state.conn, filters)
    {:reply, result, state}
  end

  def handle_call({:get, id}, _from, state) do
    result = do_get(state.conn, id)
    {:reply, result, state}
  end

  def handle_call({:delete, id}, _from, state) do
    result = do_delete(state.conn, id)
    {:reply, result, state}
  end

  def handle_call(:stats, _from, state) do
    result = do_stats(state.conn)
    {:reply, result, state}
  end

  @impl true
  def terminate(_reason, state) do
    Exqlite.Sqlite3.close(state.conn)
  end

  # Private implementation

  defp do_insert(conn, %Solution{} = solution) do
    map = Solution.to_map(solution)

    existing = find_by_signature(conn, solution.problem_signature)

    if existing && existing.trust_score >= solution.trust_score do
      :ok
    else
      if existing, do: exec_delete(conn, existing.id)

      placeholders = Enum.map_join(1..length(@columns), ", ", fn i -> "?#{i}" end)
      sql = "INSERT INTO solutions (#{Enum.join(@columns, ", ")}) VALUES (#{placeholders})"
      values = Enum.map(@columns, fn col -> map[col] end)

      case exec_stmt(conn, sql, values) do
        :done -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp do_query(conn, filters) do
    {where_clauses, params} = build_where(filters)

    sql =
      if where_clauses == [] do
        "SELECT #{Enum.join(@columns, ", ")} FROM solutions ORDER BY trust_score DESC"
      else
        "SELECT #{Enum.join(@columns, ", ")} FROM solutions WHERE #{Enum.join(where_clauses, " AND ")} ORDER BY trust_score DESC"
      end

    {:ok, rows} = exec_select(conn, sql, params)
    {:ok, Enum.map(rows, &row_to_solution/1)}
  end

  defp do_get(conn, id) do
    sql = "SELECT #{Enum.join(@columns, ", ")} FROM solutions WHERE id = ?1"

    {:ok, rows} = exec_select(conn, sql, [id])

    case rows do
      [row | _] -> {:ok, row_to_solution(row)}
      [] -> {:error, :not_found}
    end
  end

  defp do_delete(conn, id) do
    exec_delete(conn, id)
  end

  defp do_stats(conn) do
    total = exec_scalar(conn, "SELECT COUNT(*) FROM solutions", []) || 0
    avg_trust = exec_scalar(conn, "SELECT AVG(trust_score) FROM solutions", []) || 0.0

    {:ok, lang_rows} =
      exec_select(conn, "SELECT language, COUNT(*) FROM solutions GROUP BY language", [])

    by_language = Map.new(lang_rows, fn [lang, count] -> {lang, count} end)

    {:ok, %{total: total, by_language: by_language, avg_trust: avg_trust / 1}}
  end

  defp find_by_signature(conn, problem_signature) do
    sql =
      "SELECT #{Enum.join(@columns, ", ")} FROM solutions WHERE problem_signature = ?1 LIMIT 1"

    case exec_select(conn, sql, [problem_signature]) do
      {:ok, [row | _]} -> row_to_solution(row)
      _ -> nil
    end
  end

  defp build_where(filters) do
    {clauses, params, _idx} =
      Enum.reduce(filters, {[], [], 1}, fn
        {:problem_signature, val}, {c, p, i} ->
          {c ++ ["problem_signature = ?#{i}"], p ++ [val], i + 1}

        {:language, val}, {c, p, i} ->
          {c ++ ["language = ?#{i}"], p ++ [val], i + 1}

        {:framework, val}, {c, p, i} ->
          {c ++ ["framework = ?#{i}"], p ++ [val], i + 1}

        {:min_trust, val}, {c, p, i} ->
          {c ++ ["trust_score >= ?#{i}"], p ++ [val], i + 1}

        {:tags, tags}, {c, p, i} when is_list(tags) ->
          tag_clauses =
            tags
            |> Enum.with_index(i)
            |> Enum.map(fn {_tag, idx} -> "tags LIKE ?#{idx}" end)

          tag_params = Enum.map(tags, fn tag -> "%#{tag}%" end)
          {c ++ ["(#{Enum.join(tag_clauses, " OR ")})"], p ++ tag_params, i + length(tags)}

        _, acc ->
          acc
      end)

    {clauses, params}
  end

  defp row_to_solution(row) do
    map = Enum.zip(@columns, row) |> Map.new()
    Solution.from_map(map)
  end

  defp exec_stmt(conn, sql, params) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)

    try do
      :ok = Exqlite.Sqlite3.bind(stmt, params)
      Exqlite.Sqlite3.step(conn, stmt)
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end

  defp exec_select(conn, sql, params) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)

    try do
      :ok = Exqlite.Sqlite3.bind(stmt, params)
      rows = collect_rows(conn, stmt, [])
      {:ok, rows}
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end

  defp collect_rows(conn, stmt, acc) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, row} -> collect_rows(conn, stmt, acc ++ [row])
      :done -> acc
    end
  end

  defp exec_scalar(conn, sql, params) do
    case exec_select(conn, sql, params) do
      {:ok, [[val]]} -> val
      _ -> nil
    end
  end

  defp exec_delete(conn, id) do
    case exec_stmt(conn, "DELETE FROM solutions WHERE id = ?1", [id]) do
      :done -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp default_db_path do
    Path.join([System.user_home!(), ".pass", "solutions.db"])
  end

  defp ensure_dir(path) do
    path |> Path.dirname() |> File.mkdir_p!()
  end
end
