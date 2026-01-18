defmodule Exint.Records.CallRef do
  @moduledoc """
  Represents a function/macro call reference.
  """

  @behaviour Exint.Records.Record

  defstruct [
    :caller,
    :callee,
    :file,
    :span
  ]

  @type t :: %__MODULE__{
          caller: String.t(),
          callee: String.t() | nil,
          file: String.t(),
          span: Exint.Records.Record.line_span()
        }

  @impl true
  def kind, do: "call_ref"

  @impl true
  def to_map(%__MODULE__{} = record) do
    %{
      caller: record.caller,
      callee: record.callee,
      file: record.file,
      span: record.span
    }
  end

  @doc """
  Creates a new CallRef record.
  """
  def new(caller_mfa, callee_mfa, file, line) do
    %__MODULE__{
      caller: caller_mfa,
      callee: callee_mfa,
      file: file,
      span: Exint.Records.Record.line_span(line)
    }
  end
end
