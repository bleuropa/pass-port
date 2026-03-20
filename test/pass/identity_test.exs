defmodule Pass.IdentityTest do
  use ExUnit.Case, async: true

  alias Pass.Identity

  describe "generate_keypair/0" do
    test "returns a {public_key, secret_key} tuple of 32-byte binaries" do
      {public_key, secret_key} = Identity.generate_keypair()

      assert is_binary(public_key)
      assert is_binary(secret_key)
      assert byte_size(public_key) == 32
      assert byte_size(secret_key) == 32
    end

    test "generates unique keypairs" do
      {pk1, _sk1} = Identity.generate_keypair()
      {pk2, _sk2} = Identity.generate_keypair()

      assert pk1 != pk2
    end
  end

  describe "sign/2 and verify/3" do
    test "round-trip sign and verify" do
      {public_key, secret_key} = Identity.generate_keypair()
      message = "hello, agents"

      signature = Identity.sign(message, secret_key)

      assert Identity.verify(signature, message, public_key)
    end

    test "verification fails with wrong public key" do
      {_pk1, sk1} = Identity.generate_keypair()
      {pk2, _sk2} = Identity.generate_keypair()
      message = "hello"

      signature = Identity.sign(message, sk1)

      refute Identity.verify(signature, message, pk2)
    end

    test "verification fails with tampered message" do
      {public_key, secret_key} = Identity.generate_keypair()

      signature = Identity.sign("original", secret_key)

      refute Identity.verify(signature, "tampered", public_key)
    end
  end

  describe "agent_id/1" do
    test "returns pass_ prefix with 7 char suffix" do
      {public_key, _secret_key} = Identity.generate_keypair()

      id = Identity.agent_id(public_key)

      assert String.starts_with?(id, "pass_")
      assert String.length(id) == 12
    end

    test "is deterministic for the same public key" do
      {public_key, _secret_key} = Identity.generate_keypair()

      assert Identity.agent_id(public_key) == Identity.agent_id(public_key)
    end
  end

  describe "save_keypair/2 and load_keypair/1" do
    test "round-trip save and load" do
      {public_key, secret_key} = Identity.generate_keypair()
      path = Path.join(System.tmp_dir!(), "pass_test_identity_#{:rand.uniform(1_000_000)}.json")

      on_exit(fn -> File.rm(path) end)

      assert :ok = Identity.save_keypair({public_key, secret_key}, path)
      assert {:ok, loaded} = Identity.load_keypair(path)
      assert loaded.public_key == public_key
      assert loaded.secret_key == secret_key
    end

    test "load from nonexistent path returns error" do
      assert {:error, :not_found} = Identity.load_keypair("/tmp/nonexistent_pass_identity.json")
    end

    test "saved file has restricted permissions (0600)" do
      {public_key, secret_key} = Identity.generate_keypair()
      path = Path.join(System.tmp_dir!(), "pass_test_perms_#{:rand.uniform(1_000_000)}.json")

      on_exit(fn -> File.rm(path) end)

      :ok = Identity.save_keypair({public_key, secret_key}, path)
      {:ok, stat} = File.stat(path)

      assert stat.access == :read_write
      # Verify actual mode bits are 0600 (owner read/write only)
      {:ok, %{mode: mode}} = File.stat(path)
      assert Bitwise.band(mode, 0o777) == 0o600
    end

    test "load from corrupt JSON returns error" do
      path = Path.join(System.tmp_dir!(), "pass_test_corrupt_#{:rand.uniform(1_000_000)}.json")
      on_exit(fn -> File.rm(path) end)

      File.write!(path, "not valid json{{{")

      assert {:error, _} = Identity.load_keypair(path)
    end

    test "load from invalid base64 returns error" do
      path = Path.join(System.tmp_dir!(), "pass_test_bad64_#{:rand.uniform(1_000_000)}.json")
      on_exit(fn -> File.rm(path) end)

      File.write!(
        path,
        Jason.encode!(%{"public_key" => "!!!invalid!!!", "secret_key" => "also bad"})
      )

      assert {:error, _} = Identity.load_keypair(path)
    end

    test "load from file with missing keys returns error" do
      path = Path.join(System.tmp_dir!(), "pass_test_missing_#{:rand.uniform(1_000_000)}.json")
      on_exit(fn -> File.rm(path) end)

      File.write!(path, Jason.encode!(%{"something" => "else"}))

      assert {:error, _} = Identity.load_keypair(path)
    end
  end

  describe "ensure_pass_dir/0" do
    test "returns :ok" do
      assert :ok = Identity.ensure_pass_dir()
    end
  end

  describe "default_identity_path/0" do
    test "returns path ending with identity.json under .pass" do
      path = Identity.default_identity_path()

      assert String.ends_with?(path, ".pass/identity.json")
    end
  end
end
