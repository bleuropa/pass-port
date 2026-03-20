defmodule Pass.MCP.Server do
  @moduledoc """
  MCP server exposing Pass actions as tools.

  Supports stdio transport for integration with Claude Code, Cursor, and other MCP clients.
  """

  use Jido.MCP.Server,
    name: "pass",
    version: "0.1.0",
    publish: %{
      tools: [
        Pass.Actions.PublishSolution,
        Pass.Actions.QuerySolutions,
        Pass.Actions.GetStatus
      ]
    }
end
