defmodule Exint.Extractors.EctoExtractorTest do
  use ExUnit.Case, async: true

  alias Exint.Extractors.EctoExtractor

  setup do
    tmp_dir = System.tmp_dir!() |> Path.join("exint_ecto_test_#{:rand.uniform(10000)}")
    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  describe "extract_schemas/1" do
    test "extracts basic schema", %{tmp_dir: tmp_dir} do
      file = Path.join(tmp_dir, "user.ex")

      File.write!(file, """
      defmodule MyApp.User do
        use Ecto.Schema

        schema "users" do
          field :email, :string
          field :name, :string
          field :age, :integer
        end
      end
      """)

      schemas = EctoExtractor.extract_schemas([file])

      assert length(schemas) == 1
      [schema] = schemas
      assert schema.module == "MyApp.User"
      assert schema.source == "users"
      assert length(schema.fields) == 3

      email_field = Enum.find(schema.fields, &(&1.name == "email"))
      assert email_field.type == ":string"
    end

    test "extracts timestamps", %{tmp_dir: tmp_dir} do
      file = Path.join(tmp_dir, "post.ex")

      File.write!(file, """
      defmodule MyApp.Post do
        use Ecto.Schema

        schema "posts" do
          field :title, :string
          timestamps()
        end
      end
      """)

      schemas = EctoExtractor.extract_schemas([file])

      [schema] = schemas
      field_names = Enum.map(schema.fields, & &1.name)
      assert "inserted_at" in field_names
      assert "updated_at" in field_names
    end

    test "extracts associations", %{tmp_dir: tmp_dir} do
      file = Path.join(tmp_dir, "user.ex")

      File.write!(file, """
      defmodule MyApp.User do
        use Ecto.Schema

        schema "users" do
          field :email, :string

          has_many :posts, MyApp.Post
          has_one :profile, MyApp.Profile
          belongs_to :organization, MyApp.Organization
        end
      end
      """)

      schemas = EctoExtractor.extract_schemas([file])

      [schema] = schemas
      assert length(schema.assocs) == 3

      has_many = Enum.find(schema.assocs, &(&1.kind == "has_many"))
      assert has_many.name == "posts"
      assert has_many.related == "MyApp.Post"

      has_one = Enum.find(schema.assocs, &(&1.kind == "has_one"))
      assert has_one.name == "profile"
      assert has_one.related == "MyApp.Profile"

      belongs_to = Enum.find(schema.assocs, &(&1.kind == "belongs_to"))
      assert belongs_to.name == "organization"
      assert belongs_to.related == "MyApp.Organization"
    end

    test "extracts embedded schemas", %{tmp_dir: tmp_dir} do
      file = Path.join(tmp_dir, "settings.ex")

      File.write!(file, """
      defmodule MyApp.Settings do
        use Ecto.Schema

        embedded_schema do
          field :theme, :string
          field :notifications_enabled, :boolean
        end
      end
      """)

      schemas = EctoExtractor.extract_schemas([file])

      [schema] = schemas
      assert schema.module == "MyApp.Settings"
      assert schema.source == nil
      assert length(schema.fields) == 2
    end

    test "extracts embeds_one and embeds_many", %{tmp_dir: tmp_dir} do
      file = Path.join(tmp_dir, "document.ex")

      File.write!(file, """
      defmodule MyApp.Document do
        use Ecto.Schema

        schema "documents" do
          field :title, :string

          embeds_one :metadata, MyApp.Metadata
          embeds_many :sections, MyApp.Section
        end
      end
      """)

      schemas = EctoExtractor.extract_schemas([file])

      [schema] = schemas
      assert length(schema.assocs) == 2

      embeds_one = Enum.find(schema.assocs, &(&1.kind == "embeds_one"))
      assert embeds_one.name == "metadata"
      assert embeds_one.related == "MyApp.Metadata"

      embeds_many = Enum.find(schema.assocs, &(&1.kind == "embeds_many"))
      assert embeds_many.name == "sections"
      assert embeds_many.related == "MyApp.Section"
    end

    test "ignores non-schema files", %{tmp_dir: tmp_dir} do
      file = Path.join(tmp_dir, "regular.ex")

      File.write!(file, """
      defmodule MyApp.Regular do
        def foo, do: :bar
      end
      """)

      schemas = EctoExtractor.extract_schemas([file])
      assert schemas == []
    end

    test "sorts schemas by module name", %{tmp_dir: tmp_dir} do
      file = Path.join(tmp_dir, "schemas.ex")

      File.write!(file, """
      defmodule MyApp.Z.Schema do
        use Ecto.Schema
        schema "z_table" do
          field :z, :string
        end
      end

      defmodule MyApp.A.Schema do
        use Ecto.Schema
        schema "a_table" do
          field :a, :string
        end
      end
      """)

      schemas = EctoExtractor.extract_schemas([file])

      [first, second] = schemas
      assert first.module == "MyApp.A.Schema"
      assert second.module == "MyApp.Z.Schema"
    end
  end
end
