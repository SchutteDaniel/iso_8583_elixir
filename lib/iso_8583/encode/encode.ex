defmodule ISO8583.Encode do
  @moduledoc false

  alias ISO8583.Bitmap
  alias ISO8583.Decode
  alias ISO8583.Message.StaticMeta
  alias ISO8583.Utils

  require Logger

  def encode_0_127(message, opts) do
    with m <- extend_encode_etxtensions(message, opts),
         {:ok, _, with_mti} <- encode_mti(message),
         bitmap_hex <- Bitmap.fields_0_127(m),
         {:ok, with_bitmap} <- encode_bitmap(bitmap_hex, with_mti, opts),
         bitmap_list <- Utils.iterable_bitmap(bitmap_hex, 128),
         {:ok, with_data} <- loop_bitmap(bitmap_list, m, with_bitmap, <<>>, 0, opts),
         {:ok, with_static_meta} <- StaticMeta.put(with_data, opts[:static_meta]),
         with_tcpe_header <- encode_tcp_header(with_static_meta, opts) do
      {:ok, with_tcpe_header}
    else
      error -> error
    end
  end

  defp extend_encode_etxtensions(message, opts) do
    message =
      message
      |> Map.put(:"1", Bitmap.fields_0_127(message))

    with {:ok, expanded_127} <- Decode.expand_field(message, "127.", opts),
         {:ok, expanded_127_25} <- Decode.expand_field(expanded_127, "127.25.", opts),
         {:ok, m1} <- encoding_extensions(expanded_127_25, :"127.25", opts),
         {:ok, m2} <- encoding_extensions(m1, :"127", opts) do
      {:ok, Map.merge(message, %{"127.25": m2})}
    else
      error -> error
    end
  end

  defp encode_tcp_header(encoded, opts) do
    case opts[:tcp_len_header] do
      true -> Utils.encode_tcp_header(encoded)
      false -> encoded
    end
  end

  defp encode_mti(m) do
    {:ok, m, m[:"0"]}
  end

  @spec encode_bitmap(binary(), binary(), nil | maybe_improper_list() | map()) :: {:ok, binary()}
  def encode_bitmap(bitmap_hex, encoded, opts) do
    case opts[:bitmap_encoding] do
      :hex ->
        {:ok, encoded <> bitmap_hex }
      _ ->
        {:ok, encoded |> Kernel.<>(bitmap_hex |> Utils.hex_to_bytes())}
    end
  end

  def encoding_extensions(%{"127.25.1": _} = message, :"127.25", opts) do
    bitmap =
      message[:"127.25.1"]
      |> Utils.iterable_bitmap(64)

    with {:ok, encoded} <- loop_bitmap(bitmap, message, message[:"127.25.1"], "127.25.", 0, opts),
         {:ok, with_length} <-
           encode_length_indicator(encoded, "127.25", opts[:formats][:"127.25"]) do
      {:ok, Map.merge(message, %{"127.25": with_length})}
    else
      error -> error
    end
  end

  def encoding_extensions(%{"127.1": data} = message, :"127", opts) do
    with bitmap <- Utils.iterable_bitmap(data, 64),
         {:ok, encoded} <- loop_bitmap(bitmap, message, message[:"127.1"], "127.", 0, opts) do
      {:ok, Map.merge(message, %{"127": encoded})}
    else
      error -> error
    end
  end

  def encoding_extensions(message, _, _), do: message

  defp loop_bitmap([], _, encoded, _, _, _), do: {:ok, encoded}

  defp loop_bitmap(bitmap, message, encoded, field_pad, counter, opts) do
    [current | rest_bitmaps] = bitmap
    if counter == 0 or counter == 63 do
      loop_bitmap(rest_bitmaps, message, encoded, field_pad, counter + 1, opts)
    else
      case current do
        1 ->
          field = Utils.construct_field(counter + 1, field_pad)
          data = message[field]

          case encode_field(field, data, opts) do
            {:error, message} ->
              {:error, message}

            {:ok, data_encoded} ->
              loop_bitmap(
                rest_bitmaps,
                message,
                encoded <> data_encoded,
                field_pad,
                counter + 1,
                opts
              )
          end

        0 ->
          loop_bitmap(rest_bitmaps, message, encoded, field_pad, counter + 1, opts)
      end
    end
  end

  defp encode_field(field, data, opts) do
    format = opts[:formats][field]
    Logger.debug("ENCODE_FIELD - Field: #{inspect(field)}, Data: #{inspect(data)}, Format: #{inspect(format)}")
    with {:ok, _} <- validate_field(data, format, field),
         {:ok, padded_data} <- apply_padding(data, format),
         {:ok, encoded_data} <- encode_length_indicator(padded_data, field, format) do
      {:ok, encoded_data}
    end
  end

  defp validate_field(nil, _format, _field), do: {:ok, nil}
  defp validate_field(data, %{validation: %{regex: regex}} = format, field) do
    Logger.debug("VALIDATE_FIELD - Field: #{inspect(field)}, Data: #{inspect(data)}, Format: #{inspect(format)}, Regex: #{inspect(regex)}")
    regex_str = if is_binary(regex), do: regex, else: Regex.source(regex)
    compiled_regex = if is_binary(regex), do: Regex.compile!(regex), else: regex

    case Regex.match?(compiled_regex, data) do
      true ->
        Logger.debug("VALIDATION PASSED")
        {:ok, data}
      false ->
        Logger.debug("VALIDATION FAILED")
        {:error, "Field #{field}: value '#{data}' does not match validation rule (regex: #{regex_str})"}
    end
  end
  defp validate_field(data, format, field) do
    Logger.debug("VALIDATE_FIELD FALLBACK - Field: #{inspect(field)}, Data: #{inspect(data)}, Format: #{inspect(format)}")
    {:ok, data}
  end

  defp apply_padding(nil, _format), do: {:ok, nil}
  defp apply_padding(data, %{padding: %{direction: direction, char: char}} = format) do
    case format.len_type do
      "fixed" ->
        padded = case direction do
          :left -> String.pad_leading(data, format.max_len, char)
          :right -> String.pad_trailing(data, format.max_len, char)
        end
        {:ok, padded}
      _ -> {:ok, data}
    end
  end
  defp apply_padding(data, _format), do: {:ok, data}

  defp encode_length_indicator(data, field, %{len_type: len_type} = format)
       when len_type == "fixed" do
    Logger.info("encode_length_indicator data: #{inspect(data)} field: #{inspect(field)}")
    case byte_size(data) > format.max_len do
      true ->
        {:error,
         "Invalid length of data on field #{field}, expected #{format.max_len}, but got #{
           byte_size(data)
         }"}

      false ->
        {:ok, data |> encode_data(format.content_type)}
    end
  end

  defp encode_length_indicator(data, field, format) do
    case byte_size(data) > format.max_len do
      true ->
        {:error,
         "Invalid length of data on field #{field}, expected maximum of #{format.max_len}, but got #{
           byte_size(data)
         }"}

      false ->
        max_len_chars = format |> get_len_type |> byte_size()

        {:ok,
         byte_size(data)
         |> Integer.to_string()
         |> Utils.padd_chars(max_len_chars, "0")
         |> Kernel.<>(data |> encode_data(format.content_type))}
    end
  end

  defp encode_data(data, content_type) do
    case content_type do
      "b" -> Utils.hex_to_bytes(data)
      _ -> data
    end
  end

  defp get_len_type(%{len_type: len_type}) do
    [type | _] = len_type |> String.split("var")
    type
  end
end
