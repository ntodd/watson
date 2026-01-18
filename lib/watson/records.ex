defmodule Watson.Records do
  @moduledoc """
  Convenience module that re-exports all record types.
  """

  alias Watson.Records.{
    Record,
    ModuleDef,
    FunctionDef,
    CallRef,
    AliasRef,
    StructDef,
    PhoenixRoute,
    EctoSchema,
    XrefEdge
  }

  defdelegate wrap(record, source \\ :ast, confidence \\ :high), to: Record
  defdelegate to_json_line(record, source \\ :ast, confidence \\ :high), to: Record

  @doc """
  Returns all record modules.
  """
  def all_types do
    [
      ModuleDef,
      FunctionDef,
      CallRef,
      AliasRef,
      StructDef,
      PhoenixRoute,
      EctoSchema,
      XrefEdge
    ]
  end
end
