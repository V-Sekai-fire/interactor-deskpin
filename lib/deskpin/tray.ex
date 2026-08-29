defmodule Deskpin.Tray do
  @moduledoc """
  System tray icon and menu, built on `:wx` from OTP.

  The menu is rebuilt on each right-click so the window list is current.
  """

  use GenServer
  require Logger

  alias Deskpin.{Icon, Pinner}

  @icon_size 32
  @id_pin_last 4001
  @id_unpin_all 4002
  @id_quit 4003
  @id_window_base 4100

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    case start_wx() do
      {:ok, state} -> {:ok, state}
      {:error, reason} -> {:stop, {:wx_unavailable, reason}}
    end
  end

  defp start_wx do
    wx = :wx.new()
    icon = build_icon()
    tbi = :wxTaskBarIcon.new()
    true = :wxTaskBarIcon.setIcon(tbi, icon, tooltip: tooltip(0))

    :wxTaskBarIcon.connect(tbi, :taskbar_right_down)
    :wxTaskBarIcon.connect(tbi, :taskbar_left_dclick)
    :wxTaskBarIcon.connect(tbi, :command_menu_selected)

    {:ok, %{wx: wx, tbi: tbi, icon: icon, menu_windows: %{}}}
  rescue
    error -> {:error, error}
  end

  defp build_icon do
    {rgb, alpha} = Icon.planes(@icon_size)
    image = :wxImage.new(@icon_size, @icon_size, rgb)
    :wxImage.setAlpha(image, alpha)
    bitmap = :wxBitmap.new(image)
    icon = :wxIcon.new()
    :wxIcon.copyFromBitmap(icon, bitmap)
    :wxBitmap.destroy(bitmap)
    :wxImage.destroy(image)
    icon
  end

  @impl true
  def handle_info({:wx, _id, _obj, _user, {:wxTaskBarIcon, :taskbar_right_down}}, state) do
    {:noreply, popup(state)}
  end

  def handle_info({:wx, _id, _obj, _user, {:wxTaskBarIcon, :taskbar_left_dclick}}, state) do
    Pinner.pin_foreground()
    {:noreply, state}
  end

  def handle_info({:wx, @id_pin_last, _obj, _user, _event}, state) do
    Pinner.pin_foreground()
    {:noreply, state}
  end

  def handle_info({:wx, @id_unpin_all, _obj, _user, _event}, state) do
    Pinner.unpin_all()
    {:noreply, refresh_tooltip(state)}
  end

  def handle_info({:wx, @id_quit, _obj, _user, _event}, state) do
    Pinner.unpin_all()
    System.stop(0)
    {:noreply, state}
  end

  def handle_info({:wx, id, _obj, _user, _event}, state) when id >= @id_window_base do
    case Map.fetch(state.menu_windows, id) do
      {:ok, hwnd} -> Pinner.pin(hwnd)
      :error -> :ok
    end

    {:noreply, state}
  end

  def handle_info({:deskpin_event, event}, state) do
    log(event)
    {:noreply, refresh_tooltip(state)}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    :wxTaskBarIcon.removeIcon(state.tbi)
    :wxTaskBarIcon.destroy(state.tbi)
    :ok
  end

  defp popup(state) do
    menu = :wxMenu.new()
    pinned = Pinner.pinned()

    :wxMenu.append(menu, @id_pin_last, "Pin last active window\tCtrl+Win+W")
    :wxMenu.appendSeparator(menu)

    submenu = :wxMenu.new()
    candidates = Enum.take(Pinner.candidates(), 30)
    mapping = fill(submenu, candidates, @id_window_base, & &1)
    :wxMenu.append(menu, -1, "Send window to desktop", submenu)

    # Selecting a pinned window pins it again, and `Pinner` reads a second pin
    # of the same handle as a restore.
    pinned_map =
      if pinned == [] do
        %{}
      else
        :wxMenu.appendSeparator(menu)
        fill(menu, pinned, @id_window_base + 100, &("Restore: " <> &1))
      end

    :wxMenu.appendSeparator(menu)
    :wxMenu.append(menu, @id_unpin_all, "Restore all")
    :wxMenu.append(menu, @id_quit, "Quit")

    :wxTaskBarIcon.popupMenu(state.tbi, menu)
    :wxMenu.destroy(menu)
    %{state | menu_windows: Map.merge(mapping, pinned_map)}
  end

  defp fill(menu, windows, base, decorate) do
    windows
    |> Enum.with_index(base)
    |> Map.new(fn {window, id} ->
      :wxMenu.append(menu, id, decorate.(label(window)))
      {id, window.hwnd}
    end)
  end

  defp label(%{title: title}) do
    title
    |> String.slice(0, 60)
    |> String.replace("\t", " ")
    |> String.replace("&", "&&")
  end

  defp refresh_tooltip(state) do
    :wxTaskBarIcon.setIcon(state.tbi, state.icon, tooltip: tooltip(length(Pinner.pinned())))
    state
  end

  defp tooltip(0), do: "Deskpin — nothing pinned"
  defp tooltip(1), do: "Deskpin — 1 window on the desktop"
  defp tooltip(n), do: "Deskpin — #{n} windows on the desktop"

  defp log({:pinned, w}), do: Logger.info("pinned #{w.hwnd} #{w.title}")
  defp log({:unpinned, w}), do: Logger.info("restored #{w.hwnd} #{w.title}")
  defp log({:failed, reason}), do: Logger.warning("pin failed: #{inspect(reason)}")
  defp log({:hotkey_failed, reason}), do: Logger.warning("hotkey unavailable: #{inspect(reason)}")
  defp log(other), do: Logger.debug(inspect(other))
end
