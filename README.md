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

## Tools

| Tool | Description |
|------|-------------|
| `index` | Build a searchable code graph for an Elixir/Phoenix project. Run once before using other tools. Re-run after code changes. |
| `function_definition` | Find where a function is defined. Returns file path, line numbers, visibility, and whether it's a macro. |
| `function_references` | Find all call sites for a function. Returns file, line, and calling function for each invocation. |
| `function_callers` | Find functions that call a given function (traverse up the call graph). Use for impact analysis. |
| `function_callees` | Find functions called by a given function (traverse down the call graph). |
| `routes` | List all Phoenix routes. Returns HTTP verb, path, controller, and action. |
| `schema` | Get Ecto schema structure: table name, fields with types, and associations. |
| `impact_analysis` | Analyze what's affected by changing files. Returns affected modules and suggested test files. |

## MFA Format

Functions are specified in `Module.function/arity` format:

```
MyApp.Accounts.get_user/1
Phoenix.Controller.render/3
```
