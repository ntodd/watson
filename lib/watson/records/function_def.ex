defmodule Watson.Records.FunctionDef do
  @moduledoc """
  Represents a function or macro definition record.
  """

  @behaviour Watson.Records.Record

  defstruct [
    :module,
    :name,
    :arity,
    :visibility,
    :span,
    :file,
    is_macro: false
  ]

  @type visibility :: :public | :private
  @type t :: %__MODULE__{
          module: String.t(),
          name: String.t(),
          arity: non_neg_integer(),
          visibility: visibility(),
          is_macro: boolean(),
          span: Watson.Records.Record.span(),
          file: String.t()
        }

  @impl true
  def kind, do: "function_def"

  @impl true
  def to_map(%__MODULE__{} = record) do
    %{
      module: record.module,
      name: record.name,
      arity: record.arity,
      visibility: to_string(record.visibility),
      is_macro: record.is_macro,
      span: record.span,
      file: record.file
    }
  end

  @doc """
  Creates a new FunctionDef record.
  """
  def new(module, name, arity, visibility, start_line, end_line, file, opts \\ []) do
    %__MODULE__{
      module: module,
      name: to_string(name),
      arity: arity,
      visibility: visibility,
      is_macro: Keyword.get(opts, :is_macro, false),
      span: Watson.Records.Record.span(start_line, end_line),
      file: file
    }
  end

  @doc """
  Returns the MFA string for this function.
  """
  def mfa(%__MODULE__{} = record) do
    "#{record.module}.#{record.name}/#{record.arity}"
  end
end
