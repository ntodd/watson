defmodule Watson.Extractors.EctoExtractor do
  @moduledoc """
  Phase 5: Ecto DSL Extraction.

  Parses schema/2 blocks to extract:
  - field definitions
  - belongs_to associations
  - has_many associations
  - has_one associations
  - embeds_one/embeds_many
  """

  alias Watson.Records.EctoSchema

  @doc """
  Extracts Ecto schemas from the given files.
  """
  def extract_schemas(files) do
    files
    |> Enum.filter(&is_schema_file?/1)
    |> Enum.flat_map(&extract_from_file/1)
    |> Enum.sort_by(& &1.module)
  end

  defp is_schema_file?(file) do
    case File.read(file) do
      {:ok, content} ->
        String.contains?(content, "use Ecto.Schema") or
          String.contains?(content, "schema ") or
          String.contains?(content, "embedded_schema")

      _ ->
        false
    end
  end

  defp extract_from_file(file) do
    with {:ok, content} <- File.read(file),
         {:ok, ast} <- Code.string_to_quoted(content, file: file, columns: true) do
      extract_from_ast(ast, file)
    else
      _ -> []
    end
  end

  defp extract_from_ast(ast, file) do
    context = %{
      file: file,
      current_module: nil,
      schemas: []
    }

    {_ast, context} = Macro.prewalk(ast, context, &visit_node/2)
    context.schemas
  end

  # Track current module
  defp visit_node(
         {:defmodule, _meta, [{:__aliases__, _, parts} | _body]} = node,
         context
       ) do
    module_name = module_to_string(parts)
    {node, %{context | current_module: module_name}}
  end

  # Handle schema/2 macro
  defp visit_node(
         {:schema, meta, [source, [do: block]]} = node,
         context
       )
       when is_binary(source) do
    if context.current_module do
      line = Keyword.get(meta, :line, 1)
      end_line = find_block_end(block, line)

      {fields, assocs} = extract_schema_content(block)

      schema =
        EctoSchema.new(
          context.current_module,
          source,
          context.file,
          line,
          end_line,
          fields: fields,
          assocs: assocs
        )

      {node, %{context | schemas: [schema | context.schemas]}}
    else
      {node, context}
    end
  end

  # Handle embedded_schema (no source table)
  defp visit_node(
         {:embedded_schema, meta, [[do: block]]} = node,
         context
       ) do
    if context.current_module do
      line = Keyword.get(meta, :line, 1)
      end_line = find_block_end(block, line)

      {fields, assocs} = extract_schema_content(block)

      schema =
        EctoSchema.new(
          context.current_module,
          nil,
          context.file,
          line,
          end_line,
          fields: fields,
          assocs: assocs
        )

      {node, %{context | schemas: [schema | context.schemas]}}
    else
      {node, context}
    end
  end

  defp visit_node(node, context), do: {node, context}

  defp extract_schema_content(block) do
    fields = []
    assocs = []

    {fields, assocs} = walk_schema_block(block, fields, assocs)

    {Enum.reverse(fields), Enum.reverse(assocs)}
  end

  defp walk_schema_block({:__block__, _, items}, fields, assocs) do
    Enum.reduce(items, {fields, assocs}, fn item, {f, a} ->
      walk_schema_block(item, f, a)
    end)
  end

  # field/2 or field/3
  defp walk_schema_block({:field, _meta, [name, type | _opts]}, fields, assocs)
       when is_atom(name) do
    field = EctoSchema.field(name, normalize_type(type))
    {[field | fields], assocs}
  end

  defp walk_schema_block({:field, _meta, [name]}, fields, assocs)
       when is_atom(name) do
    field = EctoSchema.field(name, :string)
    {[field | fields], assocs}
  end

  # belongs_to/2 or belongs_to/3
  defp walk_schema_block(
         {:belongs_to, _meta, [name, {:__aliases__, _, parts} | _opts]},
         fields,
         assocs
       )
       when is_atom(name) do
    related = module_to_string(parts)
    assoc = EctoSchema.assoc(:belongs_to, name, related)
    {fields, [assoc | assocs]}
  end

  defp walk_schema_block({:belongs_to, _meta, [name, related | _opts]}, fields, assocs)
       when is_atom(name) and is_atom(related) do
    assoc = EctoSchema.assoc(:belongs_to, name, to_string(related))
    {fields, [assoc | assocs]}
  end

  # has_many/2 or has_many/3
  defp walk_schema_block(
         {:has_many, _meta, [name, {:__aliases__, _, parts} | _opts]},
         fields,
         assocs
       )
       when is_atom(name) do
    related = module_to_string(parts)
    assoc = EctoSchema.assoc(:has_many, name, related)
    {fields, [assoc | assocs]}
  end

  defp walk_schema_block({:has_many, _meta, [name, related | _opts]}, fields, assocs)
       when is_atom(name) and is_atom(related) do
    assoc = EctoSchema.assoc(:has_many, name, to_string(related))
    {fields, [assoc | assocs]}
  end

  # has_one/2 or has_one/3
  defp walk_schema_block(
         {:has_one, _meta, [name, {:__aliases__, _, parts} | _opts]},
         fields,
         assocs
       )
       when is_atom(name) do
    related = module_to_string(parts)
    assoc = EctoSchema.assoc(:has_one, name, related)
    {fields, [assoc | assocs]}
  end

  defp walk_schema_block({:has_one, _meta, [name, related | _opts]}, fields, assocs)
       when is_atom(name) and is_atom(related) do
    assoc = EctoSchema.assoc(:has_one, name, to_string(related))
    {fields, [assoc | assocs]}
  end

  # many_to_many/2 or many_to_many/3
  defp walk_schema_block(
         {:many_to_many, _meta, [name, {:__aliases__, _, parts} | _opts]},
         fields,
         assocs
       )
       when is_atom(name) do
    related = module_to_string(parts)
    assoc = EctoSchema.assoc(:many_to_many, name, related)
    {fields, [assoc | assocs]}
  end

  # embeds_one/2 or embeds_one/3
  defp walk_schema_block(
         {:embeds_one, _meta, [name, {:__aliases__, _, parts} | _opts]},
         fields,
         assocs
       )
       when is_atom(name) do
    related = module_to_string(parts)
    assoc = EctoSchema.assoc(:embeds_one, name, related)
    {fields, [assoc | assocs]}
  end

  # embeds_many/2 or embeds_many/3
  defp walk_schema_block(
         {:embeds_many, _meta, [name, {:__aliases__, _, parts} | _opts]},
         fields,
         assocs
       )
       when is_atom(name) do
    related = module_to_string(parts)
    assoc = EctoSchema.assoc(:embeds_many, name, related)
    {fields, [assoc | assocs]}
  end

  # timestamps/0 or timestamps/1
  defp walk_schema_block({:timestamps, _meta, _args}, fields, assocs) do
    inserted_at = EctoSchema.field(:inserted_at, :naive_datetime)
    updated_at = EctoSchema.field(:updated_at, :naive_datetime)
    {[updated_at, inserted_at | fields], assocs}
  end

  defp walk_schema_block(_, fields, assocs), do: {fields, assocs}

  defp normalize_type({:__aliases__, _, parts}), do: module_to_string(parts)
  defp normalize_type(type) when is_atom(type), do: type
  defp normalize_type({type, _, _}) when is_atom(type), do: type
  defp normalize_type(_), do: :any

  defp module_to_string(parts) when is_list(parts) do
    parts |> Enum.map(&to_string/1) |> Enum.join(".")
  end

  defp find_block_end({:__block__, _, items}, start_line) do
    items
    |> Enum.map(&get_node_line/1)
    |> Enum.max(fn -> start_line end)
  end

  defp find_block_end(single_item, start_line) do
    max(get_node_line(single_item), start_line)
  end

  defp get_node_line({_, meta, _}) when is_list(meta) do
    Keyword.get(meta, :line, 0)
  end

  defp get_node_line(_), do: 0
end
