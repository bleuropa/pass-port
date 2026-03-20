defmodule Pass.CLITest do
  use ExUnit.Case, async: true

  alias Pass.CLI

  describe "main/1 routing" do
    test "routes help command" do
      assert CLI.main(["help"]) == :ok
    end

    test "routes empty args to help" do
      assert CLI.main([]) == :ok
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
end
