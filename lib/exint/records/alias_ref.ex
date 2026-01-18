defmodule Exint.Records.AliasRef do
  @moduledoc """
  Represents an alias, import, require, or use directive.
  """

  @behaviour Exint.Records.Record

  defstruct [
    :kind_type,
    :module,
    :target,
    :file,
    :span,
    as: nil,
    only: nil,
    except: nil
  ]

  @type kind_type :: :alias | :import | :require | :use
  @type t :: %__MODULE__{
          kind_type: kind_type(),
          module: String.t(),
          target: String.t(),
          file: String.t(),
          span: Exint.Records.Record.line_span(),
          as: String.t() | nil,
          only: [atom()] | nil,
          except: [atom()] | nil
        }

  @impl true
  def kind, do: "alias_ref"

  @impl true
  def to_map(%__MODULE__{} = record) do
    map = %{
      type: to_string(record.kind_type),
      module: record.module,
      target: record.target,
      file: record.file,
      span: record.span
    }

    map
    |> maybe_put(:as, record.as)
    |> maybe_put(:only, record.only)
    |> maybe_put(:except, record.except)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @doc """
  Creates a new AliasRef record.
  """
  def new(kind_type, module, target, file, line, opts \\ []) do
    %__MODULE__{
      kind_type: kind_type,
      module: module,
      target: target,
      file: file,
      span: Exint.Records.Record.line_span(line),
      as: Keyword.get(opts, :as),
      only: Keyword.get(opts, :only),
      except: Keyword.get(opts, :except)
    }
  end
end
