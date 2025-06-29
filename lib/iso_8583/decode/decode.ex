defmodule ISO8583.Decode do
  @moduledoc false
  alias ISO8583.DataTypes
  alias ISO8583.Utils
  import ISO8583.Guards
  alias ISO8583.Message.MTI
  alias ISO8583.Message.StaticMeta
  require Logger

  def decode_0_127(message, opts) do
    if Keyword.get(opts, :de_detail, false) do
      Logger.debug("Decoding message: #{inspect(message)}")
    end

    with {:ok, _, chunk1} <- extract_tcp_len_header(message, opts),
         {:ok, _, without_static_meta} <- StaticMeta.extract(chunk1, opts[:static_meta]),
         {:ok, mti, chunk2} <- extract_mti(without_static_meta),
         {:ok, bitmap, chunk3} <- extract_bitmap(chunk2, opts) do
      if Keyword.get(opts, :de_detail, false) do
        Logger.debug("Raw data to be parsed for fields (after bitmaps): #{inspect(chunk3)}")
      end
      with {:ok, decoded} <- extract_children(bitmap, chunk3, "", %{}, 0, opts) do
        if Keyword.get(opts, :de_detail, false) do
          Logger.debug("Decoded message: #{inspect(decoded)}")
        end
      {:ok, decoded |> Map.merge(%{"0": mti})}
      else
        error -> error
      end
    else
      error -> error
    end
  end

  def extract_bitmap(message, opts) do
    initial_length =
      case opts[:bitmap_encoding] do
        :hex -> 16  # 16 hex chars = 8 bytes (64 bits)
        _ -> 8      # 8 bytes = 64 bits
      end

    # Extract primary bitmap
    case extract_bitmap(message, opts[:bitmap_encoding], initial_length) do
      {:ok, primary_bitmap, remaining_message} ->
        if Keyword.get(opts, :de_detail, false) do
          Logger.debug("Data after primary bitmap: #{inspect(remaining_message)}")
        end
        primary_fields = get_active_fields(primary_bitmap, 0)
        if Keyword.get(opts, :de_detail, false) do
        Logger.debug("Primary bitmap active fields: #{inspect(primary_fields, charlists: :as_lists)}")
        end

        # Check if secondary bitmap exists
        if Enum.at(primary_bitmap, 0) == 1 do
          # Extract secondary bitmap
          case extract_bitmap(remaining_message, opts[:bitmap_encoding], initial_length) do
            {:ok, secondary_bitmap, final_message} ->
              if Keyword.get(opts, :de_detail, false) do
                Logger.debug("Data after secondary bitmap: #{inspect(final_message)}")
              end
              secondary_fields = get_active_fields(secondary_bitmap, 64)
              if Keyword.get(opts, :de_detail, false) do
              Logger.debug("Secondary bitmap active fields: #{inspect(secondary_fields, charlists: :as_lists)}")
              end

              # Check if tertiary bitmap exists
              if Enum.at(secondary_bitmap, 0) == 1 do
                # Extract tertiary bitmap
                case extract_bitmap(final_message, opts[:bitmap_encoding], initial_length) do
                  {:ok, tertiary_bitmap, final_message} ->
                    if Keyword.get(opts, :de_detail, false) do
                      Logger.debug("Data after tertiary bitmap: #{inspect(final_message)}")
                    end
                    tertiary_fields = get_active_fields(tertiary_bitmap, 128)
                    if Keyword.get(opts, :de_detail, false) do
                      Logger.debug("Tertiary bitmap active fields: #{inspect(tertiary_fields, charlists: :as_lists)}")
                      Logger.debug("Combined bitmap active fields: #{inspect(primary_fields ++ secondary_fields ++ tertiary_fields, charlists: :as_lists)}")
                      Logger.debug("First 40 chars of data after bitmaps: #{inspect(String.slice(final_message, 0, 40))}")
                    end

                    # Create a combined bitmap for processing
                    combined_bitmap = primary_bitmap ++ secondary_bitmap ++ tertiary_bitmap
                    {:ok, combined_bitmap, final_message}

                  error -> error
                end
              else
                # No tertiary bitmap, use final message as is
                if Keyword.get(opts, :de_detail, false) do
              Logger.debug("Combined bitmap active fields: #{inspect(primary_fields ++ secondary_fields, charlists: :as_lists)}")
                  Logger.debug("First 40 chars of data after bitmaps: #{inspect(String.slice(final_message, 0, 40))}")
                end

                # Create a combined bitmap for processing
              combined_bitmap = primary_bitmap ++ secondary_bitmap
              {:ok, combined_bitmap, final_message}
              end

            error -> error
          end
        else
          # No secondary bitmap, use remaining message as is
          {:ok, primary_bitmap, remaining_message}
        end
      error -> error
    end
  end

  def extract_bitmap(message, :hex, length) do
    try do
      <<bitmap_hex::binary-size(length), without_bitmap::binary>> = message
      bitmap = Utils.iterable_bitmap(bitmap_hex, 64)
      {:ok, bitmap, without_bitmap}
    rescue
      _ -> {:error, :bitmap_extraction_failed}
    end
  end

  def extract_bitmap(message, _encoding, length) do
    try do
      <<bitmap_bytes::binary-size(length), without_bitmap::binary>> = message
      bitmap_hex = Utils.bytes_to_hex(bitmap_bytes)
      bitmap = Utils.iterable_bitmap(bitmap_hex, 64)
      {:ok, bitmap, without_bitmap}
    rescue
      _ -> {:error, :bitmap_extraction_failed}
    end
  end

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

  def expand_binary(data, field_pad, opts) do
    with {:ok, bitmap_binary, without_bitmap} <- Utils.slice(data, 0, 16),
         bitmap <- Utils.iterable_bitmap(bitmap_binary, 64),
         {:ok, expanded} <-
           extract_children(bitmap, without_bitmap, field_pad, %{}, 0, opts) do
      {:ok, expanded}
    else
      error -> error
    end
  end

  defp extract_children([], _, _, extracted, _, _), do: {:ok, extracted}

  defp extract_children(bitmap, data, pad, extracted, counter, opts) do
    [current | rest] = bitmap
    if counter == 0 or counter == 63 or counter == 64 do
      extract_children(rest, data, pad, extracted, counter + 1, opts)
    else
      # Field number is always counter + 1 (ISO 8583 standard)
      field_number = counter + 1
      field = Utils.construct_field(field_number, pad)

      case current do
        1 ->
          format = opts[:formats][field]

          if Keyword.get(opts, :de_detail, false) do
            Logger.debug("Extracting field #{field} with format: #{inspect(format)}")
          end

          {field_data, left} = extract_field_data(field, data, format, opts)

          if Keyword.get(opts, :de_detail, false) do
            Logger.debug("Extracted field #{field}: #{inspect(field_data)}")
          end

          with true <- DataTypes.check_data_length(field, field_data, format),
               true <- DataTypes.valid?(field, field_data, format) do
            extracted = extracted |> Map.put(field, field_data)
            extract_children(rest, left, pad, extracted, counter + 1, opts)
          else
            error ->
              if Keyword.get(opts, :de_detail, false) do
              Logger.error("Error with field #{field}: #{inspect(error)}. Remaining data: #{inspect(data)}")
              end
              error
          end

        0 ->
          extract_children(rest, data, pad, extracted, counter + 1, opts)
      end
    end
  end

  def extract_field_data(_, data, nil, _opts), do: {"", data}

  def extract_field_data(_, data, %{len_type: len_type} = format, opts)
       when len_type == "fixed" do
    if Keyword.get(opts, :de_detail, false) do
      Logger.debug("Extracting fixed length field with length: #{format.max_len}")
    end
    case format.content_type do
      "b" -> Utils.extract_hex_data(data, format.max_len, format.content_type)
      _ -> Utils.extract_text_data(data, format.max_len)
    end
  end

  def extract_field_data(_, data, %{len_type: len_type} = format, opts)
       when len_type in ["llvar", "lllvar", "llllvar"] do
    len_chars = Utils.var_len_chars(format)
    <<len::binary-size(len_chars), rest::binary>> = data
    length = String.to_integer(len)

    if Keyword.get(opts, :de_detail, false) do
      Logger.debug("Extracting variable length field with length: #{length}")
    end

    case format.content_type do
      "b" -> Utils.extract_hex_data(rest, length, format.content_type)
      _ -> Utils.extract_text_data(rest, length)
    end
  end

  def extract_field_data(_, <<>>, _, _opts), do: {"", <<>>}

  # Add this helper function to get list of active fields
  def get_active_fields(bitmap, offset) do
    bitmap
    |> Enum.with_index()
    |> Enum.filter(fn {value, _index} -> value == 1 end)
    |> Enum.map(fn {_value, index} -> index + 1 + offset end)
  end
end
