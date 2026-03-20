import Config

config :pass,
  relay_url: "ws://localhost:4000/socket/agent/websocket",
  auto_connect: false

import_config "#{config_env()}.exs"
