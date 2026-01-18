defmodule Exint.Extractors.AstExtractorTest do
  use ExUnit.Case, async: true

  alias Exint.Extractors.AstExtractor

  setup do
    # Create a temp directory for test files
    tmp_dir = System.tmp_dir!() |> Path.join("exint_test_#{:rand.uniform(10000)}")
    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  describe "extract_file/1" do
    test "extracts module definition", %{tmp_dir: tmp_dir} do
      file = Path.join(tmp_dir, "simple.ex")

      File.write!(file, """
      defmodule MyApp.Simple do
        @moduledoc "A simple module"

        def hello(name) do
          "Hello, " <> name
        end
      end
      """)

      result = AstExtractor.extract_file(file)

      assert length(result.modules) == 1
      [module] = result.modules
      assert module.module == "MyApp.Simple"
      assert module.file == file
      assert module.span.start.line == 1
    end

    test "extracts function definitions", %{tmp_dir: tmp_dir} do
      file = Path.join(tmp_dir, "funcs.ex")

      File.write!(file, """
      defmodule MyApp.Funcs do
        def public_func(x), do: x * 2
        defp private_func(x), do: x + 1
        defmacro my_macro(ast), do: ast
      end
      """)

      result = AstExtractor.extract_file(file)

      assert length(result.functions) == 3

      public = Enum.find(result.functions, &(&1.name == "public_func"))
      assert public.visibility == :public
      assert public.arity == 1
      assert public.is_macro == false

      private = Enum.find(result.functions, &(&1.name == "private_func"))
      assert private.visibility == :private

      macro = Enum.find(result.functions, &(&1.name == "my_macro"))
      assert macro.is_macro == true
    end

    test "extracts alias/import/require/use", %{tmp_dir: tmp_dir} do
      file = Path.join(tmp_dir, "with_alias.ex")

      File.write!(file, """
      defmodule MyApp.WithAlias do
        alias MyApp.Other
        import Enum, only: [map: 2]
        require Logger
        use GenServer
      end
      """)

      result = AstExtractor.extract_file(file)

      assert length(result.aliases) == 4

      alias_ref = Enum.find(result.aliases, &(&1.kind_type == :alias))
      assert alias_ref.target == "MyApp.Other"

      import_ref = Enum.find(result.aliases, &(&1.kind_type == :import))
      assert import_ref.target == "Enum"
      assert import_ref.only == [{:map, 2}]

      require_ref = Enum.find(result.aliases, &(&1.kind_type == :require))
      assert require_ref.target == "Logger"

      use_ref = Enum.find(result.aliases, &(&1.kind_type == :use))
      assert use_ref.target == "GenServer"
    end

    test "extracts remote calls", %{tmp_dir: tmp_dir} do
      file = Path.join(tmp_dir, "with_calls.ex")

      File.write!(file, """
      defmodule MyApp.WithCalls do
        def foo do
          String.upcase("hello")
          Enum.map([1, 2, 3], &(&1 * 2))
        end
      end
      """)

      result = AstExtractor.extract_file(file)

      calls = Enum.filter(result.calls, &(&1.callee != nil))
      assert length(calls) >= 2

      string_call = Enum.find(calls, &String.starts_with?(&1.callee, "String."))
      assert string_call != nil
      assert string_call.callee == "String.upcase/1"
    end

    test "extracts struct definitions", %{tmp_dir: tmp_dir} do
      file = Path.join(tmp_dir, "with_struct.ex")

      File.write!(file, """
      defmodule MyApp.Settings do
        defstruct [:theme, :locale, enabled: true]
      end
      """)

      result = AstExtractor.extract_file(file)

      assert length(result.structs) == 1
      [struct] = result.structs
      assert struct.module == "MyApp.Settings"
      assert length(struct.fields) == 3

      theme_field = Enum.find(struct.fields, &(&1.name == "theme"))
      assert theme_field != nil

      enabled_field = Enum.find(struct.fields, &(&1.name == "enabled"))
      assert enabled_field.default == "true"
    end
  end

  describe "extract_files/1" do
    test "extracts from multiple files", %{tmp_dir: tmp_dir} do
      file1 = Path.join(tmp_dir, "mod1.ex")
      file2 = Path.join(tmp_dir, "mod2.ex")

      File.write!(file1, """
      defmodule MyApp.Mod1 do
        def foo, do: :foo
      end
      """)

      File.write!(file2, """
      defmodule MyApp.Mod2 do
        def bar, do: :bar
      end
      """)

      result = AstExtractor.extract_files([file1, file2])

      assert length(result.modules) == 2
      assert length(result.functions) == 2
    end

    test "sorts results for determinism", %{tmp_dir: tmp_dir} do
      file = Path.join(tmp_dir, "multi.ex")

      File.write!(file, """
      defmodule Z.Module do
        def z_func, do: :z
      end

      defmodule A.Module do
        def a_func, do: :a
      end
      """)

      result = AstExtractor.extract_files([file])

      [first_mod, second_mod] = result.modules
      assert first_mod.module == "A.Module"
      assert second_mod.module == "Z.Module"
    end
  end
end
