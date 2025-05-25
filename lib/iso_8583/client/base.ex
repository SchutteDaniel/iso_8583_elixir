defmodule ISO8583.Client.Base do
  @moduledoc """
  Base module for client-specific ISO8583 implementations.
  Each client module should implement this behaviour.
  """
 
  @callback decode_field(field :: String.t(), data :: binary()) :: {:ok, map()} | {:error, String.t()}
  @callback encode_field(field :: String.t(), data :: map()) :: {:ok, binary()} | {:error, String.t()}
end 