defmodule Pass.HTTP.RouterTest do
  use ExUnit.Case, async: false

  import Plug.Test
  import Plug.Conn

  alias Pass.HTTP.Router

  setup do
    db_path = Path.join(System.tmp_dir!(), "pass_http_test_#{:rand.uniform(1_000_000)}.db")
    {:ok, conn} = Exqlite.Sqlite3.open(db_path)
    alias Pass.Store.Migrations
    :ok = Migrations.run(conn)
    Exqlite.Sqlite3.close(conn)

    # Start store as Pass.Store (the default name actions use)
    start_supervised!({Pass.Store, db_path: db_path, name: Pass.Store})

    identity_path = Path.join(System.tmp_dir!(), "pass_http_id_#{:rand.uniform(1_000_000)}.json")
    keypair = Pass.Identity.generate_keypair()
    :ok = Pass.Identity.save_keypair(keypair, identity_path)

    on_exit(fn ->
      File.rm(db_path)
      File.rm(identity_path)
    end)

    %{identity_path: identity_path}
  end

  test "GET /health returns 200 ok" do
    conn = conn(:get, "/health") |> Router.call(Router.init([]))

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body) == %{"status" => "ok"}
  end

  test "GET /nonexistent returns 404" do
    conn = conn(:get, "/nonexistent") |> Router.call(Router.init([]))

    assert conn.status == 404
  end

  test "POST /api/query returns results" do
    conn =
      conn(:post, "/api/query", Jason.encode!(%{"goal" => "test query"}))
      |> put_req_header("content-type", "application/json")
      |> Router.call(Router.init([]))

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert is_map(body)
  end

  test "GET /api/status returns status" do
    conn = conn(:get, "/api/status") |> Router.call(Router.init([]))

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert Map.has_key?(body, "contributions")
  end
end
