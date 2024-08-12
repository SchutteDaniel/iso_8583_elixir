defmodule ISO8583.Decode do
  @moduledoc false
  alias ISO8583.DataTypes
  alias ISO8583.Utils
  import ISO8583.Guards
  alias ISO8583.Message.MTI
  alias ISO8583.Message.StaticMeta
  require Logger

  def decode_0_127(message, opts) do
    with {:ok, _, chunk1} <- extract_tcp_len_header(message, opts),
         {:ok, _, without_static_meta} <- StaticMeta.extract(chunk1, opts[:static_meta]),
         {:ok, mti, chunk2} <- extract_mti(without_static_meta),
         {:ok, bitmap, chunk3} <- extract_bitmap(chunk2, opts),
         {:ok, decoded} <- extract_children(bitmap, chunk3, "", %{}, 0, opts) do
      {:ok, decoded |> Map.merge(%{"0": mti})}
    else
      error -> error
    end
  end

  defp extract_bitmap(message, opts) do
    case opts[:bitmap_encoding] do
      :hex ->
        extract_bitmap(message, opts, 16)
      _ ->
        extract_bitmap(message, opts, 16)
    end
  end

#  defp extract_bitmap(message, _, length) do
#    with {:ok, bitmap, without_bitmap} <- Utils.slice(message, 0, length),
#         bitmap <- Utils.bytes_to_hex(bitmap) |> Utils.iterable_bitmap(128) do
#      {:ok, bitmap, without_bitmap}
#    else
#      error -> error
#    end
#  end

  defp extract_bitmap(message, _, length) do

    with {:ok, bitmap, without_bitmap} <- Utils.slice(message, 0, length),
         bitmap_bits <- Utils.bytes_to_hex(bitmap) |> Utils.iterable_bitmap(64),
         {combined_bitmap, remaining_data} <- get_optional_second_bitmap(bitmap_bits, without_bitmap) do
      {:ok, combined_bitmap, remaining_data}
    else
      error -> error
    end
  end

  defp get_optional_second_bitmap([1 | _rest] = bitmap, without_bitmap) do
    # Extract the next 8 bytes if the first bit is 1
    with {:ok, extra_bitmap, remaining_data} = Utils.slice(without_bitmap, 0, 8),
      bitmap_bits <- Utils.bytes_to_hex(extra_bitmap) |> Utils.iterable_bitmap(64) do
      [bitmap ++ bitmap_bits, remaining_data]
    end
  end
  defp get_optional_second_bitmap(bitmap, without_bitmap), do: {bitmap, without_bitmap}


  defp extract_mti(message) when has_mti(message) do
    with {:ok, mti, without_mti} <- Utils.slice(message, 0, 4),
         {:ok, _} <- MTI.is_valid(mti) do
      {:ok, mti, without_mti}
    else
      error -> error
    end
  end

  defp extract_mti(_), do: {:error, "Error while extracting MTI, Not encoded"}

  defp extract_tcp_len_header(message, opts) when has_tcp_length_indicator(message) do
    case opts[:tcp_len_header] do
      true ->
        {:ok, tcp_len_header_bin, rest} = Utils.slice(message, 0, 2)
        tcp_len_header = tcp_len_header_bin |> Utils.bytes_to_hex() |> Utils.extract_tcp_header()
        {:ok, tcp_len_header, rest}

      false ->
        {:ok, 0, message}
    end
  end

  defp extract_tcp_len_header(_, _),
    do: {:error, "Error while extracting message length indicator, Not encoded"}

  def expand_field(%{"127": data} = message, "127.", opts) do
    case expand_binary(data, "127.", opts) do
      {:ok, expanded} -> {:ok, Map.merge(message, expanded)}
      error -> error
    end
  end

  def expand_field(%{"127.25": data} = message, "127.25.", opts) do
    case expand_binary(data, "127.25.", opts) do
      {:ok, expanded} -> {:ok, Map.merge(message, expanded)}
      error -> error
    end
  end

  def expand_field(message, _, _), do: {:ok, message}

  def binary_to_decimals(binary_list) do
    binary_to_decimals(binary_list, [], 1)
  end

  defp binary_to_decimals([], result, _current_value) do
    Enum.reverse(result)
  end

  defp binary_to_decimals([0 | rest], result, current_value) do
    binary_to_decimals(rest, result, current_value + 1)
  end

  defp binary_to_decimals([1 | rest], result, current_value) do
    binary_to_decimals(rest, [current_value | result], current_value + 1)
  end

  def expand_binary(data, field_pad, opts) do
    # 16 to 8
    ## {:ok, bitmap_binary, without_bitmap} <- Utils.slice(data, 0, 16),

 #   with
         {:ok, bitmap, without_bitmap} = extract_bitmap(data, opts, 8)
 #        decimal_bitmap = binary_to_decimals(bitmap)
         {:ok, decoded} = extract_children(bitmap, without_bitmap, field_pad, %{}, 0, opts)

         {:ok, decoded}

#         bitmap <- Utils.iterable_bitmap(bitmap_binary, 64),
#         {:ok, expanded} <- extract_children(bitmap, without_bitmap, field_pad, %{}, 0, opts) do
#    else
#      error -> error
#    end
  end

  defp extract_children([], _, _, extracted, _, _), do: {:ok, extracted}

  defp extract_children(bitmap, data, pad, extracted, counter, opts) do
    [current | rest] = bitmap
    field = Utils.construct_field(counter + 1, pad)

    case current do
      1 ->
        format = opts[:formats][field]
        {field_data, left} = extract_field_data(field, data, format)

        with true <- DataTypes.check_data_length(field, field_data, format),
             true <- DataTypes.valid?(field, field_data, format) do
          extracted = extracted |> Map.put(field, field_data)
          extract_children(rest, left, pad, extracted, counter + 1, opts)
        else
          error ->
            error
        end

      0 ->
        extract_children(rest, data, pad, extracted, counter + 1, opts)
    end
  end

  defp extract_field_data(_, data, nil), do: {"", data}

  defp extract_field_data(_, data, %{len_type: len_type} = format)
       when len_type == "fixed" do
    Utils.extract_hex_data(
      data,
      format.max_len,
      format.content_type
    )
  end

  defp extract_field_data(_, <<>>, _), do: {"", <<>>}

  defp extract_field_data(_, data, %{len_type: _} = format) do
    data_length = String.length(data)

    len_indicator_length = Utils.var_len_chars(format)

    with {:ok, field_data_len, without_length} <- Utils.slice(data, 0, len_indicator_length),
         {extracted, remaining} <-
           Utils.extract_hex_data(
             without_length,
             String.to_integer(field_data_len),
             format.content_type
           ) do
      {extracted, remaining}
    else
      error -> error
    end
  end

  defp extract_field_data(x, data, format) do
    Logger.debug("x: #{x} data: #{data}  format: #{inspect(format)}")

  end

end
