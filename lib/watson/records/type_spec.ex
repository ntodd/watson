defmodule Watson.Records.TypeSpec do
  @moduledoc """
  Represents a @spec definition for a function.

  Example:
  ```elixir
  @spec create_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  ```
  """

  @behaviour Watson.Records.Record

  alias Watson.Records.Record

  @type t :: %__MODULE__{
          module: String.t(),
          name: String.t(),
          arity: non_neg_integer(),
          params: [String.t()],
          return_type: String.t(),
          file: String.t(),
          span: Record.line_span()
        }

  @enforce_keys [:module, :name, :arity, :params, :return_type, :file, :span]
  defstruct [:module, :name, :arity, :params, :return_type, :file, :span]

  @impl true
  def kind, do: "type_spec"

  @impl true
  def to_map(%__MODULE__{} = spec) do
    %{
      "module" => spec.module,
      "name" => spec.name,
      "arity" => spec.arity,
      "params" => spec.params,
      "return_type" => spec.return_type,
      "file" => spec.file,
      "span" => span_to_map(spec.span)
    }
  end

  @doc """
  Creates a new TypeSpec record.
  """
  def new(module, name, arity, params, return_type, file, line) do
    %__MODULE__{
      module: module,
      name: to_string(name),
      arity: arity,
      params: params,
      return_type: return_type,
      file: file,
      span: %{line: line}
    }
  end

  defp span_to_map(%{line: line}), do: %{"line" => line}
end
