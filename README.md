# ISO8583

An ISO 8583 messaging library for Elixir. Supports message validation, encoding and decoding. [See the docs](https://hexdocs.pm/iso_8583)

This project is still in early stages. If you have feature suggestions you can do two things.

- Push a PR and I will be happy to review.
- Suggest using new issue and I will be happy to implement.

```elixir
iex> message
%{
  "0": "0800",
  "11": "646465",
  "12": "160244",
  "13": "0818",
  "7": "0818160244",
  "70": "001"
}
iex> {:ok, encoded} = ISO8583.encode(message)
{:ok,
 <<0, 49, 48, 56, 48, 48, 130, 56, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 48,
   56, 49, 56, 49, 54, 48, 50, 52, 52, 54, 52, 54, 52, 54, 53, 49, 54, 48, 50,
   52, 52, 48, 56, 49, 56, ...>>}
iex> {:ok, decoded} = ISO8583.decode(encoded)
{:ok,
 %{
   "0": "0800",
   "11": "646465",
   "12": "160244",
   "13": "0818",
   "7": "0818160244",
   "70": "001"
 }}
iex>
```

## Installation

```elixir
def deps do
  [
    {:iso_8583, "~> 0.1.2"}
  ]
end
```

## Configuration Options

All exposed API functions take options with the following configurable parameters:
  
### TCP Length Header (`tcp_len_header`)
Controls whether to include the 2-byte hexadecimal encoded byte length of the whole message when encoding or to consider it when decoding.
- Default: `true`
- Example:
  ```elixir
  ISO8583.encode(message, tcp_len_header: false)
  ```

### Bitmap Encoding (`bitmap_encoding`)
Configures how the primary and secondary bitmaps for fields 0-127 are encoded.
- Options: `:hex` (default) or `:ascii`
- `:hex` results in 16-byte length bitmap
- `:ascii` results in 32-byte length bitmap
- Example:
  ```elixir
ISO8583.encode(message, bitmap_encoding: :ascii)
```

### Format Strategy (`format_strategy`)
Controls how custom formats are applied to the default formats.
- Options: `:merge` (default) or `:replace`
- `:merge` - Combines custom formats with default formats, with custom formats taking precedence
- `:replace` - Completely replaces default formats with custom formats
- Example:
  ```elixir
# Merge custom formats with defaults
ISO8583.encode(message, formats: custom_formats, format_strategy: :merge)

# Replace all default formats
ISO8583.encode(message, formats: custom_formats, format_strategy: :replace)
  ```

### Custom Formats (`formats`)
Allows customization of data type, length, and format for all fields including special bitmaps.
- Default: Uses `ISO8583.Formats.formats_definitions()`
- Can be merged with or replace default formats based on `format_strategy`
- Example:
  ```elixir
custom_formats = %{
        "2": %{
          content_type: "n",
          label: "Primary account number (PAN)",
          len_type: "llvar",
          max_len: 30,
          min_len: 1
        }
      }

ISO8583.encode(message, formats: custom_formats)
```

### Data Element Detail Logging (`de_detail`)
Enables detailed logging of data elements during encoding and decoding for debugging purposes.
- Default: `false`
- Uses debug level logging to minimize performance impact
- Example:
```elixir
ISO8583.encode(message, de_detail: true)
ISO8583.decode(message, de_detail: true)
```

## Field Format Structure

Each field in the format definition can have the following properties:

- `content_type`: Data type of the field
  - `"n"` - Numeric
  - `"a"` - Alphabetic
  - `"an"` - Alphanumeric
  - `"ans"` - Alphanumeric with special characters
  - `"b"` - Binary
  - `"z"` - Track data
  - `"x+n"` - Extended numeric
  - `"ns"` - Numeric with special characters
  - `"anp"` - Alphanumeric with padding

- `label`: Human-readable description of the field
- `len_type`: Length type of the field
  - `"fixed"` - Fixed length
  - `"llvar"` - Variable length with 2-digit length indicator
  - `"lllvar"` - Variable length with 3-digit length indicator
  - `"llllvar"` - Variable length with 4-digit length indicator
  - `"llllllvar"` - Variable length with 6-digit length indicator

- `max_len`: Maximum length of the field
- `min_len`: (Optional) Minimum length of the field
- `padding`: (Optional) Padding configuration
  - `direction`: `:left` or `:right`
  - `char`: Character to use for padding
- `validation`: (Optional) Validation rules
  - `regex`: Regular expression pattern for validation
  
  ## Roadmap
  - Optimizations
  - More customizations
  - Message composition
- Support for composable validators
- More tests
