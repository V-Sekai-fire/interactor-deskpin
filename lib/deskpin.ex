defmodule Deskpin do
  @moduledoc """
  Sends any window to the desktop wallpaper layer, behind the desktop icons,
  where it keeps running and stays clickable. The tray icon and the Ctrl+Win+W
  hotkey do the same thing interactively.
  """

  alias Deskpin.Pinner

  defdelegate pin(hwnd), to: Pinner
  defdelegate pin_matching(pattern), to: Pinner
  defdelegate pin_foreground(), to: Pinner
  defdelegate restore(hwnd), to: Pinner, as: :unpin
  defdelegate restore_all(), to: Pinner, as: :unpin_all
  defdelegate pinned(), to: Pinner

  @doc "Every visible top-level window that is a pin candidate."
  defdelegate list(), to: Pinner, as: :candidates
end
