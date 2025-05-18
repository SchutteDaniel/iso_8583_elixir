defmodule ISO8583.Client.PPN do
  @moduledoc """
  PPN-specific implementation of ISO8583 client.
  """

  @behaviour ISO8583.Client.Base

  @impl true
  def decode_field("120", data) do
    ISO8583.Client.PPN.DE120.unpack_de120(data)
  end

  def decode_field(field, _data) do
    {:error, "Field #{field} not implemented for PPN client"}
  end

  @impl true
  def encode_field("120", sub_fields) do
    ISO8583.Client.PPN.DE120.pack_de120(sub_fields)
  end

  def encode_field(field, _sub_fields) do
    {:error, "Field #{field} not implemented for PPN client"}
  end

  @doc """
  Returns the list of sub-fields for a given field.
  """
  def get_sub_fields("120") do
    [
      "120.1", "120.45", "120.46", "120.47", "120.50", 
      "120.56", "120.62", "120.70", "120.71", "120.72", 
      "120.73", "120.74", "120.75"
    ]
  end
  def get_sub_fields(_), do: []
end 