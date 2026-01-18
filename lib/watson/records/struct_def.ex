defmodule Watson.Records.StructDef do
  @moduledoc """
  Represents a struct definition.
  """

  @behaviour Watson.Records.Record

  defstruct [
    :module,
    :file,
    :span,
    fields: []
  ]

  @type field :: %{
          name: String.t(),
          default: String.t() | nil
        }

  @type t :: %__MODULE__{
          module: String.t(),
          file: String.t(),
          span: Watson.Records.Record.line_span(),
          fields: [field()]
        }

  @impl true
  def kind, do: "struct_def"

  @impl true
  def to_map(%__MODULE__{} = record) do
    %{
      module: record.module,
      file: record.file,
      span: record.span,
      fields: record.fields
    }
  end

  @doc """
  Creates a new StructDef record.
  """
  def new(module, file, line, fields \\ []) do
    %__MODULE__{
      module: module,
      file: file,
      span: Watson.Records.Record.line_span(line),
      fields: fields
    }
  end

  @doc """
  Creates a field map.
  """
  def field(name, default \\ nil) do
    %{name: to_string(name), default: if(default, do: inspect(default))}
  end
end
