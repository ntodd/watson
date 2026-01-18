defmodule Watson.Records.Record do
  @moduledoc """
  Base behaviour and utilities for index records.

  All records must implement:
  - `kind/0` - Returns the record kind as a string
  - `to_map/1` - Converts the record to a map for JSON serialization
  """

  @type span :: %{
          start: %{line: pos_integer()},
          end: %{line: pos_integer()} | nil
        }

  @type line_span :: %{line: pos_integer()}

  @type confidence :: :high | :medium | :low
  @type source :: :ast | :compiler | :xref

  @callback kind() :: String.t()
  @callback to_map(struct()) :: map()

  @doc """
  Wraps a record with metadata for JSON Lines output.
  """
  def wrap(record, source \\ :ast, confidence \\ :high) do
    module = record.__struct__

    %{
      kind: module.kind(),
      data: module.to_map(record),
      source: to_string(source),
      confidence: to_string(confidence)
    }
  end

  @doc """
  Encodes a record as a JSON line.
  """
  def to_json_line(record, source \\ :ast, confidence \\ :high) do
    record
    |> wrap(source, confidence)
    |> Jason.encode!()
  end

  @doc """
  Creates a span map from line numbers.
  """
  def span(start_line, end_line \\ nil) do
    base = %{start: %{line: start_line}}

    if end_line do
      Map.put(base, :end, %{line: end_line})
    else
      base
    end
  end

  @doc """
  Creates a line-only span.
  """
  def line_span(line), do: %{line: line}

  @doc """
  Converts a record with source and confidence to a JSON-serializable map.
  This is used for rewriting the index during incremental updates.
  """
  def to_map(record, source \\ :ast, confidence \\ :high) do
    wrap(record, source, confidence)
  end
end
