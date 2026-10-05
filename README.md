# interactor-deskpin

Sends any window to the Windows desktop wallpaper layer, behind the icons, where it keeps running and stays clickable.

## What it is for

It sits in the tray. A hotkey or the tray menu pins the focused window behind the desktop icons, and the same action restores it. It is Elixir with a small native binding for the desktop calls, and it runs on Windows only.

## Build and run

```sh
mix compile
deskpin.cmd
```

The build needs `gcc` or `cc` on the `PATH` for the native binding, and an Erlang/OTP built with wx.

## Licence

MIT; see `LICENSE`.
