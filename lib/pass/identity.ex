defmodule Pass.Identity do
  @moduledoc """
  Ed25519 keypair management for agent identity.
  """

  @pass_dir Path.expand("~/.pass")
  @identity_file "identity.json"

  @doc """
  Generates a new Ed25519 keypair.

  Returns `{public_key, secret_key}` as raw binaries.
  """
  @spec generate_keypair() :: {binary(), binary()}
  def generate_keypair do
    {secret_key, public_key} = Ed25519.generate_key_pair()
    {public_key, secret_key}
  end

  @doc """
  Signs binary data with the given secret key.
  """
  @spec sign(binary(), binary()) :: binary()
  def sign(data, secret_key) do
    Ed25519.signature(data, secret_key)
  end

  @doc """
  Verifies a signature against a public key.
  """
  @spec verify(binary(), binary(), binary()) :: boolean()
  def verify(signature, data, public_key) do
    Ed25519.valid_signature?(signature, data, public_key)
  end

  @doc """
  Derives a short agent ID from a public key.

  Format: `pass_` + first 7 characters of base64url-encoded public key.
  """
  @spec agent_id(binary()) :: String.t()
  def agent_id(public_key) do
    short =
      public_key
      |> Base.url_encode64(padding: false)
      |> binary_part(0, 7)

    "pass_" <> short
  end

  @doc """
  Saves a keypair to the given path as JSON with base64-encoded keys.
  """
  @spec save_keypair({binary(), binary()}, String.t()) :: :ok | {:error, term()}
  def save_keypair({public_key, secret_key}, path) do
    json =
      Jason.encode!(%{
        public_key: Base.encode64(public_key),
        secret_key: Base.encode64(secret_key)
      })

    path |> Path.dirname() |> File.mkdir_p!()
    File.write(path, json)
  end

  @doc """
  Loads a keypair from the given path.

  Returns `{:ok, %{public_key: ..., secret_key: ...}}` with raw binary keys,
  or `{:error, :not_found}`.
  """
  @spec load_keypair(String.t()) ::
          {:ok, %{public_key: binary(), secret_key: binary()}} | {:error, :not_found}
  def load_keypair(path) do
    case File.read(path) do
      {:ok, contents} ->
        data = Jason.decode!(contents)

        {:ok,
         %{
           public_key: Base.decode64!(data["public_key"]),
           secret_key: Base.decode64!(data["secret_key"])
         }}

      {:error, :enoent} ->
        {:error, :not_found}
    end
  end

  @doc """
  Creates `~/.pass/` directory if it doesn't exist.
  """
  @spec ensure_pass_dir() :: :ok | {:error, term()}
  def ensure_pass_dir do
    File.mkdir_p(@pass_dir)
  end

  @doc """
  Returns the default identity file path: `~/.pass/identity.json`.
  """
  @spec default_identity_path() :: String.t()
  def default_identity_path do
    Path.join(@pass_dir, @identity_file)
  end
end
