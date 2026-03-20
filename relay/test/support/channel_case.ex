defmodule RelayWeb.ChannelCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import RelayWeb.ChannelCase

      @endpoint RelayWeb.Endpoint
    end
  end
end
