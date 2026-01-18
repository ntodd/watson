defmodule Exint.Records.EctoSchema do
  @moduledoc """
  Represents an Ecto schema definition.
  """

  @behaviour Exint.Records.Record

  defstruct [
    :module,
    :source,
    :file,
    :span,
    fields: [],
    assocs: []
  ]

  @type field :: %{
          name: String.t(),
          type: String.t()
        }

  @type assoc :: %{
          kind: String.t(),
          name: String.t(),
          related: String.t()
        }

  @type t :: %__MODULE__{
          module: String.t(),
          source: String.t(),
          file: String.t(),
          span: Exint.Records.Record.span(),
          fields: [field()],
          assocs: [assoc()]
        }

  @impl true
  def kind, do: "ecto_schema"

  @impl true
  def to_map(%__MODULE__{} = record) do
    %{
      module: record.module,
      source: record.source,
      fields: record.fields,
      assocs: record.assocs
    }
  end

  @doc """
  Creates a new EctoSchema record.
  """
  def new(module, source, file, start_line, end_line, opts \\ []) do
    %__MODULE__{
      module: module,
      source: source,
      file: file,
      span: Exint.Records.Record.span(start_line, end_line),
      fields: Keyword.get(opts, :fields, []),
      assocs: Keyword.get(opts, :assocs, [])
    }
  end

  @doc """
  Creates a field map.
  """
  def field(name, type) do
    %{name: to_string(name), type: inspect(type)}
  end

  @doc """
  Creates an association map.
  """
  def assoc(kind, name, related) do
    %{kind: to_string(kind), name: to_string(name), related: related}
  end
end
