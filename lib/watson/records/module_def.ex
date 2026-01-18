defmodule Watson.Records.ModuleDef do
  @moduledoc """
  Represents a module definition record.
  """

  @behaviour Watson.Records.Record

  defstruct [
    :module,
    :file,
    :span,
    behaviours: [],
    attributes: []
  ]

  @type t :: %__MODULE__{
          module: String.t(),
          file: String.t(),
          span: Watson.Records.Record.span(),
          behaviours: [String.t()],
          attributes: [String.t()]
        }

  @impl true
  def kind, do: "module_def"

  @impl true
  def to_map(%__MODULE__{} = record) do
    %{
      module: record.module,
      file: record.file,
      span: record.span,
      behaviours: record.behaviours,
      attributes: record.attributes
    }
  end

  @doc """
  Creates a new ModuleDef record.
  """
  def new(module, file, start_line, end_line, opts \\ []) do
    %__MODULE__{
      module: module,
      file: file,
      span: Watson.Records.Record.span(start_line, end_line),
      behaviours: Keyword.get(opts, :behaviours, []),
      attributes: Keyword.get(opts, :attributes, [])
    }
  end
end
