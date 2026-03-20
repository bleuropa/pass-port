defmodule Pass.ConfigTest do
  use ExUnit.Case, async: true

  alias Pass.Config

  setup do
    tmp_dir = System.tmp_dir!()

    config_path =
      Path.join(tmp_dir, "pass_config_test_#{:erlang.unique_integer([:positive])}.json")

    on_exit(fn -> File.rm(config_path) end)

    %{config_path: config_path}
  end

  describe "default_config/0" do
    test "returns expected defaults" do
      defaults = Config.default_config()
      assert defaults["default_sharing"] == "attributed"
      assert defaults["relay_url"] == "ws://relay.pass-port.dev/socket/agent/websocket"
      assert defaults["auto_connect"] == false
      assert defaults["subscribe_languages"] == ["elixir"]
      assert defaults["min_trust_from_network"] == 0.3
    end
  end

  describe "load/1" do
    test "returns defaults when file does not exist", %{config_path: config_path} do
      config = Config.load(config_path)
      assert config == Config.default_config()
    end

    test "returns defaults when file contains invalid JSON", %{config_path: config_path} do
      File.write!(config_path, "not json")
      config = Config.load(config_path)
      assert config == Config.default_config()
    end

    test "merges saved config with defaults for missing keys", %{config_path: config_path} do
      partial = %{"default_sharing" => "local"}
      File.write!(config_path, Jason.encode!(partial))

      config = Config.load(config_path)
      assert config["default_sharing"] == "local"
      assert config["relay_url"] == "ws://relay.pass-port.dev/socket/agent/websocket"
      assert config["auto_connect"] == false
    end
  end

  describe "save/2 and load/1 round-trip" do
    test "saves and loads config correctly", %{config_path: config_path} do
      config = %{
        "default_sharing" => "local",
        "relay_url" => "ws://custom:4000/socket",
        "auto_connect" => true,
        "subscribe_languages" => ["elixir", "python"],
        "min_trust_from_network" => 0.5
      }

      assert :ok = Config.save(config, config_path)
      loaded = Config.load(config_path)

      assert loaded["default_sharing"] == "local"
      assert loaded["relay_url"] == "ws://custom:4000/socket"
      assert loaded["auto_connect"] == true
      assert loaded["subscribe_languages"] == ["elixir", "python"]
      assert loaded["min_trust_from_network"] == 0.5
    end
  end

  describe "get/2" do
    test "gets a single key with defaults", %{config_path: config_path} do
      assert Config.get("default_sharing", config_path) == "attributed"
    end

    test "gets a saved key", %{config_path: config_path} do
      Config.save(%{"default_sharing" => "local"}, config_path)
      assert Config.get("default_sharing", config_path) == "local"
    end
  end

  describe "set/3" do
    test "sets a key and persists it", %{config_path: config_path} do
      Config.set("default_sharing", "local", config_path)
      assert Config.get("default_sharing", config_path) == "local"

      # Other defaults still present
      assert Config.get("auto_connect", config_path) == false
    end

    test "overwrites existing key", %{config_path: config_path} do
      Config.set("relay_url", "ws://first:4000/socket", config_path)
      Config.set("relay_url", "ws://second:4000/socket", config_path)
      assert Config.get("relay_url", config_path) == "ws://second:4000/socket"
    end
  end
end
