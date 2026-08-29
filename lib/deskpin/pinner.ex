defmodule Deskpin.Pinner do
  @moduledoc """
  Owns the pinned-window set and the global hotkey.

  It also remembers the last foreground window that was not our own, because a
  tray menu takes focus before the click is delivered: by then `foreground/0`
  is the menu, not the window the user meant.
  """

  use GenServer

  alias Deskpin.Win32

  @poll_interval 400
  @modifiers %{alt: 0x0001, ctrl: 0x0002, shift: 0x0004, win: 0x0008}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Pins the window the user was last in, or an explicit handle."
  def pin_foreground, do: GenServer.call(__MODULE__, :pin_foreground)
  def pin(hwnd) when is_integer(hwnd), do: GenServer.call(__MODULE__, {:pin, hwnd})
  def unpin(hwnd) when is_integer(hwnd), do: GenServer.call(__MODULE__, {:unpin, hwnd})
  def unpin_all, do: GenServer.call(__MODULE__, :unpin_all)
  def pinned, do: GenServer.call(__MODULE__, :pinned)
  def candidates, do: GenServer.call(__MODULE__, :candidates)

  @doc "Pins the first visible window whose title contains `pattern`."
  def pin_matching(pattern) when is_binary(pattern),
    do: GenServer.call(__MODULE__, {:pin_matching, pattern})

  @impl true
  def init(opts) do
    {mods, vk} = Keyword.get(opts, :hotkey, {[:ctrl, :win], ?W})
    bits = Enum.reduce(mods, 0, fn m, acc -> Bitwise.bor(acc, Map.fetch!(@modifiers, m)) end)

    case Win32.hotkey_start(bits, vk) do
      :ok -> :ok
      {:error, reason} -> notify({:hotkey_failed, reason})
    end

    Process.send_after(self(), :poll, @poll_interval)
    {:ok, %{pinned: %{}, last_fg: nil, own_pid: own_os_pid(), hotkey: :pending}}
  end

  @impl true
  def handle_call(:pin_foreground, _from, state) do
    target = state.last_fg || Win32.foreground()
    {reply, state} = do_pin(target, state)
    {:reply, reply, state}
  end

  def handle_call({:pin, hwnd}, _from, state) do
    {reply, state} = do_pin(hwnd, state)
    {:reply, reply, state}
  end

  def handle_call({:pin_matching, pattern}, _from, state) do
    down = String.downcase(pattern)

    match =
      Win32.windows()
      |> Enum.reject(&(&1.os_pid == state.own_pid))
      |> Enum.find(&String.contains?(String.downcase(&1.title), down))

    case match do
      nil ->
        {:reply, {:error, :no_match}, state}

      window ->
        {reply, state} = do_pin(window.hwnd, state)
        {:reply, reply, state}
    end
  end

  def handle_call({:unpin, hwnd}, _from, state) do
    {:reply, Win32.unpin(hwnd), %{state | pinned: Map.delete(state.pinned, hwnd)}}
  end

  def handle_call(:unpin_all, _from, state) do
    Enum.each(Map.keys(state.pinned), &Win32.unpin/1)
    {:reply, :ok, %{state | pinned: %{}}}
  end

  def handle_call(:pinned, _from, state), do: {:reply, Map.values(state.pinned), state}

  def handle_call(:candidates, _from, state) do
    windows =
      Win32.windows()
      |> Enum.reject(&(&1.os_pid == state.own_pid or Map.has_key?(state.pinned, &1.hwnd)))

    {:reply, windows, state}
  end

  @impl true
  def handle_info(:hotkey, state) do
    {_reply, state} = do_pin(Win32.foreground(), state)
    {:noreply, state}
  end

  def handle_info({:hotkey_ready, ok?}, state) do
    unless ok?, do: notify({:hotkey_failed, :already_taken})
    {:noreply, %{state | hotkey: ok?}}
  end

  def handle_info(:poll, state) do
    Process.send_after(self(), :poll, @poll_interval)
    live = state.pinned |> Enum.filter(fn {hwnd, _} -> Win32.alive(hwnd) end) |> Map.new()
    {:noreply, %{state | pinned: live, last_fg: track_foreground(state)}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    Enum.each(Map.keys(state.pinned), &Win32.unpin/1)
    Win32.hotkey_stop()
    :ok
  end

  defp do_pin(nil, state), do: {{:error, :no_target}, state}

  defp do_pin(hwnd, state) do
    info = Win32.info(hwnd)

    cond do
      is_nil(info) ->
        {{:error, :no_such_window}, state}

      info.os_pid == state.own_pid ->
        {{:error, :own_window}, state}

      Map.has_key?(state.pinned, hwnd) ->
        Win32.unpin(hwnd)
        notify({:unpinned, info})
        {{:ok, :unpinned}, %{state | pinned: Map.delete(state.pinned, hwnd)}}

      true ->
        case Win32.pin(hwnd) do
          {:ok, layer} ->
            record = Map.put(info, :layer, layer)
            notify({:pinned, record})
            {{:ok, record}, %{state | pinned: Map.put(state.pinned, hwnd, record)}}

          {:error, reason} = error ->
            notify({:failed, reason})
            {error, state}
        end
    end
  end

  defp track_foreground(state) do
    with hwnd when is_integer(hwnd) <- Win32.foreground(),
         info when is_map(info) <- Win32.info(hwnd),
         false <- info.os_pid == state.own_pid,
         false <- info.title == "" do
      hwnd
    else
      _ -> state.last_fg
    end
  end

  defp own_os_pid, do: :os.getpid() |> List.to_integer()

  defp notify(event) do
    case Process.whereis(Deskpin.Tray) do
      nil -> :ok
      pid -> send(pid, {:deskpin_event, event})
    end
  end
end
