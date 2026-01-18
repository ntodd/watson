# Watson

Code intelligence for Elixir/Phoenix projects. Builds a searchable call graph for LLM coding agents.

## Installation

Add `watson` as a dev dependency in `mix.exs`:

```elixir
def deps do
  [
    {:watson, "~> 0.1.0", only: :dev, runtime: false}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

## Claude Code Setup

Add to your `~/.claude/mcp.json`:

```json
{
  "mcpServers": {
    "watson": {
      "command": "mix",
      "args": ["watson.mcp"],
      "cwd": "/path/to/your/elixir/project"
    }
  }
}
```

## Auto-Indexing

Watson automatically indexes your project when you use any query tool. The index is:

- **Created on first use** - no manual setup required
- **Updated incrementally** - only changed files are re-indexed
- **Persisted in `.watson/`** - survives restarts

You can force a full rebuild with the `index` tool if needed, but it's rarely necessary.

## Tools

### Code Navigation

| Tool | Description |
|------|-------------|
| `function_definition` | Find where a function is defined. Returns file path, line numbers, visibility, and whether it's a macro. |
| `function_references` | Find all call sites for a function. Returns file, line, and calling function for each invocation. |
| `function_callers` | Find functions that call a given function (traverse up the call graph). Use for impact analysis. |
| `function_callees` | Find functions called by a given function (traverse down the call graph). |

### Type Information

| Tool | Description |
|------|-------------|
| `function_spec` | Get the `@spec` type signature for a function. Returns parameter types and return type. |
| `module_types` | List all type definitions (`@type`, `@typep`, `@opaque`, `@callback`) in a module. |
| `type_errors` | Get compiler type errors and warnings from Elixir's type checker (1.17+). |

### Phoenix/Ecto

| Tool | Description |
|------|-------------|
| `routes` | List all Phoenix routes. Returns HTTP verb, path, controller, and action. |
| `schema` | Get Ecto schema structure: table name, fields with types, and associations. |

### Analysis

| Tool | Description |
|------|-------------|
| `impact_analysis` | Analyze what's affected by changing files. Returns affected modules and suggested test files. |
| `index` | Force a full rebuild of the code index. Usually not needed due to auto-indexing. |

## MFA Format

Functions are specified in `Module.function/arity` format:

```
MyApp.Accounts.get_user/1
Phoenix.Controller.render/3
```
