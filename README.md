# deskpin

Sends any window to the desktop wallpaper layer, behind the desktop icons,
where it keeps running and stays clickable. Elixir with a small Win32 NIF; MIT.

    mix compile
    deskpin.cmd

A tray icon appears. Press **Ctrl+Win+W** with the target window focused, or
right-click the tray icon and pick the window from *Send window to desktop*.
The same key on an already-pinned window restores it, as does *Restore all*.

## From IEx

    iex -S mix

    Deskpin.list()                  # visible top-level windows
    Deskpin.pin_matching("Terminal")
    Deskpin.pinned()
    Deskpin.restore_all()

## How it works

Windows draws the wallpaper into a `WorkerW` window and the desktop icons into
a sibling that hosts `SHELLDLL_DefView`. Sending Progman the undocumented
message `0x052C` splits those apart; `SetParent` onto the icon-free `WorkerW`
puts a window between the wallpaper and the icons. It keeps its own message
loop, so it stays interactive.

`Deskpin.Win32` binds those calls. `RegisterHotKey` needs a message queue, so
the NIF runs it on its own thread and delivers `WM_HOTKEY` to the owning process
as `:hotkey`. `Deskpin.Pinner` holds the pinned set, prunes handles whose window
has closed, and restores everything on shutdown. `Deskpin.Tray` is `:wx`.

`Deskpin.Pinner` also tracks the last foreground window that was not ours,
because a tray menu takes focus before the click arrives: by then the
foreground window is the menu, not the window the user meant.

## The icon

`Deskpin.Icon` draws the tray artwork analytically and writes PNG and ICO with
no image library — `:zlib` for the PNG stream, a DIB per ICO entry below 256 px
and an embedded PNG at 256. One description renders at every size rather than
one bitmap being resampled.

    mix icon      # writes priv/deskpin.png and priv/deskpin.ico

The tray does not read those files; it renders at 32 px straight into a
`wxImage`. They exist for shortcuts and installers.

## Layout

    c_src/deskpin_nif.c    Win32 calls and the hotkey thread
    lib/deskpin/win32.ex   NIF binding
    lib/deskpin/pinner.ex  pinned set, hotkey owner, foreground tracking
    lib/deskpin/tray.ex    tray icon and menu
    lib/deskpin/icon.ex    PNG and ICO generation

`mix compile` builds the NIF with whatever `gcc` or `cc` is on PATH; it was
developed against llvm-mingw. Windows only.

## Tests

    mix test

`test/win32_test.exs` touches the live desktop. Its hotkey case asserts a
successful registration and a failing one — Ctrl+Shift+Win+F24, which the shell
reserves — so a pass is not something the code can report unconditionally.
