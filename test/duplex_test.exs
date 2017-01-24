defmodule DuplexTest do
  use ExUnit.Case
  doctest Duplex
  import Duplex

  test "getting all .ex, .exs files" do
    assert Duplex.get_files("test") == ["test/test_helper.exs",
                                        "test/files_for_tests/example_code4.ex",
                                        "test/files_for_tests/example_code3.ex",
                                        "test/files_for_tests/example_code2.ex",
                                        "test/files_for_tests/example_code1.ex",
                                        "test/duplex_test.exs"]
    assert Duplex.get_files("path_does_not_exist") == []
  end

  def get_nodes(threshold, f_index \\ nil) do
    dir = "test/files_for_tests/"
    name = "example_code"
    ext = ".ex"
    f_names = ["#{dir}#{name}1#{ext}",
               "#{dir}#{name}2#{ext}",
               "#{dir}#{name}3#{ext}",
               "#{dir}#{name}4#{ext}"]
    files = if f_index do
      Enum.slice(f_names, f_index..f_index)
    else
      f_names
    end
    nodes = for file <- files do
      code_blocks(file, threshold)
    end
    nodes |> Enum.flat_map(&(&1))
  end

  test "example_code duplicates" do
    results = [[{"test/files_for_tests/example_code1.ex", {1, 14}, 13},
                {"test/files_for_tests/example_code2.ex", {1, 14}, 13},
                {"test/files_for_tests/example_code4.ex", {2, 16}, 13}]]
    f_name = "test_res.txt"
    dir = ["test/files_for_tests"]
    assert Duplex.show_similar(dir, nil, nil, f_name) == results
    assert Duplex.show_similar(dir, 20, nil, f_name) == results
    assert File.rm(f_name) == :ok
  end

  test "async works the same" do
    f_name = "test_res.txt"
    dir = ["test/files_for_tests"]
    four_th = Duplex.show_similar(dir, nil, 4, f_name)
    one_th = Duplex.show_similar(dir, nil, 1, f_name)
    assert four_th == one_th
    assert File.rm(f_name) == :ok
  end

  test "async file reading" do
    dir = "test/files_for_tests/"
    name = "example_code"
    ext = ".ex"
    files = ["#{dir}#{name}1#{ext}",
             "#{dir}#{name}2#{ext}",
             "#{dir}#{name}3#{ext}",
             "#{dir}#{name}4#{ext}"]
    chunks = for i <- 1..8 do
      Duplex.read_files(files, i, 7)
    end
    assert chunks |> Enum.uniq |> length == 1
  end

  test "shape hashes" do
    nodes1 = get_nodes(7, 0)
    nodes2 = get_nodes(7, 1)
    nodes3 = get_nodes(7, 2)
    {_, shape1} = nodes1 |> Enum.max_by(fn {_, shape} -> shape[:depth] end)
    {_, shape2} = nodes2 |> Enum.max_by(fn {_, shape} -> shape[:depth] end)
    {_, shape3} = nodes3 |> Enum.max_by(fn {_, shape} -> shape[:depth] end)
    h1 = shape1 |> Duplex.hash_shape
    h2 = shape2 |> Duplex.hash_shape
    h3 = shape3 |> Duplex.hash_shape
    assert h1 == h2
    assert h1 != h3
  end

  test "argparse" do
    args = ["--help", "--njobs", "10",
            "--threshold", "2", "--file",
            "/path/to/file.ex"]
    assert Duplex.parse_args(args) == {true, 2, 10, "/path/to/file.ex"}
  end

  test "this app has no duplicates" do
    assert Duplex.main(["lib"]) == []
  end

  test "escript" do
    assert Duplex.main(["--help"]) == Duplex.help_text
    assert Duplex.main == Duplex.show_similar
  end

  test "writting file" do
    f_name = "f.ex"
    assert Duplex.write_file(f_name, ["data1", "data2"]) == :ok
    assert File.read!(f_name) == "data1\ndata2\n"
    assert File.rm(f_name) == :ok
  end

end
