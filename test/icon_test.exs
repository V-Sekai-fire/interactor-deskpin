defmodule Deskpin.IconTest do
  use ExUnit.Case, async: true

  alias Deskpin.Icon

  test "png carries the declared dimensions and a decodable image" do
    png = Icon.png(32)

    assert <<137, ?P, ?N, ?G, 13, 10, 26, 10, 13::32, "IHDR", 32::32, 32::32, 8, 6, 0, 0, 0,
             _crc::32, rest::binary>> = png

    assert byte_size(inflate_idat(rest)) == 32 * (1 + 32 * 4)
  end

  test "rgba is transparent in the corner and opaque in the panel" do
    size = 64
    pixels = Icon.rgba(size)
    assert {_, _, _, 0} = pixel(pixels, size, 0, size - 1)
    assert {_, _, _, 255} = pixel(pixels, size, div(size * 30, 100), div(size * 65, 100))
  end

  test "ico directory agrees with the payloads it points at" do
    ico = Icon.ico([16, 32, 256])
    <<0::little-16, 1::little-16, count::little-16, rest::binary>> = ico
    assert count == 3

    entries =
      for i <- 0..(count - 1) do
        <<w, _h, _c, _r, 1::little-16, 32::little-16, size::little-32, offset::little-32>> =
          :binary.part(rest, i * 16, 16)

        {w, size, offset}
      end

    assert [{16, _, _}, {32, _, _}, {0, _, _}] = entries

    Enum.each(entries, fn {_w, size, offset} ->
      assert byte_size(:binary.part(ico, offset, size)) == size
    end)

    {_, size256, offset256} = List.last(entries)
    assert <<137, ?P, ?N, ?G, _::binary>> = :binary.part(ico, offset256, size256)
  end

  test "planes split into rgb and alpha of matching pixel counts" do
    {rgb, alpha} = Icon.planes(16)
    assert byte_size(rgb) == 16 * 16 * 3
    assert byte_size(alpha) == 16 * 16
  end

  defp pixel(pixels, size, x, y) do
    <<r, g, b, a>> = :binary.part(pixels, (y * size + x) * 4, 4)
    {r, g, b, a}
  end

  defp inflate_idat(<<len::32, "IDAT", data::binary-size(len), _crc::32, _::binary>>),
    do: :zlib.uncompress(data)

  defp inflate_idat(<<len::32, _type::binary-4, _data::binary-size(len), _crc::32, rest::binary>>),
    do: inflate_idat(rest)
end
