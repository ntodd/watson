defmodule Exint.Extractors.CompilerTracer do
  @moduledoc """
  Phase 2: Compiler Tracing.

  Uses Elixir's compiler tracer to capture:
  - resolved alias/import context
  - macro expansion boundaries (best effort)
  - compile-time module dependencies
  """

  alias Exint.Records.{CallRef, XrefEdge}

  @doc """
  Starts the tracer agent to collect events.
  """
  def start do
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end

  @doc """
  Stops the tracer and returns collected events.
  """
  def stop do
    events = Agent.get(__MODULE__, & &1)
    Agent.stop(__MODULE__)
    events
  end

  @doc """
  Gets the current events without stopping.
  """
  def get_events do
    if Process.whereis(__MODULE__) do
      Agent.get(__MODULE__, & &1)
    else
      []
    end
  end

  @doc """
  Clears collected events.
  """
  def clear do
    if Process.whereis(__MODULE__) do
      Agent.update(__MODULE__, fn _ -> [] end)
    end
  end

  # Tracer callbacks

  def trace({:remote_function, meta, module, name, arity}, env) do
    if Process.whereis(__MODULE__) do
      event = %{
        type: :remote_call,
        caller_module: env.module,
        caller_function: env.function,
        callee_module: module,
        callee_name: name,
        callee_arity: arity,
        file: env.file,
        line: Keyword.get(meta, :line, 0)
      }

      Agent.update(__MODULE__, &[event | &1])
    end

    :ok
  end

  def trace({:remote_macro, meta, module, name, arity}, env) do
    if Process.whereis(__MODULE__) do
      event = %{
        type: :remote_macro,
        caller_module: env.module,
        caller_function: env.function,
        callee_module: module,
        callee_name: name,
        callee_arity: arity,
        file: env.file,
        line: Keyword.get(meta, :line, 0)
      }

      Agent.update(__MODULE__, &[event | &1])
    end

    :ok
  end

  def trace({:local_function, meta, name, arity}, env) do
    if Process.whereis(__MODULE__) do
      event = %{
        type: :local_call,
        caller_module: env.module,
        caller_function: env.function,
        callee_name: name,
        callee_arity: arity,
        file: env.file,
        line: Keyword.get(meta, :line, 0)
      }

      Agent.update(__MODULE__, &[event | &1])
    end

    :ok
  end

  def trace({:local_macro, meta, name, arity}, env) do
    if Process.whereis(__MODULE__) do
      event = %{
        type: :local_macro,
        caller_module: env.module,
        caller_function: env.function,
        callee_name: name,
        callee_arity: arity,
        file: env.file,
        line: Keyword.get(meta, :line, 0)
      }

      Agent.update(__MODULE__, &[event | &1])
    end

    :ok
  end

  def trace({:imported_function, meta, module, name, arity}, env) do
    if Process.whereis(__MODULE__) do
      event = %{
        type: :imported_call,
        caller_module: env.module,
        caller_function: env.function,
        callee_module: module,
        callee_name: name,
        callee_arity: arity,
        file: env.file,
        line: Keyword.get(meta, :line, 0)
      }

      Agent.update(__MODULE__, &[event | &1])
    end

    :ok
  end

  def trace({:imported_macro, meta, module, name, arity}, env) do
    if Process.whereis(__MODULE__) do
      event = %{
        type: :imported_macro,
        caller_module: env.module,
        caller_function: env.function,
        callee_module: module,
        callee_name: name,
        callee_arity: arity,
        file: env.file,
        line: Keyword.get(meta, :line, 0)
      }

      Agent.update(__MODULE__, &[event | &1])
    end

    :ok
  end

  def trace({:alias_reference, meta, module}, env) do
    if Process.whereis(__MODULE__) do
      event = %{
        type: :alias_reference,
        caller_module: env.module,
        referenced_module: module,
        file: env.file,
        line: Keyword.get(meta, :line, 0)
      }

      Agent.update(__MODULE__, &[event | &1])
    end

    :ok
  end

  def trace({:require, _meta, module, _opts}, env) do
    if Process.whereis(__MODULE__) do
      event = %{
        type: :require,
        caller_module: env.module,
        required_module: module,
        file: env.file
      }

      Agent.update(__MODULE__, &[event | &1])
    end

    :ok
  end

  def trace({:struct_expansion, meta, module, _keys}, env) do
    if Process.whereis(__MODULE__) do
      event = %{
        type: :struct_expansion,
        caller_module: env.module,
        struct_module: module,
        file: env.file,
        line: Keyword.get(meta, :line, 0)
      }

      Agent.update(__MODULE__, &[event | &1])
    end

    :ok
  end

  def trace({:import, _meta, module, _opts}, env) do
    if Process.whereis(__MODULE__) do
      event = %{
        type: :import,
        caller_module: env.module,
        imported_module: module,
        file: env.file
      }

      Agent.update(__MODULE__, &[event | &1])
    end

    :ok
  end

  def trace({:compile_env, app, path, return}, env) do
    if Process.whereis(__MODULE__) do
      event = %{
        type: :compile_env,
        module: env.module,
        app: app,
        path: path,
        value: return,
        file: env.file
      }

      Agent.update(__MODULE__, &[event | &1])
    end

    :ok
  end

  def trace(_event, _env), do: :ok

  @doc """
  Converts tracer events to records.
  """
  def events_to_records(events) do
    calls =
      events
      |> Enum.filter(&(&1.type in [:remote_call, :remote_macro, :imported_call, :imported_macro, :local_call, :local_macro]))
      |> Enum.map(&event_to_call_ref/1)
      |> Enum.reject(&is_nil/1)

    edges =
      events
      |> Enum.filter(&(&1.type in [:require, :alias_reference, :struct_expansion, :import]))
      |> Enum.map(&event_to_xref_edge/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    compile_envs =
      events
      |> Enum.filter(&(&1.type == :compile_env))
      |> Enum.uniq_by(&{&1.app, &1.path})

    %{calls: calls, edges: edges, compile_envs: compile_envs}
  end

  defp event_to_call_ref(event) do
    # Skip calls at line 1 (usually macro expansions/compile-time code)
    if event.line <= 1 do
      nil
    else
      caller_mfa = format_mfa(event.caller_module, event.caller_function)

      # Local calls don't have callee_module
      callee_mfa =
        if event.type in [:local_call, :local_macro] do
          "#{inspect(event.caller_module)}.#{event.callee_name}/#{event.callee_arity}"
        else
          "#{inspect(event.callee_module)}.#{event.callee_name}/#{event.callee_arity}"
        end

      cond do
        # No caller info
        is_nil(caller_mfa) ->
          nil

        # Skip internal functions (double underscore)
        String.contains?(caller_mfa, "__") ->
          nil

        # Skip calls to Kernel/Module/Elixir internals
        skip_callee?(callee_mfa) ->
          nil

        true ->
          CallRef.new(caller_mfa, callee_mfa, event.file, event.line)
      end
    end
  end

  # Skip standard library and compiler internal calls
  defp skip_callee?("Kernel." <> _), do: true
  defp skip_callee?("Module." <> _), do: true
  defp skip_callee?("Code." <> _), do: true
  defp skip_callee?("Macro." <> _), do: true
  defp skip_callee?(":erlang." <> _), do: true
  defp skip_callee?(":elixir" <> _), do: true
  defp skip_callee?("String.Chars." <> _), do: true
  defp skip_callee?("Access." <> _), do: true
  defp skip_callee?("Phoenix.Component.Declarative." <> _), do: true
  defp skip_callee?("Phoenix.Template." <> _), do: true
  defp skip_callee?("Phoenix.LiveView.HTMLEngine." <> _), do: true
  defp skip_callee?("Phoenix.VerifiedRoutes." <> _), do: true
  defp skip_callee?(_), do: false

  defp event_to_xref_edge(%{type: :require} = event) do
    XrefEdge.new(
      inspect(event.caller_module),
      inspect(event.required_module),
      :compile
    )
  end

  defp event_to_xref_edge(%{type: :alias_reference} = event) do
    XrefEdge.new(
      inspect(event.caller_module),
      inspect(event.referenced_module),
      :runtime
    )
  end

  defp event_to_xref_edge(%{type: :struct_expansion} = event) do
    XrefEdge.new(
      inspect(event.caller_module),
      inspect(event.struct_module),
      :compile
    )
  end

  defp event_to_xref_edge(%{type: :import} = event) do
    XrefEdge.new(
      inspect(event.caller_module),
      inspect(event.imported_module),
      :compile
    )
  end

  defp event_to_xref_edge(_), do: nil

  defp format_mfa(module, nil), do: inspect(module)
  defp format_mfa(nil, _), do: nil
  defp format_mfa(module, {name, arity}), do: "#{inspect(module)}.#{name}/#{arity}"
end
