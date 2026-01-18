defmodule Watson.Index.StoreTest do
  use ExUnit.Case, async: true

  alias Watson.Index.Store
  alias Watson.Records.ModuleDef

  setup do
    tmp_dir = System.tmp_dir!() |> Path.join("watson_store_test_#{:rand.uniform(10000)}")
    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  describe "init/1" do
    test "creates index directory structure", %{tmp_dir: tmp_dir} do
      Store.init(tmp_dir)

      assert File.exists?(Store.index_dir(tmp_dir))
      assert File.exists?(Store.cache_dir(tmp_dir))
    end
  end

  describe "write_records/2 and read_records/1" do
    test "writes and reads records", %{tmp_dir: tmp_dir} do
      mod1 = ModuleDef.new("MyApp.Mod1", "lib/mod1.ex", 1, 10)
      mod2 = ModuleDef.new("MyApp.Mod2", "lib/mod2.ex", 1, 20)

      records = [{mod1, :ast, :high}, {mod2, :ast, :high}]

      Store.write_records(records, tmp_dir)

      {:ok, loaded} = Store.read_records(tmp_dir)

      assert length(loaded) == 2
      assert Enum.all?(loaded, &(&1["kind"] == "module_def"))
    end

    test "handles empty records list", %{tmp_dir: tmp_dir} do
      Store.write_records([], tmp_dir)

      {:ok, loaded} = Store.read_records(tmp_dir)
      assert loaded == []
    end
  end

  describe "write_manifest/2 and read_manifest/1" do
    test "writes and reads manifest", %{tmp_dir: tmp_dir} do
      Store.write_manifest(tmp_dir, file_count: 10, record_count: 100)

      {:ok, manifest} = Store.read_manifest(tmp_dir)

      assert manifest["schema_version"] == "1.0.0"
      assert manifest["file_count"] == 10
      assert manifest["record_count"] == 100
      assert Map.has_key?(manifest, "elixir_version")
      assert Map.has_key?(manifest, "otp_version")
      assert Map.has_key?(manifest, "mix_env")
    end
  end

  describe "index_exists?/1" do
    test "returns false for non-existent index", %{tmp_dir: tmp_dir} do
      refute Store.index_exists?(tmp_dir)
    end

    test "returns true when manifest and index exist", %{tmp_dir: tmp_dir} do
      Store.write_records([], tmp_dir)
      Store.write_manifest(tmp_dir)

      assert Store.index_exists?(tmp_dir)
    end
  end

  describe "clear/1" do
    test "removes index directory", %{tmp_dir: tmp_dir} do
      Store.write_records([], tmp_dir)
      Store.write_manifest(tmp_dir)

      assert Store.index_exists?(tmp_dir)

      Store.clear(tmp_dir)

      refute Store.index_exists?(tmp_dir)
    end
  end

  describe "stream_records/1" do
    test "streams records lazily", %{tmp_dir: tmp_dir} do
      mods = for i <- 1..5 do
        ModuleDef.new("MyApp.Mod#{i}", "lib/mod#{i}.ex", 1, 10)
      end

      records = Enum.map(mods, &{&1, :ast, :high})
      Store.write_records(records, tmp_dir)

      stream = Store.stream_records(tmp_dir)
      assert is_struct(stream, Stream)

      loaded = Enum.to_list(stream)
      assert length(loaded) == 5
    end
  end
end
