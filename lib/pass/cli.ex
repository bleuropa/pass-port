defmodule Pass.CLI do
  @moduledoc """
  CLI entry point for the Pass agent network.

  Commands:
    - `pass init` — initialize agent identity and local store
    - `pass serve --mcp` — start MCP server (stdio transport)
    - `pass serve --http` — start HTTP API server
    - `pass status` — show agent status
    - `pass connect` — connect to relay server
    - `pass disconnect` — disconnect from relay
    - `pass config` — show current configuration
    - `pass config set <key> <value>` — update a config value
  """

  alias Pass.Config
  alias Pass.Identity
  alias Pass.Store.Migrations

  @doc """
  Main entry point for CLI argument parsing and dispatch.
  """
  def main(args) do
    dispatch(args)
  end

  defp dispatch(["init" | _rest]), do: cmd_init()
  defp dispatch(["serve" | rest]), do: cmd_serve(rest)
  defp dispatch(["status" | _rest]), do: cmd_status()
  defp dispatch(["connect" | rest]), do: cmd_connect(rest)
  defp dispatch(["disconnect" | _rest]), do: cmd_disconnect()
  defp dispatch(["config", "set", key, value | _rest]), do: cmd_config_set(key, value)
  defp dispatch(["config" | _rest]), do: cmd_config()
  defp dispatch(["help" | _rest]), do: cmd_help()
  defp dispatch([]), do: cmd_help()
  defp dispatch(args), do: cmd_unknown(args)

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
        network_lines = network_status_lines()

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
          | network_lines
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
      "  pass connect            Connect to relay server\n",
      "  pass connect --url URL  Connect to a specific relay\n",
      "  pass disconnect         Disconnect from relay\n",
      "  pass config             Show current configuration\n",
      "  pass config set K V     Update a config value\n",
      "  pass help              Show this help message"
    ])
  end

  @doc false
  def cmd_connect(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [url: :string],
        aliases: [u: :url]
      )

    config = Config.load()
    url = Keyword.get(opts, :url, config["relay_url"])

    identity_path = Identity.default_identity_path()

    case Identity.load_keypair(identity_path) do
      {:ok, keys} ->
        agent_id = Identity.agent_id(keys.public_key)
        Owl.IO.puts(Owl.Data.tag("Connecting to #{url}...", :cyan))

        connect_opts = [agent_id: agent_id, identity: keys, url: url]

        case Pass.Network.connect(connect_opts) do
          :ok ->
            Owl.IO.puts(Owl.Data.tag("Connected!", :green))

          {:error, reason} ->
            Owl.IO.puts(Owl.Data.tag("Connection failed: #{inspect(reason)}", :red))
        end

      {:error, _} ->
        Owl.IO.puts([
          Owl.Data.tag("Agent not initialized.", :yellow),
          "\n  Run ",
          Owl.Data.tag("pass init", :cyan),
          " first."
        ])
    end
  end

  @doc false
  def cmd_disconnect do
    Pass.Network.disconnect()
    Owl.IO.puts(Owl.Data.tag("Disconnected from relay.", :yellow))
  end

  @doc false
  def cmd_config(opts \\ []) do
    path = Keyword.get(opts, :config_path, nil)
    config = if path, do: Config.load(path), else: Config.load()

    Owl.IO.puts(Owl.Data.tag("Pass Configuration\n", :cyan))

    Enum.each(Enum.sort(config), fn {key, value} ->
      Owl.IO.puts([
        Owl.Data.tag("  #{key}: ", :cyan),
        format_value(value)
      ])
    end)

    :ok
  end

  @doc false
  def cmd_config_set(key, value, opts \\ []) do
    path = Keyword.get(opts, :config_path, nil)
    parsed_value = parse_config_value(key, value)

    if path do
      Config.set(key, parsed_value, path)
    else
      Config.set(key, parsed_value)
    end

    Owl.IO.puts([
      Owl.Data.tag("Set ", :green),
      Owl.Data.tag(key, :cyan),
      Owl.Data.tag(" = ", :green),
      format_value(parsed_value)
    ])

    :ok
  end

  defp parse_config_value("auto_connect", val) when val in ["true", "1", "yes"], do: true
  defp parse_config_value("auto_connect", _val), do: false

  defp parse_config_value("min_trust_from_network", val) do
    case Float.parse(val) do
      {float, _} when float >= 0.0 and float <= 1.0 -> float
      {float, _} -> min(max(float, 0.0), 1.0)
      :error -> 0.3
    end
  end

  defp parse_config_value("subscribe_languages", val) do
    val |> String.split(",") |> Enum.map(&String.trim/1)
  end

  defp parse_config_value(_key, val), do: val

  defp format_value(val) when is_list(val), do: inspect(val)
  defp format_value(val) when is_boolean(val), do: to_string(val)
  defp format_value(val) when is_float(val), do: to_string(val)
  defp format_value(val), do: to_string(val)

  defp network_status_lines do
    net_status = Pass.Network.status()

    case net_status.status do
      :connected ->
        channels = Enum.join(net_status.channels, ", ")

        [
          "\n",
          Owl.Data.tag("  Network:     ", :cyan),
          Owl.Data.tag("connected", :green),
          "\n",
          Owl.Data.tag("  Channels:    ", :cyan),
          channels
        ]

      _ ->
        [
          "\n",
          Owl.Data.tag("  Network:     ", :cyan),
          Owl.Data.tag("disconnected", :yellow)
        ]
    end
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
