defmodule Deskpin.Win32 do
  @moduledoc """
  Binding over `deskpin_nif`. Handles are `HWND` widened to 64-bit integers.
  """

  @on_load :load_nif

  @type hwnd :: non_neg_integer()
  @type window :: %{hwnd: hwnd(), title: binary(), class: binary(), os_pid: non_neg_integer()}

  @doc false
  def load_nif do
    :deskpin
    |> :code.priv_dir()
    |> Path.join("deskpin_nif")
    |> String.to_charlist()
    |> :erlang.load_nif(0)
  end

  @spec foreground() :: hwnd() | nil
  def foreground, do: nif_error()

  @spec windows() :: [window()]
  def windows, do: nif_error()

  @spec info(hwnd()) :: window() | nil
  def info(_hwnd), do: nif_error()

  @spec desktop_layer() :: {:ok, hwnd()} | {:error, atom()}
  def desktop_layer, do: nif_error()

  @spec pin(hwnd()) :: {:ok, hwnd()} | {:error, atom()}
  def pin(_hwnd), do: nif_error()

  @spec unpin(hwnd()) :: :ok | {:error, atom()}
  def unpin(_hwnd), do: nif_error()

  @spec parent(hwnd()) :: hwnd() | nil
  def parent(_hwnd), do: nif_error()

  @spec alive(hwnd()) :: boolean()
  def alive(_hwnd), do: nif_error()

  @doc "Delivers `{:hotkey_ready, boolean}` once, then `:hotkey` per press."
  @spec hotkey_start(non_neg_integer(), non_neg_integer()) :: :ok | {:error, atom()}
  def hotkey_start(_modifiers, _vk), do: nif_error()

  @spec hotkey_stop() :: :ok
  def hotkey_stop, do: nif_error()

  defp nif_error, do: :erlang.nif_error(:deskpin_nif_not_loaded)
end
