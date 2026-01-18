defmodule Watson.Records.TypeDiagnostic do
  @moduledoc """
  Represents a compiler diagnostic (warning or error).

  Captures diagnostics from Code.with_diagnostics/2 including:
  - Type errors (Elixir 1.17+)
  - Unused variables
  - Unreachable clauses
  - Pattern match warnings
  - Deprecated function usage
  """

  @behaviour Watson.Records.Record

  alias Watson.Records.Record

  @type severity :: :error | :warning | :info | :hint

  @type t :: %__MODULE__{
          severity: severity(),
          message: String.t(),
          file: String.t(),
          span: Record.line_span(),
          module: String.t() | nil,
          function: String.t() | nil,
          code: String.t() | nil,
          source: String.t() | nil
        }

  @enforce_keys [:severity, :message, :file, :span]
  defstruct [:severity, :message, :file, :span, :module, :function, :code, :source]

  @impl true
  def kind, do: "type_diagnostic"

  @impl true
  def to_map(%__MODULE__{} = diag) do
    base = %{
      "severity" => to_string(diag.severity),
      "message" => diag.message,
      "file" => diag.file,
      "span" => span_to_map(diag.span)
    }

    base
    |> maybe_put("module", diag.module)
    |> maybe_put("function", diag.function)
    |> maybe_put("code", diag.code)
    |> maybe_put("source", diag.source)
  end

  @doc """
  Creates a new TypeDiagnostic from a compiler diagnostic map.
  """
  def new(severity, message, file, line, opts \\ []) do
    %__MODULE__{
      severity: severity,
      message: message,
      file: file,
      span: %{line: line},
      module: Keyword.get(opts, :module),
      function: Keyword.get(opts, :function),
      code: Keyword.get(opts, :code),
      source: Keyword.get(opts, :source)
    }
  end

  @doc """
  Creates a TypeDiagnostic from a Code.with_diagnostics/2 diagnostic.
  """
  def from_compiler_diagnostic(diagnostic) do
    %__MODULE__{
      severity: diagnostic.severity,
      message: diagnostic.message,
      file: diagnostic.file || "unknown",
      span: %{line: diagnostic.position || 1},
      module: nil,
      function: nil,
      code: nil,
      source: diagnostic.source && to_string(diagnostic.source)
    }
  end

  defp span_to_map(%{line: line}), do: %{"line" => line}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
