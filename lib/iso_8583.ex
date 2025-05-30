defmodule ISO8583 do
  @moduledoc ~S"""
  ISO 8583 messaging library for Elixir. This library has utilities validate, encode and decode message
  between systems using ISO 8583 regadless of the language the other system is written in.

    ```elixir
      message = %{ "0": "0800",  "11": "646465", "12": "160244", "13": "0818", "7": "0818160244","70": "001"}
      {:ok, encoded} = ISO8583.encode(message)
      # {:ok, <<0, 49, 48, 56, 48, 48, 130, 56, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 48, 49, 56, 49, 54, ...>>}
      {:ok, decoded} = ISO8583.decode(encoded)
      # {:ok, %{ "0": "0800",  "11": "646465", "12": "160244", "13": "0818", "7": "0818160244","70": "001"}}
    ```

  ## Installation

    ```elixir
    def deps do
      [
        {:iso_8583, "~> 0.1.2"}
      ]
    end
    ```
  ## Customization and configuration

    All exposed API functions take options with the following configurable options.

    ### TCP Length Indicator
    This is used to specify whether or not to include the 2 byte hexadecimal encoded byte length of the whole message
    whe encoding or to consider it when decoding.
    This value is set to true by default.
    Example:
    ```elixir
    ISO8583.encode(some_message, tcp_len_header: false)
    ```

  ### Bitmap encoding

    Primary and SecondaryBitmap encoding bitmap for fields 0-127 is configurable like below.

    Examples:

    ```elixir
    ISO8583.encode(some_message, bitmap_encoding: :ascii) # will result in 32 byte length bitmap
    ```

    ```elixir
    ISO8583.encode(some_message) # will default to :hex result in 16 byte length bitmap encoded hexadecimal
    ```

  ### Custom formats

    Custom formats for data type, data length and length type for all fields including special bitmaps like
    for 127.1 and 127.25.1 are configurable through custom formats. The default formats will be replaced by the custom one.

    To see the default formats [check here](https://github.com/zemuldo/iso_8583_elixir/blob/master/lib/iso_8583/formats/formats.ex#L104)

    Example:

    Here we override field 2 to have maximum of 30 characters.

    ```elixir
     custome_format = %{
          "2": %{
            content_type: "n",
            label: "Primary account number (PAN)",
            len_type: "llvar",
            max_len: 30,
            min_len: 1
          }
        }

     message = some_message |> Map.put(:"2", "444466668888888888888888")

     ISO8583.encode(message, formats: custome_format)
    ```

  ### Data Element Detail Logging
    Enable detailed logging of data elements during encoding and decoding for debugging purposes.
    This option is disabled by default and uses debug level logging to minimize performance impact.

    Example:
    ```elixir
    ISO8583.encode(some_message, de_detail: true)
    ISO8583.decode(some_message, de_detail: true)
    ```
  """

  import ISO8583.Encode
  alias ISO8583.DataTypes
  import ISO8583.Decode
  alias ISO8583.Formats
  alias ISO8583.Message.ResponseStatus
  alias ISO8583.Utils
  require Logger

  @doc """
  Function to encode json or Elixir map into ISO 8583 encoded binary. Use this to encode all fields that are supported.
  See the formats module for details.
  ## Examples
      iex> message = %{
      iex>   "0": "0800",
      iex>   "7": "0818160244",
      iex>   "11": "646465",
      iex>   "12": "160244",
      iex>   "13": "0818",
      iex>   "70": "001"
      iex> }
      %{
      "0": "0800",
      "11": "646465",
      "12": "160244",
      "13": "0818",
      "7": "0818160244",
      "70": "001"
      }
      iex>ISO8583.encode(message)
      {:ok, <<0, 49, 48, 56, 48, 48, 130, 56, 0, 0, 0, 0,
      0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 48, 56, 49, 56,
      49, 54, 48, 50, 52, 52, 54, 52, 54, 52, 54, 53,
      49, 54, 48, 50, 52, 52, 48, 56, 49, 56, 48, 48,
      49>>}
  """

  @spec encode(message :: map(), opts :: Keyword.t()) :: {:ok, binary()} | {:error, String.t()}
  def encode(message, opts \\ [])

  def encode(message, opts) do
    opts = opts |> default_opts()

    message
    |> Utils.atomify_map()
    |> encode_0_127(opts)
  end

  @doc """
  Function to encode field 127 extensions.
  ## Examples

      iex>message = %{
      iex>"127.1": "0000008000000000",
      iex>"127.25": "7E1E5F7C0000000000000000500000000000000014A00000000310105C000128FF0061F379D43D5AEEBC8002800000000000000001E0302031F000203001406010A03A09000008CE0D0C840421028004880040417091180000014760BAC24959"
      iex>}
      %{
        "127.1": "0000008000000000",
        "127.25": "7E1E5F7C0000000000000000500000000000000014A00000000310105C000128FF0061F379D43D5AEEBC8002800000000000000001E0302031F000203001406010A03A09000008CE0D0C840421028004880040417091180000014760BAC24959"
      }
      iex>ISO8583.encode_127(message)
      {:ok, %{
        "127": "000000800000000001927E1E5F7C0000000000000000500000000000000014A00000000310105C000128FF0061F379D43D5AEEBC8002800000000000000001E0302031F000203001406010A03A09000008CE0D0C840421028004880040417091180000014760BAC24959",
        "127.1": "0000008000000000",
        "127.25": "7E1E5F7C0000000000000000500000000000000014A00000000310105C000128FF0061F379D43D5AEEBC8002800000000000000001E0302031F000203001406010A03A09000008CE0D0C840421028004880040417091180000014760BAC24959"
      }}
  """

  @spec encode_127(message :: map(), opts :: Keyword.t()) ::
          {:ok, binary()} | {:error, String.t()}
  def encode_127(message, opts \\ []) do
    opts = opts |> default_opts()

    message
    |> encoding_extensions(:"127", opts)
  end

  @doc """
  Function to encode field 127.25 extensions.
  ## Examples

      iex>message = %{
      iex>"127.25.1": "7E1E5F7C00000000",
      iex>"127.25.12": "61F379D43D5AEEBC",
      iex>"127.25.13": "80",
      iex>"127.25.14": "00000000000000001E0302031F00",
      iex>"127.25.15": "020300",
      iex>"127.25.18": "06010A03A09000",
      iex>"127.25.2": "000000005000",
      iex>"127.25.20": "008C",
      iex>"127.25.21": "E0D0C8",
      iex>"127.25.22": "404",
      iex>"127.25.23": "21",
      iex>"127.25.24": "0280048800",
      iex>"127.25.26": "404",
      iex>"127.25.27": "170911",
      iex>"127.25.28": "00000147",
      iex>"127.25.29": "60",
      iex>"127.25.3": "000000000000",
      iex>"127.25.30": "BAC24959",
      iex>"127.25.4": "A0000000031010",
      iex>"127.25.5": "5C00",
      iex>"127.25.6": "0128",
      iex>"127.25.7": "FF00"
      iex>}
      %{
        "127.25.1": "7E1E5F7C00000000",
        "127.25.2": "000000005000",
        "127.25.3": "000000000000",
        "127.25.4": "A0000000031010",
        "127.25.5": "5C00",
        "127.25.6": "0128",
        "127.25.7": "FF00",
        "127.25.12": "61F379D43D5AEEBC",
        "127.25.13": "80",
        "127.25.14": "00000000000000001E0302031F00",
        "127.25.15": "020300",
        "127.25.18": "06010A03A09000",
        "127.25.20": "008C",
        "127.25.21": "E0D0C8",
        "127.25.22": "404",
        "127.25.23": "21",
        "127.25.24": "0280048800",
        "127.25.26": "404",
        "127.25.27": "170911",
        "127.25.28": "00000147",
        "127.25.29": "60",
        "127.25.30": "BAC24959"
      }
      iex>ISO8583.encode_127_25(message)
      {:ok, %{
        "127.25": "01927E1E5F7C0000000000000000500000000000000014A00000000310105C000128FF0061F379D43D5AEEBC8002800000000000000001E0302031F000203001406010A03A09000008CE0D0C840421028004880040417091180000014760BAC24959",
        "127.25.1": "7E1E5F7C00000000",
        "127.25.12": "61F379D43D5AEEBC",
        "127.25.13": "80",
        "127.25.14": "00000000000000001E0302031F00",
        "127.25.15": "020300",
        "127.25.18": "06010A03A09000",
        "127.25.2": "000000005000",
        "127.25.20": "008C",
        "127.25.21": "E0D0C8",
        "127.25.22": "404",
        "127.25.23": "21",
        "127.25.24": "0280048800",
        "127.25.26": "404",
        "127.25.27": "170911",
        "127.25.28": "00000147",
        "127.25.29": "60",
        "127.25.3": "000000000000",
        "127.25.30": "BAC24959",
        "127.25.4": "A0000000031010",
        "127.25.5": "5C00",
        "127.25.6": "0128",
        "127.25.7": "FF00"
      }}
  """

  @spec encode_127_25(message :: map(), opts :: Keyword.t()) ::
          {:ok, binary()} | {:error, String.t()}
  def encode_127_25(message, opts \\ []) do
    opts = opts |> default_opts()

    message
    |> encoding_extensions(:"127.25", opts)
  end

  @doc """
  Function to decode an ISO8583 binary using custimizable rules as describe in customization section.
  See the formats module for details.
  ## Examples
      iex> message = <<0, 49, 48, 56, 48, 48, 130, 56, 0, 0, 0, 0,
      iex> 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 48, 56, 49, 56,
      iex> 49, 54, 48, 50, 52, 52, 54, 52, 54, 52, 54, 53,
      iex> 49, 54, 48, 50, 52, 52, 48, 56, 49, 56, 48, 48,
      iex> 49>>
      iex>ISO8583.decode(message)
      {:ok, %{
      "0": "0800",
      "11": "646465",
      "12": "160244",
      "13": "0818",
      "7": "0818160244",
      "70": "001"
      }}
  """

  @spec decode(message :: binary(), opts :: Keyword.t()) :: {:ok, map()} | {:error, String.t()}
  def decode(message, opts \\ []) do
    opts = opts |> default_opts()

    message
    |> decode_0_127(opts)
  end

  @doc """
  Function to expand field 127 to its sub fields.
  ## Examples

      iex>message = %{
      iex>"127": "000000800000000001927E1E5F7C0000000000000000500000000000000014A00000000310105C000128FF0061F379D43D5AEEBC8002800000000000000001E0302031F000203001406010A03A09000008CE0D0C840421028004880040417091180000014760BAC24959"
      iex>}
      %{
          "127": "000000800000000001927E1E5F7C0000000000000000500000000000000014A00000000310105C000128FF0061F379D43D5AEEBC8002800000000000000001E0302031F000203001406010A03A09000008CE0D0C840421028004880040417091180000014760BAC24959"
      }
      iex>ISO8583.decode_127(message)
      {:ok, %{
          "127": "000000800000000001927E1E5F7C0000000000000000500000000000000014A00000000310105C000128FF0061F379D43D5AEEBC8002800000000000000001E0302031F000203001406010A03A09000008CE0D0C840421028004880040417091180000014760BAC24959",
          "127.25": "7E1E5F7C0000000000000000500000000000000014A00000000310105C000128FF0061F379D43D5AEEBC8002800000000000000001E0302031F000203001406010A03A09000008CE0D0C840421028004880040417091180000014760BAC24959"
       }}
  """

  @spec decode_127(message :: binary(), opts :: Keyword.t()) ::
          {:ok, map()} | {:error, String.t()}
  def decode_127(message, opts \\ [])

  def decode_127(message, opts) when is_binary(message) do
    opts = opts |> default_opts()

    message
    |> expand_field("127.", opts)
  end

  def decode_127(message, opts) do
    opts = opts |> default_opts()

    message
    |> expand_field("127.", opts)
  end

  @doc """
  Function to expand field 127.25 to its sub fields
  ## Examples

      iex>message = %{
      iex>"127": "000000800000000001927E1E5F7C0000000000000000500000000000000014A00000000310105C000128FF0061F379D43D5AEEBC8002800000000000000001E0302031F000203001406010A03A09000008CE0D0C840421028004880040417091180000014760BAC24959",
      iex>"127.25": "7E1E5F7C0000000000000000500000000000000014A00000000310105C000128FF0061F379D43D5AEEBC8002800000000000000001E0302031F000203001406010A03A09000008CE0D0C840421028004880040417091180000014760BAC24959"
      iex>}
      %{
          "127": "000000800000000001927E1E5F7C0000000000000000500000000000000014A00000000310105C000128FF0061F379D43D5AEEBC8002800000000000000001E0302031F000203001406010A03A09000008CE0D0C840421028004880040417091180000014760BAC24959",
          "127.25": "7E1E5F7C0000000000000000500000000000000014A00000000310105C000128FF0061F379D43D5AEEBC8002800000000000000001E0302031F000203001406010A03A09000008CE0D0C840421028004880040417091180000014760BAC24959"
      }
      iex>ISO8583.decode_127_25(message)
      {:ok, %{
        "127": "000000800000000001927E1E5F7C0000000000000000500000000000000014A00000000310105C000128FF0061F379D43D5AEEBC8002800000000000000001E0302031F000203001406010A03A09000008CE0D0C840421028004880040417091180000014760BAC24959",
        "127.25": "7E1E5F7C0000000000000000500000000000000014A00000000310105C000128FF0061F379D43D5AEEBC8002800000000000000001E0302031F000203001406010A03A09000008CE0D0C840421028004880040417091180000014760BAC24959",
        "127.25.12": "61F379D43D5AEEBC",
        "127.25.13": "80",
        "127.25.14": "00000000000000001E0302031F00",
        "127.25.15": "020300",
        "127.25.18": "06010A03A09000",
        "127.25.2": "000000005000",
        "127.25.20": "008C",
        "127.25.21": "E0D0C8",
        "127.25.22": "404",
        "127.25.23": "21",
        "127.25.24": "0280048800",
        "127.25.26": "404",
        "127.25.27": "170911",
        "127.25.28": "00000147",
        "127.25.29": "60",
        "127.25.3": "000000000000",
        "127.25.30": "BAC24959",
        "127.25.4": "A0000000031010",
        "127.25.5": "5C00",
        "127.25.6": "0128",
        "127.25.7": "FF00"
      }}
  """

  @spec decode_127_25(message :: binary(), opts :: Keyword.t()) ::
          {:ok, map()} | {:error, String.t()}
  def decode_127_25(message, opts \\ []) do
    opts = opts |> default_opts()

    message
    |> expand_field("127.25.", opts)
  end

  @doc """
  Function check if json message is valid.
  ## Examples
      iex> message = %{
      iex>   "0": "0800",
      iex>   "7": "0818160244",
      iex>   "11": "646465",
      iex>   "12": "160244",
      iex>   "13": "0818",
      iex>   "70": "001"
      iex> }
      %{
      "0": "0800",
      "11": "646465",
      "12": "160244",
      "13": "0818",
      "7": "0818160244",
      "70": "001"
      }
      iex>ISO8583.valid?(message)
      true
      iex> message = <<0, 49, 48, 56, 48, 48, 130, 56, 0, 0, 0, 0,
      iex> 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 48, 56, 49, 56,
      iex> 49, 54, 48, 50, 52, 52, 54, 52, 54, 52, 54, 53,
      iex> 49, 54, 48, 50, 52, 52, 48, 56, 49, 56, 48, 48,
      iex> 49>>
      iex>ISO8583.valid?(message)
      true
  """

  @spec valid?(message :: binary() | map(), opts :: Keyword.t()) :: true | false
  def valid?(message, opts \\ [])

  def valid?(message, opts) when is_map(message) do
    opts = opts |> default_opts()

    with atomified <- Utils.atomify_map(message),
         {:ok, _} <- DataTypes.valid?(atomified, opts) do
      true
    else
      _ -> false
    end
  end

  def valid?(message, opts) when is_binary(message) do
    opts = opts |> default_opts()

    case decode(message, opts) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Function check if json message is valid.
  ## Examples
      iex> message = %{
      iex>   "0": "0800",
      iex>   "7": "0818160244",
      iex>   "11": "646465",
      iex>   "12": "160244",
      iex>   "13": "0818",
      iex>   "70": "001"
      iex> }
      %{
      "0": "0800",
      "11": "646465",
      "12": "160244",
      "13": "0818",
      "7": "0818160244",
      "70": "001"
      }
      iex>ISO8583.valid(message)
      {:ok, message}
      iex> message = <<0, 49, 48, 56, 48, 48, 130, 56, 0, 0, 0, 0,
      iex> 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 48, 56, 49, 56,
      iex> 49, 54, 48, 50, 52, 52, 54, 52, 54, 52, 54, 53,
      iex> 49, 54, 48, 50, 52, 52, 48, 56, 49, 56, 48, 48,
      iex> 49>>
      iex>ISO8583.valid(message)
      {:ok, %{
      "0": "0800",
      "11": "646465",
      "12": "160244",
      "13": "0818",
      "7": "0818160244",
      "70": "001"
      }}
  """
  @spec valid(message :: map() | binary(), opts :: Keyword.t()) ::
          {:ok, map()} | {:error, String.t()}
  def valid(message, opts \\ [])

  def valid(message, opts) when is_map(message) do
    opts = opts |> default_opts()

    message
    |> Utils.atomify_map()
    |> DataTypes.valid?(opts)
  end

  def valid(message, opts) when is_binary(message) do
    opts = opts |> default_opts()

    message |> decode(opts)
  end

  @doc """
  Function to get the message status.
  ## Examples

      iex> ISO8583.status(%{"0": "0110", "39": "00"})
      {:ok, "Approved or completed successfully"}
      iex> ISO8583.status(%{"0": "0110", "39": "01"})
      {:error, "Refer to card issuer"}
      iex> ISO8583.status(%{"0": "0110", "39": "000"})
      {:error, "Unknown statuscode"}
  """
  @spec status(message: map()) :: {:ok, String.t()} | {:error, String.t()}
  def status(message) when is_map(message) do
    message
    |> ResponseStatus.ok?()
  end

  def status(_), do: {:error, "Message has to be a map with field 39"}

  @doc """
  Function to decode a specific field using client-specific implementation.
  ## Examples

      iex> message = %{
      iex>   "120": "001003ABC045004JOHN07000512345"
      iex> }
      iex> ISO8583.decode_field("ppn", "120", message)
      {:ok, %{
          "120": "001003ABC045004JOHN07000512345",
          "120.1": "ABC",
          "120.45": "JOHN",
          "120.70": "12345"
      }}

      iex> ISO8583.decode_field("ppn", "120", "001003ABC045004JOHN07000512345")
      {:ok, %{
          "120.1": "ABC",
          "120.45": "JOHN",
          "120.70": "12345"
      }}
  """
  @spec decode_field(client :: String.t(), field :: String.t(), message :: map() | String.t(), opts :: Keyword.t()) ::
          {:ok, map()} | {:error, String.t()}

  def decode_field(client, field, message, opts \\ [])
  
  def decode_field(client, field, message, opts) when is_map(message) do
    opts = opts |> default_opts()

    client_module = get_client_module(client)
    field_key = if is_integer(field), do: Integer.to_string(field), else: field
    
    Logger.debug("Decoding field #{field_key} from map: #{inspect(message)}")
    
    # Try both string and atom keys
    data = case Map.get(message, field_key) do
      nil -> Map.get(message, String.to_atom(field_key))
      value -> value
    end
    
    case data do
      nil -> 
        Logger.debug("Field #{field_key} not found in message")
        {:ok, message}
      value -> 
        Logger.debug("Found field #{field_key} with data: #{inspect(value)}")
        case client_module.decode_field(field, value) do
          {:ok, sub_fields} -> 
            Logger.debug("Successfully decoded sub-fields: #{inspect(sub_fields)}")
            # Convert sub-field keys to atoms
            atomized_sub_fields = Map.new(sub_fields, fn {k, v} -> 
              {String.to_atom(k), v}
            end)
            result = Map.merge(message, atomized_sub_fields)
            Logger.debug("Final merged result: #{inspect(result)}")
            {:ok, result}
          error -> 
            Logger.error("Error decoding field #{field_key}: #{inspect(error)}")
            error
        end
    end
  end

  def decode_field(client, field, data, opts) when is_binary(data) do
    opts = opts |> default_opts()

    client_module = get_client_module(client)
    field_key = if is_integer(field), do: Integer.to_string(field), else: field
    Logger.debug("Decoding field #{field_key} from binary data: #{inspect(data)}")
    
    case client_module.decode_field(field, data) do
      {:ok, sub_fields} -> 
        Logger.debug("Successfully decoded sub-fields: #{inspect(sub_fields)}")
        # Convert sub-field keys to atoms
        atomized_sub_fields = Map.new(sub_fields, fn {k, v} -> 
          {String.to_atom(k), v}
        end)
        {:ok, atomized_sub_fields}
      error -> 
        Logger.error("Error decoding field #{field_key}: #{inspect(error)}")
        error
    end
  end

  @doc """
  Function to encode a specific field using client-specific implementation.
  ## Examples

      iex> message = %{
      iex>   "120.1": "ABC",
      iex>   "120.45": "JOHN",
      iex>   "120.70": "12345"
      iex> }
      iex> ISO8583.encode_field("ppn", "120", message)
      {:ok, %{
          "120": "001003ABC045004JOHN07000512345",
          "120.1": "ABC",
          "120.45": "JOHN",
          "120.70": "12345"
      }}
  """
  @spec encode_field(client :: String.t(), field :: String.t(), message :: map(), opts :: Keyword.t()) ::
          {:ok, map()} | {:error, String.t()}
  def encode_field(client, field, message, opts \\ []) do
    opts = opts |> default_opts()

    client_module = get_client_module(client)
    field_key = if is_integer(field), do: Integer.to_string(field), else: field
    field_atom = String.to_atom(field_key)

    Logger.debug("ISO8583: Starting encode_field for field #{field_key}")
    Logger.debug("ISO8583: Original message: #{inspect(message)}")

    # First, remove any existing field data
    message = Map.delete(message, field_atom)
    Logger.debug("ISO8583: Message after removing existing field: #{inspect(message)}")

    # Then process the sub-fields
    sub_fields = message
    |> Map.take(client_module.get_sub_fields(field))
    |> Map.new(fn {k, v} -> 
      key = if is_atom(k), do: Atom.to_string(k), else: k
      {String.replace(key, "#{field}.", ""), v}
    end)

    Logger.debug("ISO8583: Processed sub-fields: #{inspect(sub_fields)}")

    case client_module.encode_field(field, sub_fields) do
      {:ok, field_data} -> 
        Logger.debug("ISO8583: Received field data: #{inspect(field_data)}")
        # Only add the field data if it's not empty
        result = if field_data == "", do: message, else: Map.put(message, field_atom, field_data)
        Logger.debug("ISO8583: Final result: #{inspect(result)}")
        {:ok, result}
      error -> 
        Logger.error("ISO8583: Error encoding field: #{inspect(error)}")
        error
    end
  end

  # Helper function to get client module
  defp get_client_module("ppn"), do: ISO8583.Client.PPN
  defp get_client_module(client), do: raise "Unknown client: #{client}"

  defp default_opts([]) do
    [bitmap_encoding: :hex, tcp_len_header: true, formats: Formats.formats_definitions(), de_detail: false, format_strategy: :merge]
  end

  defp default_opts(opts) do
    default_opts([])
    |> Keyword.merge(opts)
    |> configure_formats()
  end

  defp configure_formats(opts) do
    formats = case opts[:formats] do
      func when is_function(func) -> func.()
      map when is_map(map) -> map
      _ -> Formats.formats_definitions()
    end

    case opts[:format_strategy] do
      :replace ->
        # Use the provided formats directly, replacing all default formats
        opts
        |> Keyword.merge(formats: formats |> Utils.atomify_map())

      :merge ->
        # Merge the provided formats with the default formats
        formats_with_customs =
          Formats.formats_definitions()
          |> Map.merge(formats |> Utils.atomify_map())

        opts
        |> Keyword.merge(formats: formats_with_customs)

      _ ->
        # Default to merge strategy if unknown strategy is provided
        formats_with_customs =
          Formats.formats_definitions()
          |> Map.merge(formats |> Utils.atomify_map())

        opts
        |> Keyword.merge(formats: formats_with_customs)
    end
  end

  @doc """
  Logs data element details if de_detail option is enabled.
  """
  defp log_de_detail(field, value, format, opts) do
    if Keyword.get(opts, :de_detail, false) do
      Logger.debug("DE#{field}: #{inspect(value)} - Format: #{inspect(format)}")
    end
  end

  @doc """
  Logs data element error details if de_detail option is enabled.
  """
  defp log_de_error(field, error, opts) do
    if Keyword.get(opts, :de_detail, false) do
      Logger.debug("DE#{field} Error: #{inspect(error)}")
    end
  end
end
