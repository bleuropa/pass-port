defmodule Pass.Store do
  @moduledoc """
  SQLite-backed solution store using Exqlite.

  Manages a local database of solutions at `~/.pass/solutions.db`.
  Supports insert (with dedup by problem_signature), query, get, delete, and stats.
  Also supports fingerprint-aware search via FTS5 and faceted filtering.
  """

  use GenServer

  alias Pass.Fingerprint
  alias Pass.Solution
  alias Pass.Store.Migrations

  @base_columns ~w(id problem_signature problem_description solution_content language framework runtime tags verification trust_score agent_id signature sharing inserted_at updated_at)
  @fingerprint_columns ~w(domain target ecosystem version_constraints error_class constraints goal symptoms terms)
  @columns @base_columns ++ @fingerprint_columns

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

  Accepts an optional fingerprint as the second argument. If provided, the fingerprint
  facets are stored alongside the solution and indexed in FTS5.
  """
  @spec insert(Solution.t(), Fingerprint.t() | nil | GenServer.server()) :: :ok | {:error, term()}
  def insert(solution, fingerprint_or_server \\ nil)

  def insert(%Solution{} = solution, %Fingerprint{} = fingerprint) do
    GenServer.call(__MODULE__, {:insert, solution, fingerprint})
  end

  def insert(%Solution{} = solution, nil) do
    GenServer.call(__MODULE__, {:insert, solution, nil})
  end

  def insert(%Solution{} = solution, server)
      when is_atom(server) or is_pid(server) or is_tuple(server) do
    GenServer.call(server, {:insert, solution, nil})
  end

  @doc """
  Inserts a solution with an optional fingerprint to a specific server.
  """
  @spec insert(Solution.t(), Fingerprint.t() | nil, GenServer.server()) :: :ok | {:error, term()}
  def insert(%Solution{} = solution, fingerprint, server) do
    GenServer.call(server, {:insert, solution, fingerprint})
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

  Returns `%{total: integer, by_language: map, avg_trust: float, fingerprinted: integer}`.
  """
  @spec stats(GenServer.server()) :: {:ok, map()}
  def stats(server \\ __MODULE__) do
    GenServer.call(server, :stats)
  end

  @doc """
  Searches for solutions by fingerprint facets.

  Filters on structural facets (domain, target, error_class) where they are non-nil
  in the given fingerprint map. Returns `{solution, fingerprint_map}` tuples.

  Options:
    - `:limit` — max results (default 50)
    - `:min_trust` — minimum trust_score filter
  """
  @spec search(map(), keyword(), GenServer.server()) :: {:ok, [{Solution.t(), map()}]}
  def search(fingerprint_map, opts \\ [], server \\ __MODULE__)

  def search(fingerprint_map, opts, server) when is_map(fingerprint_map) do
    GenServer.call(server, {:search, fingerprint_map, opts})
  end

  @doc """
  Full-text search using FTS5 with BM25 ranking.

  Returns solutions ranked by text relevance to the query.

  Options:
    - `:limit` — max results (default 20)
  """
  @spec fts_search(String.t(), keyword(), GenServer.server()) :: {:ok, [Solution.t()]}
  def fts_search(query_text, opts \\ [], server \\ __MODULE__)

  def fts_search(query_text, opts, server) when is_binary(query_text) do
    GenServer.call(server, {:fts_search, query_text, opts})
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
  def handle_call({:insert, %Solution{} = solution, fingerprint}, _from, state) do
    result = do_insert(state.conn, solution, fingerprint)
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

  def handle_call({:search, fingerprint_map, opts}, _from, state) do
    result = do_search(state.conn, fingerprint_map, opts)
    {:reply, result, state}
  end

  def handle_call({:fts_search, query_text, opts}, _from, state) do
    result = do_fts_search(state.conn, query_text, opts)
    {:reply, result, state}
  end

  @impl true
  def terminate(_reason, state) do
    Exqlite.Sqlite3.close(state.conn)
  end

  # Private implementation

  defp do_insert(conn, %Solution{} = solution, fingerprint) do
    map = Solution.to_map(solution)

    fp_map =
      if fingerprint do
        Fingerprint.to_map(fingerprint)
      else
        %{}
      end

    merged = Map.merge(map, fp_map)

    existing = find_by_signature(conn, solution.problem_signature)

    if existing && existing.trust_score >= solution.trust_score do
      :ok
    else
      if existing, do: exec_delete(conn, existing.id)

      placeholders = Enum.map_join(1..length(@columns), ", ", fn i -> "?#{i}" end)
      sql = "INSERT INTO solutions (#{Enum.join(@columns, ", ")}) VALUES (#{placeholders})"
      values = Enum.map(@columns, fn col -> merged[col] end)

      case exec_stmt(conn, sql, values) do
        :done ->
          insert_fts(conn, merged)
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp insert_fts(conn, merged) do
    goal = merged["goal"]
    symptoms = merged["symptoms"]
    description = merged["problem_description"]
    tags = merged["tags"]

    if goal || symptoms || description || tags do
      sql =
        "INSERT INTO solutions_fts (rowid, goal, symptoms, problem_description, tags) VALUES (?1, ?2, ?3, ?4, ?5)"

      rowid = get_rowid(conn, merged["id"])

      if rowid do
        symptoms_text = decode_for_fts(symptoms)
        tags_text = decode_for_fts(tags)

        exec_stmt(conn, sql, [rowid, goal || "", symptoms_text, description || "", tags_text])
      end
    end
  end

  defp get_rowid(conn, id) do
    case exec_select(conn, "SELECT rowid FROM solutions WHERE id = ?1", [id]) do
      {:ok, [[rowid]]} -> rowid
      _ -> nil
    end
  end

  defp decode_for_fts(val) when is_binary(val) do
    case Jason.decode(val) do
      {:ok, list} when is_list(list) -> Enum.join(list, " ")
      _ -> val
    end
  end

  defp decode_for_fts(nil), do: ""

  defp delete_fts(conn, id) do
    rowid = get_rowid(conn, id)

    if rowid do
      exec_stmt(
        conn,
        "INSERT INTO solutions_fts (solutions_fts, rowid, goal, symptoms, problem_description, tags) VALUES ('delete', ?1, ?2, ?3, ?4, ?5)",
        [rowid, "", "", "", ""]
      )
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

    case exec_select(conn, sql, params) do
      {:ok, rows} -> {:ok, Enum.map(rows, &row_to_solution/1)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_get(conn, id) do
    sql = "SELECT #{Enum.join(@columns, ", ")} FROM solutions WHERE id = ?1"

    case exec_select(conn, sql, [id]) do
      {:ok, [row | _]} -> {:ok, row_to_solution(row)}
      {:ok, []} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_delete(conn, id) do
    delete_fts(conn, id)
    exec_delete(conn, id)
  end

  defp do_stats(conn) do
    total = exec_scalar(conn, "SELECT COUNT(*) FROM solutions", []) || 0
    avg_trust = exec_scalar(conn, "SELECT AVG(trust_score) FROM solutions", []) || 0.0

    by_language =
      case exec_select(conn, "SELECT language, COUNT(*) FROM solutions GROUP BY language", []) do
        {:ok, rows} -> Map.new(rows, fn [lang, count] -> {lang, count} end)
        {:error, _} -> %{}
      end

    fingerprinted =
      exec_scalar(
        conn,
        "SELECT COUNT(*) FROM solutions WHERE domain IS NOT NULL OR goal IS NOT NULL",
        []
      ) || 0

    {:ok,
     %{
       total: total,
       by_language: by_language,
       avg_trust: avg_trust,
       fingerprinted: fingerprinted
     }}
  end

  defp do_search(conn, fingerprint_map, opts) do
    limit = Keyword.get(opts, :limit, 50)
    min_trust = Keyword.get(opts, :min_trust, nil)

    {where_clauses, params, idx} = build_search_where(fingerprint_map, min_trust)

    where_sql =
      if where_clauses == [] do
        ""
      else
        " WHERE " <> Enum.join(where_clauses, " AND ")
      end

    sql =
      "SELECT #{Enum.join(@columns, ", ")} FROM solutions#{where_sql} ORDER BY trust_score DESC LIMIT ?#{idx}"

    case exec_select(conn, sql, params ++ [limit]) do
      {:ok, rows} ->
        results =
          Enum.map(rows, fn row ->
            solution = row_to_solution(row)
            fp_map = row_to_fingerprint_map(row)
            {solution, fp_map}
          end)

        {:ok, results}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_search_where(fingerprint_map, min_trust) do
    facets = [
      {"domain", Map.get(fingerprint_map, :domain) || Map.get(fingerprint_map, "domain")},
      {"target", Map.get(fingerprint_map, :target) || Map.get(fingerprint_map, "target")},
      {"error_class",
       Map.get(fingerprint_map, :error_class) || Map.get(fingerprint_map, "error_class")}
    ]

    {clauses, params, idx} =
      Enum.reduce(facets, {[], [], 1}, fn
        {col, val}, {c, p, i} when is_binary(val) and val != "" ->
          {c ++ ["#{col} = ?#{i}"], p ++ [val], i + 1}

        _, acc ->
          acc
      end)

    {clauses, params, idx} =
      if min_trust do
        {clauses ++ ["trust_score >= ?#{idx}"], params ++ [min_trust], idx + 1}
      else
        {clauses, params, idx}
      end

    {clauses, params, idx}
  end

  defp row_to_fingerprint_map(row) do
    col_map = Enum.zip(@columns, row) |> Map.new()

    %{
      "domain" => col_map["domain"],
      "target" => col_map["target"],
      "ecosystem" => col_map["ecosystem"],
      "version_constraints" => col_map["version_constraints"],
      "error_class" => col_map["error_class"],
      "constraints" => col_map["constraints"],
      "goal" => col_map["goal"],
      "symptoms" => col_map["symptoms"],
      "terms" => col_map["terms"]
    }
  end

  defp do_fts_search(conn, query_text, opts) do
    limit = Keyword.get(opts, :limit, 20)
    sanitized = sanitize_fts_query(query_text)

    if sanitized == "" do
      {:ok, []}
    else
      fts_sql = """
      SELECT s.#{Enum.join(@columns, ", s.")}
      FROM solutions_fts fts
      JOIN solutions s ON s.rowid = fts.rowid
      WHERE solutions_fts MATCH ?1
      ORDER BY rank
      LIMIT ?2
      """

      case exec_select(conn, fts_sql, [sanitized, limit]) do
        {:ok, rows} -> {:ok, Enum.map(rows, &row_to_solution/1)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp sanitize_fts_query(text) do
    text
    |> String.replace(~r/["\*\-\(\)\:\^]/, " ")
    |> String.replace(~r/\b(AND|OR|NOT|NEAR)\b/i, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
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

      case collect_rows(conn, stmt, []) do
        {:error, reason} -> {:error, reason}
        rows -> {:ok, rows}
      end
    after
      Exqlite.Sqlite3.release(conn, stmt)
    end
  end

  defp collect_rows(conn, stmt, acc) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, row} -> collect_rows(conn, stmt, [row | acc])
      :done -> Enum.reverse(acc)
      {:error, reason} -> {:error, reason}
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
