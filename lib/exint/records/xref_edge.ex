defmodule Exint.Records.XrefEdge do
  @moduledoc """
  Represents an xref dependency edge between modules.
  """

  @behaviour Exint.Records.Record

  defstruct [
    :from,
    :to,
    :type
  ]

  @type edge_type :: :compile | :runtime | :export | :behaviour
  @type t :: %__MODULE__{
          from: String.t(),
          to: String.t(),
          type: edge_type()
        }

  @impl true
  def kind, do: "xref_edge"

  @impl true
  def to_map(%__MODULE__{} = record) do
    %{
      from: record.from,
      to: record.to,
      type: to_string(record.type)
    }
  end

  @doc """
  Creates a new XrefEdge record.
  """
  def new(from_module, to_module, type) do
    %__MODULE__{
      from: from_module,
      to: to_module,
      type: type
    }
  end
end
