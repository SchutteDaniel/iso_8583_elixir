defmodule ISO8583.Client.PPN.DE120 do
  @moduledoc """
  PPN-specific implementation for handling DE120 field.
  """

  require Logger

  @doc """
  Unpacks DE120 into its constituent sub-fields.
  Returns a map with the sub-field codes as keys and their values.
  """
  def unpack_de120(de120) when is_binary(de120) do
    de120(de120, %{})
  end

  # Transaction Type (45)
  defp de120(<<"001", len::binary-size(3), rest::binary>>, result) do
    length = String.to_integer(len)
    <<de::binary-size(length), data::binary>> = rest
    Logger.info(%{de: {120, 1}, value: de})
    de120(data, Map.put(result, "120.1", de))
  end

  # Remitter Name
  defp de120(<<"045", len::binary-size(3), rest::binary>>, result) do
    length = String.to_integer(len)
    <<de::binary-size(length), data::binary>> = rest
    Logger.info(%{de: {120, 45}, value: de})
    de120(data, Map.put(result, "120.45", de))
  end

  # Remitter Address
  defp de120(<<"070", len::binary-size(3), rest::binary>>, result) do
    length = String.to_integer(len)
    <<de::binary-size(length), data::binary>> = rest
    Logger.info(%{de: {120, 70}, value: de})
    de120(data, Map.put(result, "120.70", de))
  end

  # Remitter SWIFT Code (BIC)
  defp de120(<<"071", len::binary-size(3), rest::binary>>, result) do
    length = String.to_integer(len)
    <<de::binary-size(length), data::binary>> = rest
    Logger.info(%{de: {120, 71}, value: de})
    de120(data, Map.put(result, "120.71", de))
  end

  # Beneficiary Name
  defp de120(<<"046", len::binary-size(3), rest::binary>>, result) do
    length = String.to_integer(len)
    <<de::binary-size(length), data::binary>> = rest
    Logger.info(%{de: {120, 46}, value: de})
    de120(data, Map.put(result, "120.46", de))
  end

  # Beneficiary Address
  defp de120(<<"072", len::binary-size(3), rest::binary>>, result) do
    length = String.to_integer(len)
    <<de::binary-size(length), data::binary>> = rest
    Logger.info(%{de: {120, 72}, value: de})
    de120(data, Map.put(result, "120.72", de))
  end

  # Beneficiary SWIFT Code (BIC)
  defp de120(<<"073", len::binary-size(3), rest::binary>>, result) do
    length = String.to_integer(len)
    <<de::binary-size(length), data::binary>> = rest
    Logger.info(%{de: {120, 73}, value: de})
    de120(data, Map.put(result, "120.73", de))
  end

  # Beneficiary Account Number
  defp de120(<<"062", len::binary-size(3), rest::binary>>, result) do
    length = String.to_integer(len)
    <<de::binary-size(length), data::binary>> = rest
    Logger.info(%{de: {120, 62}, value: de})
    de120(data, Map.put(result, "120.62", de))
  end

  # Transaction Reason
  defp de120(<<"074", len::binary-size(3), rest::binary>>, result) do
    length = String.to_integer(len)
    <<de::binary-size(length), data::binary>> = rest
    Logger.info(%{de: {120, 74}, value: de})
    de120(data, Map.put(result, "120.74", de))
  end

  # Remitter Transaction Reference
  defp de120(<<"075", len::binary-size(3), rest::binary>>, result) do
    length = String.to_integer(len)
    <<de::binary-size(length), data::binary>> = rest
    Logger.info(%{de: {120, 75}, value: de})
    de120(data, Map.put(result, "120.75", de))
  end

  # Remitter Proc Info (fixed length of 15)
  defp de120(<<"050", len::binary-size(3), rest::binary>>, result) do
    length = String.to_integer(len)
    <<de::binary-size(length), data::binary>> = rest
    Logger.info(%{de: {120, 50}, value: de})
    de120(data, Map.put(result, "120.50", de))
  end

  # Channel Indicator (fixed length of 3)
  defp de120(<<"056", len::binary-size(3), rest::binary>>, result) do
    length = String.to_integer(len)
    <<de::binary-size(length), data::binary>> = rest
    Logger.info(%{de: {120, 56}, value: de})
    de120(data, Map.put(result, "120.56", de))
  end

  # Original Transaction Detail (fixed length of 36)
  defp de120(<<"047", len::binary-size(3), rest::binary>>, result) do
    length = String.to_integer(len)
    <<de::binary-size(length), data::binary>> = rest
    Logger.info(%{de: {120, 47}, value: de})
    de120(data, Map.put(result, "120.47", de))
  end

  # End of processing
  defp de120(<<>>, result) do
    Logger.info(%{de: 120, step: :done})
    {:ok, result}
  end

  # Error case
  defp de120(de, result) do
    Logger.error(%{de120: de, error: :invalid_data})
    {:error, {de, result}}
  end

  @doc """
  Packs sub-fields back into DE120 format.
  ## Examples

      iex> sub_fields = %{
      iex>   "120.1": "ABC",
      iex>   "120.45": "JOHN",
      iex>   "120.70": "12345"
      iex> }
      iex> ISO8583.Client.PPN.DE120.pack_de120(sub_fields)
      {:ok, "001003ABC045004JOHN07000512345"}
  """
  @spec pack_de120(sub_fields :: map()) :: {:ok, String.t()} | {:error, String.t()}
  def pack_de120(sub_fields) do
    try do
      Logger.debug("DE120: Starting pack_de120 with sub-fields: #{inspect(sub_fields)}")

      # Define the order of fields with their corresponding field IDs
      field_order = [
        {"1", "001"},
        {"45", "045"},
        {"46", "046"},
        {"47", "047"},
        {"50", "050"},
        {"56", "056"},
        {"62", "062"},
        {"70", "070"},
        {"71", "071"},
        {"72", "072"},
        {"73", "073"},
        {"74", "074"},
        {"75", "075"}
      ]

      Logger.debug("DE120: Processing fields in order: #{inspect(field_order)}")

      result = field_order
      |> Enum.map(fn {key, field_id} ->
        Logger.debug("DE120: Processing field #{key} with ID #{field_id}")
        # Look up the key with the "120." prefix
        case Map.get(sub_fields, "120.#{key}") do
          nil -> 
            # Try without the prefix
            case Map.get(sub_fields, key) do
              nil -> 
                Logger.debug("DE120: No value found for field #{key}")
                nil
              value -> 
                Logger.debug("DE120: Found value for field #{key} without prefix: #{inspect(value)}")
                len = String.length(value)
                "#{field_id}#{String.pad_leading("#{len}", 3, "0")}#{value}"
            end
          value -> 
            Logger.debug("DE120: Found value for field #{key} with prefix: #{inspect(value)}")
            len = String.length(value)
            "#{field_id}#{String.pad_leading("#{len}", 3, "0")}#{value}"
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join()

      Logger.debug("DE120: Final packed result: #{inspect(result)}")
      {:ok, result}
    rescue
      e ->
        Logger.error("DE120: Error packing DE120: #{inspect(e)}")
        {:error, "Failed to pack DE120: #{inspect(e)}"}
    end
  end
end 