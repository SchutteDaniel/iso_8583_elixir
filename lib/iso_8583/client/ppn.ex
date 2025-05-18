defmodule ISO8583.Client.PPN do
  @moduledoc """
  PPN-specific implementation of ISO8583 client.
  """

  @behaviour ISO8583.Client.Base
  require Logger

  @impl true
  def decode_field("120", data), do: decode_field(120, data)
  def decode_field(120, data) when is_binary(data) do
    Logger.debug("PPN: Decoding field 120 from binary data: #{inspect(data)}")
    ISO8583.Client.PPN.DE120.unpack_de120(data)
  end
  def decode_field(120, data) when is_map(data) do
    Logger.debug("PPN: Decoding field 120 from map: #{inspect(data)}")
    # Try both string and atom keys
    value = case Map.get(data, "120") do
      nil -> Map.get(data, :"120")
      v -> v
    end
    
    case value do
      nil -> 
        Logger.debug("PPN: Field 120 not found in map")
        {:ok, data}
      value when is_binary(value) -> 
        Logger.debug("PPN: Found field 120 with value: #{inspect(value)}")
        case ISO8583.Client.PPN.DE120.unpack_de120(value) do
          {:ok, sub_fields} -> 
            Logger.debug("PPN: Successfully decoded sub-fields: #{inspect(sub_fields)}")
            {:ok, sub_fields}
          error -> 
            Logger.error("PPN: Error decoding field 120: #{inspect(error)}")
            error
        end
      _ -> 
        Logger.error("PPN: Invalid DE120 data format")
        {:error, "Invalid DE120 data format"}
    end
  end

  def decode_field(field, _data) when is_binary(field) do
    {:error, "Field #{field} not implemented for PPN client"}
  end
  def decode_field(field, _data) when is_integer(field) do
    {:error, "Field #{field} not implemented for PPN client"}
  end

  @impl true
  def encode_field("120", sub_fields), do: encode_field(120, sub_fields)
  def encode_field(120, sub_fields) do
    Logger.debug("PPN: Encoding field 120 with sub-fields: #{inspect(sub_fields)}")
    # Convert atom keys back to strings for encoding
    string_sub_fields = Map.new(sub_fields, fn {k, v} -> 
      {if(is_atom(k), do: Atom.to_string(k), else: k), v}
    end)
    ISO8583.Client.PPN.DE120.pack_de120(string_sub_fields)
  end

  def encode_field(field, _sub_fields) when is_binary(field) do
    {:error, "Field #{field} not implemented for PPN client"}
  end
  def encode_field(field, _sub_fields) when is_integer(field) do
    {:error, "Field #{field} not implemented for PPN client"}
  end

  @doc """
  Returns the list of sub-fields for a given field.
  """
  def get_sub_fields("120"), do: get_sub_fields(120)
  def get_sub_fields(120) do
    [
      :"120.1", :"120.45", :"120.46", :"120.47", :"120.50", 
      :"120.56", :"120.62", :"120.70", :"120.71", :"120.72", 
      :"120.73", :"120.74", :"120.75"
    ]
  end
  def get_sub_fields(_), do: []
end 