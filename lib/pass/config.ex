defmodule Pass.Config do
  @moduledoc """
  Reads and writes the Pass configuration file at `~/.pass/config.json`.
  """

  @config_path Path.expand("~/.pass/config.json")

  @defaults %{
    "default_sharing" => "attributed",
    "relay_url" => "ws://relay.pass-port.dev/socket/agent/websocket",
    "auto_connect" => false,
    "subscribe_languages" => ["elixir"],
    "min_trust_from_network" => 0.3
  }

  @doc "Returns the default configuration map."
  def default_config, do: @defaults

  @doc "Loads config from disk, merging with defaults for missing keys."
  @spec load(String.t()) :: map()
  def load(path \\ @config_path) do
    case File.read(path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, config} when is_map(config) -> Map.merge(@defaults, config)
          _ -> @defaults
        end

      {:error, _} ->
        @defaults
    end
  end

  @doc "Saves a config map to disk as JSON."
  @spec save(map(), String.t()) :: :ok | {:error, term()}
  def save(config, path \\ @config_path) do
    path |> Path.dirname() |> File.mkdir_p!()
    json = Jason.encode!(config, pretty: true)
    File.write(path, json)
  end

  @doc "Gets a single config key."
  @spec get(String.t(), String.t()) :: term()
  def get(key, path \\ @config_path) do
    config = load(path)
    Map.get(config, key)
  end

  @doc "Sets a single config key and saves."
  @spec set(String.t(), term(), String.t()) :: :ok | {:error, term()}
  def set(key, value, path \\ @config_path) do
    config = load(path)
    save(Map.put(config, key, value), path)
  end
end
