defmodule Watson.Records.TypeDef do
  @moduledoc """
  Represents a type definition (@type, @typep, @opaque, @callback).

  Examples:
  ```elixir
  @type t :: %__MODULE__{name: String.t(), age: integer()}
  @typep internal :: {atom(), any()}
  @opaque opaque_type :: list(map())
  @callback my_callback(arg :: term()) :: :ok | {:error, reason :: term()}
  ```
  """

  @behaviour Watson.Records.Record

  alias Watson.Records.Record

  @type kind_type :: :type | :typep | :opaque | :callback | :macrocallback

  @type t :: %__MODULE__{
          module: String.t(),
          name: String.t(),
          arity: non_neg_integer(),
          kind_type: kind_type(),
          params: [String.t()],
          definition: String.t(),
          file: String.t(),
          span: Record.line_span()
        }

  @enforce_keys [:module, :name, :arity, :kind_type, :definition, :file, :span]
  defstruct [:module, :name, :arity, :kind_type, :definition, :file, :span, params: []]

  @impl true
  def kind, do: "type_def"

  @impl true
  def to_map(%__MODULE__{} = type_def) do
    %{
      "module" => type_def.module,
      "name" => type_def.name,
      "arity" => type_def.arity,
      "kind_type" => to_string(type_def.kind_type),
      "params" => type_def.params,
      "definition" => type_def.definition,
      "file" => type_def.file,
      "span" => span_to_map(type_def.span)
    }
  end

  @doc """
  Creates a new TypeDef record.
  """
  def new(module, name, arity, kind_type, params, definition, file, line) do
    %__MODULE__{
      module: module,
      name: to_string(name),
      arity: arity,
      kind_type: kind_type,
      params: params,
      definition: definition,
      file: file,
      span: %{line: line}
    }
  end

  defp span_to_map(%{line: line}), do: %{"line" => line}
end
