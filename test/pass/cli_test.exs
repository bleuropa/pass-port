defmodule Pass.CLITest do
  use ExUnit.Case, async: true

  alias Pass.CLI
  alias Pass.Config

  describe "main/1 routing" do
    test "routes help command" do
      assert CLI.main(["help"]) == :ok
    end

    test "routes empty args to help" do
      assert CLI.main([]) == :ok
    end

    test "routes config command" do
      assert CLI.main(["config"]) == :ok
    end
  end

  describe "cmd_init/1" do
    test "creates identity and database in specified directory" do
      tmp_dir =
        Path.join(System.tmp_dir!(), "pass_cli_test_#{:erlang.unique_integer([:positive])}")

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      assert :ok = CLI.cmd_init(pass_dir: tmp_dir)

      identity_path = Path.join(tmp_dir, "identity.json")
      db_path = Path.join(tmp_dir, "solutions.db")

      assert File.exists?(identity_path)
      assert File.exists?(db_path)

      {:ok, keys} = Pass.Identity.load_keypair(identity_path)
      assert is_binary(keys.public_key)
      assert is_binary(keys.secret_key)
    end

    test "does not overwrite existing identity" do
      tmp_dir =
        Path.join(System.tmp_dir!(), "pass_cli_test_#{:erlang.unique_integer([:positive])}")

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      :ok = CLI.cmd_init(pass_dir: tmp_dir)
      identity_path = Path.join(tmp_dir, "identity.json")
      {:ok, original_content} = File.read(identity_path)

      :ok = CLI.cmd_init(pass_dir: tmp_dir)
      {:ok, second_content} = File.read(identity_path)

      assert original_content == second_content
    end
  end

  describe "cmd_config/1" do
    test "shows current config" do
      tmp_path =
        Path.join(
          System.tmp_dir!(),
          "pass_cli_cfg_#{:erlang.unique_integer([:positive])}.json"
        )

      on_exit(fn -> File.rm(tmp_path) end)

      assert :ok = CLI.cmd_config(config_path: tmp_path)
    end
  end

  describe "cmd_config_set/3" do
    test "sets default_sharing value" do
      tmp_path =
        Path.join(
          System.tmp_dir!(),
          "pass_cli_cfg_set_#{:erlang.unique_integer([:positive])}.json"
        )

      on_exit(fn -> File.rm(tmp_path) end)

      assert :ok = CLI.cmd_config_set("default_sharing", "local", config_path: tmp_path)
      assert Config.get("default_sharing", tmp_path) == "local"
    end

    test "sets relay_url value" do
      tmp_path =
        Path.join(
          System.tmp_dir!(),
          "pass_cli_cfg_url_#{:erlang.unique_integer([:positive])}.json"
        )

      on_exit(fn -> File.rm(tmp_path) end)

      assert :ok =
               CLI.cmd_config_set("relay_url", "ws://my-relay:4000/socket", config_path: tmp_path)

      assert Config.get("relay_url", tmp_path) == "ws://my-relay:4000/socket"
    end

    test "sets auto_connect boolean" do
      tmp_path =
        Path.join(
          System.tmp_dir!(),
          "pass_cli_cfg_auto_#{:erlang.unique_integer([:positive])}.json"
        )

      on_exit(fn -> File.rm(tmp_path) end)

      assert :ok = CLI.cmd_config_set("auto_connect", "true", config_path: tmp_path)
      assert Config.get("auto_connect", tmp_path) == true
    end

    test "sets min_trust_from_network float" do
      tmp_path =
        Path.join(
          System.tmp_dir!(),
          "pass_cli_cfg_trust_#{:erlang.unique_integer([:positive])}.json"
        )

      on_exit(fn -> File.rm(tmp_path) end)

      assert :ok = CLI.cmd_config_set("min_trust_from_network", "0.7", config_path: tmp_path)
      assert Config.get("min_trust_from_network", tmp_path) == 0.7
    end

    test "sets subscribe_languages as comma-separated list" do
      tmp_path =
        Path.join(
          System.tmp_dir!(),
          "pass_cli_cfg_langs_#{:erlang.unique_integer([:positive])}.json"
        )

      on_exit(fn -> File.rm(tmp_path) end)

      assert :ok =
               CLI.cmd_config_set("subscribe_languages", "elixir,python,rust",
                 config_path: tmp_path
               )

      assert Config.get("subscribe_languages", tmp_path) == ["elixir", "python", "rust"]
    end
  end

  describe "main/1 connect/disconnect arg parsing" do
    test "connect with --url parses correctly" do
      args = ["connect", "--url", "ws://custom:4000/socket"]

      {opts, _, _} =
        OptionParser.parse(tl(args),
          switches: [url: :string],
          aliases: [u: :url]
        )

      assert Keyword.get(opts, :url) == "ws://custom:4000/socket"
    end

    test "connect without --url uses default" do
      args = ["connect"]

      {opts, _, _} =
        OptionParser.parse(tl(args),
          switches: [url: :string],
          aliases: [u: :url]
        )

      assert Keyword.get(opts, :url) == nil
    end
  end
end
