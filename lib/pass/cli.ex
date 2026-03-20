defmodule Pass.CLI do
  @moduledoc """
  CLI entry point for the Pass agent network.

  Commands:
    - `pass init` — initialize agent identity and local store
    - `pass serve --mcp` — start MCP server (stdio transport)
    - `pass serve --http` — start HTTP API server
    - `pass status` — show agent status
  """

  alias Pass.Identity
  alias Pass.Store.Migrations

  @doc """
  Main entry point for CLI argument parsing and dispatch.
  """
  def main(args) do
    case args do
      ["init" | _rest] -> cmd_init()
      ["serve" | rest] -> cmd_serve(rest)
      ["status" | _rest] -> cmd_status()
      ["help" | _rest] -> cmd_help()
      [] -> cmd_help()
      _ -> cmd_unknown(args)
    end
  end

  @doc false
  def cmd_init(opts \\ []) do
    pass_dir = Keyword.get(opts, :pass_dir, Path.expand("~/.pass"))
    identity_path = Path.join(pass_dir, "identity.json")
    db_path = Path.join(pass_dir, "solutions.db")

    File.mkdir_p!(pass_dir)

    if File.exists?(identity_path) do
      Owl.IO.puts(Owl.Data.tag("Identity already exists at #{identity_path}", :yellow))
    else
      keypair = Identity.generate_keypair()
      :ok = Identity.save_keypair(keypair, identity_path)
      agent_id = Identity.agent_id(elem(keypair, 0))

      Owl.IO.puts([
        Owl.Data.tag("Pass initialized!\n", :green),
        Owl.Data.tag("  Agent ID: ", :cyan),
        agent_id,
        "\n",
        Owl.Data.tag("  Identity: ", :cyan),
        identity_path,
        "\n",
        Owl.Data.tag("  Store:    ", :cyan),
        db_path
      ])
    end

    # Ensure the store DB is created
    {:ok, conn} = Exqlite.Sqlite3.open(db_path)
    :ok = Migrations.run(conn)
    Exqlite.Sqlite3.close(conn)

    :ok
  end

  @doc false
  def cmd_serve(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [mcp: :boolean, http: :boolean, port: :integer],
        aliases: [p: :port]
      )

    cond do
      Keyword.get(opts, :mcp, false) ->
        Owl.IO.puts(Owl.Data.tag("Starting Pass MCP server (stdio)...", :cyan))
        start_app(:mcp)

      Keyword.get(opts, :http, false) ->
        port = Keyword.get(opts, :port, 7493)
        Owl.IO.puts(Owl.Data.tag("Starting Pass HTTP server on port #{port}...", :cyan))
        start_app({:http, port})

      true ->
        Owl.IO.puts(Owl.Data.tag("Please specify --mcp or --http", :red))
        cmd_help()
    end
  end

  @doc false
  def cmd_status(opts \\ []) do
    identity_path = Keyword.get(opts, :identity_path, Identity.default_identity_path())

    agent_info =
      case Identity.load_keypair(identity_path) do
        {:ok, keys} -> {:ok, Identity.agent_id(keys.public_key)}
        {:error, _} -> :not_initialized
      end

    case agent_info do
      {:ok, agent_id} ->
        Owl.IO.puts([
          Owl.Data.tag("Pass Agent Status\n", :cyan),
          Owl.Data.tag("  Agent ID:    ", :cyan),
          agent_id,
          "\n",
          Owl.Data.tag("  Identity:    ", :cyan),
          identity_path,
          "\n",
          Owl.Data.tag("  Initialized: ", :cyan),
          Owl.Data.tag("yes", :green)
        ])

      :not_initialized ->
        Owl.IO.puts([
          Owl.Data.tag("Pass agent not initialized.", :yellow),
          "\n  Run ",
          Owl.Data.tag("pass init", :cyan),
          " to get started."
        ])
    end
  end

  @doc false
  def cmd_help do
    Owl.IO.puts([
      Owl.Data.tag("Pass", :cyan),
      " — agent-to-agent solution network\n\n",
      Owl.Data.tag("Commands:\n", :cyan),
      "  pass init              Initialize agent identity and local store\n",
      "  pass serve --mcp       Start MCP server (stdio transport)\n",
      "  pass serve --http      Start HTTP API server (default port 7493)\n",
      "  pass status            Show agent status\n",
      "  pass help              Show this help message"
    ])
  end

  defp cmd_unknown(args) do
    Owl.IO.puts(Owl.Data.tag("Unknown command: #{Enum.join(args, " ")}", :red))
    cmd_help()
  end

  defp start_app(mode) do
    Application.put_env(:pass, :serve_mode, mode)
    Application.ensure_all_started(:pass)
    Process.sleep(:infinity)
  end
end
