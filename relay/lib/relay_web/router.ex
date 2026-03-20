defmodule RelayWeb.Router do
  use RelayWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", RelayWeb do
    pipe_through :api
  end
end
