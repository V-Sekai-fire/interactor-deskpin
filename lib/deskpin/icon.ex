defmodule Deskpin.Icon do
  @moduledoc """
  Generates the tray artwork: a desktop panel in front, an application window
  sliding behind it. Rendered analytically at any size, so the 16 px tray glyph
  and the 256 px shell icon come from one description rather than a resampled
  bitmap. Emits PNG and Windows ICO with no image library.
  """

  @accent {0x4C, 0x8D, 0xF6}
  @accent_bar {0x9A, 0xC1, 0xFB}
  @panel {0x1D, 0x22, 0x2E}
  @panel_edge {0x44, 0x50, 0x6B}
  @glyph {0xA6, 0xB6, 0xD4}

  @ico_sizes [16, 20, 24, 32, 40, 48, 64, 128, 256]
  @samples 4

  @doc "RGBA8 pixel data, row-major, `size` x `size`."
  @spec rgba(pos_integer()) :: binary()
  def rgba(size) do
    for y <- 0..(size - 1), x <- 0..(size - 1), into: <<>> do
      {r, g, b, a} = supersample(x, y, size)
      <<r, g, b, a>>
    end
  end

  @spec png(pos_integer()) :: binary()
  def png(size) do
    raw = rgba(size)

    scanlines =
      for row <- 0..(size - 1), into: <<>> do
        <<0, :binary.part(raw, row * size * 4, size * 4)::binary>>
      end

    <<137, ?P, ?N, ?G, 13, 10, 26, 10>> <>
      chunk("IHDR", <<size::32, size::32, 8, 6, 0, 0, 0>>) <>
      chunk("IDAT", deflate(scanlines)) <>
      chunk("IEND", <<>>)
  end

  @doc "Interleaved RGB plus a separate alpha plane, the layout `wxImage` wants."
  @spec planes(pos_integer()) :: {binary(), binary()}
  def planes(size) do
    for <<r, g, b, a <- rgba(size)>>, reduce: {<<>>, <<>>} do
      {rgb, alpha} -> {<<rgb::binary, r, g, b>>, <<alpha::binary, a>>}
    end
  end

  @spec ico() :: binary()
  def ico, do: ico(@ico_sizes)

  @spec ico([pos_integer()]) :: binary()
  def ico(sizes) do
    images = Enum.map(sizes, fn size -> {size, image_payload(size)} end)
    offset0 = 6 + 16 * length(images)

    {entries, _} =
      Enum.map_reduce(images, offset0, fn {size, payload}, offset ->
        dim = if size >= 256, do: 0, else: size

        entry =
          <<dim, dim, 0, 0, 1::little-16, 32::little-16, byte_size(payload)::little-32,
            offset::little-32>>

        {entry, offset + byte_size(payload)}
      end)

    <<0::little-16, 1::little-16, length(images)::little-16>> <>
      IO.iodata_to_binary(entries) <>
      IO.iodata_to_binary(Enum.map(images, fn {_, payload} -> payload end))
  end

  @doc "Writes `deskpin.png` (256 px) and `deskpin.ico` into `dir`."
  @spec write!(Path.t()) :: [Path.t()]
  def write!(dir) do
    File.mkdir_p!(dir)
    png_path = Path.join(dir, "deskpin.png")
    ico_path = Path.join(dir, "deskpin.ico")
    File.write!(png_path, png(256))
    File.write!(ico_path, ico())
    [png_path, ico_path]
  end

  # Windows accepts embedded PNG only for the 256 px entry; the rest are DIBs.
  defp image_payload(size) when size >= 256, do: png(size)

  defp image_payload(size) do
    pixels =
      for y <- (size - 1)..0//-1, x <- 0..(size - 1), into: <<>> do
        {r, g, b, a} = supersample(x, y, size)
        <<b, g, r, a>>
      end

    mask_row = div(size + 31, 32) * 4

    <<40::little-32, size::little-32, (size * 2)::little-32, 1::little-16, 32::little-16,
      0::little-32, byte_size(pixels)::little-32, 0::little-32, 0::little-32, 0::little-32,
      0::little-32>> <>
      pixels <> :binary.copy(<<0>>, mask_row * size)
  end

  defp supersample(x, y, size) do
    step = 1.0 / @samples

    samples =
      for sy <- 0..(@samples - 1), sx <- 0..(@samples - 1) do
        u = (x + (sx + 0.5) * step) / size
        v = (y + (sy + 0.5) * step) / size
        color_at(u, v)
      end

    total = length(samples)
    covered = Enum.reject(samples, &is_nil/1)

    case covered do
      [] ->
        {0, 0, 0, 0}

      _ ->
        n = length(covered)
        {r, g, b} = Enum.reduce(covered, {0, 0, 0}, fn {r, g, b}, {ar, ag, ab} ->
          {ar + r, ag + g, ab + b}
        end)

        {div(r, n), div(g, n), div(b, n), round(255 * n / total)}
    end
  end

  defp color_at(u, v) do
    cond do
      glyph?(u, v) -> @glyph
      in_rrect?(u, v, 0.03, 0.34, 0.66, 0.96, 0.09) -> panel_color(u, v)
      in_rrect?(u, v, 0.34, 0.05, 0.97, 0.60, 0.07) -> back_window_color(v)
      true -> nil
    end
  end

  defp panel_color(u, v) do
    if in_rrect?(u, v, 0.065, 0.375, 0.625, 0.925, 0.07), do: @panel, else: @panel_edge
  end

  defp back_window_color(v), do: if(v < 0.17, do: @accent_bar, else: @accent)

  defp glyph?(u, v) do
    Enum.any?(
      [{0.13, 0.45, 0.27, 0.59}, {0.35, 0.45, 0.49, 0.59}, {0.13, 0.67, 0.27, 0.81}],
      fn {x0, y0, x1, y1} -> in_rrect?(u, v, x0, y0, x1, y1, 0.02) end
    )
  end

  defp in_rrect?(u, v, x0, y0, x1, y1, r) do
    cx = clamp(u, x0 + r, x1 - r)
    cy = clamp(v, y0 + r, y1 - r)
    dx = u - cx
    dy = v - cy
    dx * dx + dy * dy <= r * r
  end

  defp clamp(value, lo, hi) when lo > hi, do: clamp(value, (lo + hi) / 2, (lo + hi) / 2)
  defp clamp(value, lo, hi), do: value |> max(lo) |> min(hi)

  defp chunk(type, data) do
    payload = type <> data
    <<byte_size(data)::32>> <> payload <> <<:erlang.crc32(payload)::32>>
  end

  defp deflate(data) do
    z = :zlib.open()
    :zlib.deflateInit(z, 9)
    out = :zlib.deflate(z, data, :finish)
    :zlib.deflateEnd(z)
    :zlib.close(z)
    IO.iodata_to_binary(out)
  end
end
