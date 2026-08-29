defmodule Deskpin.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children =
      [{Deskpin.Pinner, hotkey: Application.get_env(:deskpin, :hotkey, {[:ctrl, :win], ?W})}] ++
        if(Application.get_env(:deskpin, :tray, true), do: [Deskpin.Tray], else: [])

    Supervisor.start_link(children, strategy: :one_for_one, name: Deskpin.Supervisor)
  end
end
