defmodule Deskpin.Win32Test do
  use ExUnit.Case, async: false

  alias Deskpin.Win32

  @moduletag :windows

  test "the desktop layer resolves and is a real window" do
    assert {:ok, layer} = Win32.desktop_layer()
    assert is_integer(layer) and layer > 0
    assert Win32.alive(layer)
  end

  test "enumeration returns titled visible windows" do
    windows = Win32.windows()
    assert is_list(windows)
    assert Enum.all?(windows, &(&1.title != "" and Win32.alive(&1.hwnd)))
  end

  test "a handle that is not a window is rejected rather than reparented" do
    assert Win32.info(1) == nil
    assert Win32.pin(1) == {:error, :no_such_window}
    assert Win32.unpin(1) == {:error, :no_such_window}
    refute Win32.alive(1)
  end

  # Ctrl+Alt+F19 registers; the control is Ctrl+Shift+Win+F24, which the shell
  # reserves, so a `true` here is not something the code reports unconditionally.
  test "the hotkey thread reports registration and stops cleanly" do
    assert :ok = Win32.hotkey_start(0x0002 + 0x0001, 0x82)
    assert_receive {:hotkey_ready, true}, 2000
    assert {:error, :already_running} = Win32.hotkey_start(0x0002 + 0x0001, 0x82)
    assert :ok = Win32.hotkey_stop()

    assert :ok = Win32.hotkey_start(0x0002 + 0x0004 + 0x0008, 0x87)
    assert_receive {:hotkey_ready, false}, 2000
    assert :ok = Win32.hotkey_stop()
  end
end
