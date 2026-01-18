defmodule Exint.Records.PhoenixRoute do
  @moduledoc """
  Represents a Phoenix route definition.
  """

  @behaviour Exint.Records.Record

  defstruct [
    :verb,
    :path,
    :controller,
    :action,
    :router,
    :span,
    :file
  ]

  @type t :: %__MODULE__{
          verb: String.t(),
          path: String.t(),
          controller: String.t(),
          action: String.t(),
          router: String.t(),
          span: Exint.Records.Record.line_span(),
          file: String.t()
        }

  @impl true
  def kind, do: "phoenix_route"

  @impl true
  def to_map(%__MODULE__{} = record) do
    %{
      verb: record.verb,
      path: record.path,
      controller: record.controller,
      action: record.action,
      router: record.router,
      span: record.span
    }
  end

  @doc """
  Creates a new PhoenixRoute record.
  """
  def new(verb, path, controller, action, router, line, file) do
    %__MODULE__{
      verb: String.upcase(to_string(verb)),
      path: path,
      controller: controller,
      action: to_string(action),
      router: router,
      span: Exint.Records.Record.line_span(line),
      file: file
    }
  end
end
