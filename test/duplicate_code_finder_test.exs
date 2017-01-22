defmodule DuplexTest do
  use ExUnit.Case
  doctest Duplex
  import Duplex

  test "getting all .ex, .exs files" do
    assert Duplex.get_files("lib") == ["lib/mix/scan_task.ex", "lib/duplicate_code_finder.ex"]
    assert Duplex.get_files("path_does_not_exist") == []
  end

  test "AST node shapes comparison" do
    shape1 = "test/files_for_tests/example_code1.txt"
            |> Duplex.get_ast
            |> Duplex.get_shape
    shape2 = "test/files_for_tests/example_code2.txt"
            |> Duplex.get_ast
            |> Duplex.get_shape
    shape3 = "test/files_for_tests/example_code3.txt"
            |> Duplex.get_ast
            |> Duplex.get_shape
    assert shape1 != shape2
    assert Duplex.is_equal(shape1, shape2)
    assert shape1 != shape3
    assert shape2 != shape3
    assert not Duplex.is_equal(shape1, shape3)
    assert not Duplex.is_equal(shape2, shape3)
  end

  test "_this app code_ has duplicates" do
    assert Duplex.show_similar == []
  end

  def get_nodes(d, l) do
    dir = "test/files_for_tests/"
    name = "example_code"
    ext = ".txt"
    files = ["#{dir}#{name}1#{ext}", "#{dir}#{name}2#{ext}", "#{dir}#{name}3#{ext}", "#{dir}#{name}4#{ext}"]
    nodes = for file <- files do
      code_blocks(file, d, l)
    end
    {_, nodes} = Enum.flat_map_reduce(nodes, [], fn item, acc -> {item, acc ++ item} end)
    nodes
  end

  test "equal code groups" do
    equals = [[{"test/files_for_tests/example_code1.txt", {1, 11}},
               {"test/files_for_tests/example_code2.txt", {1, 11}},
               {"test/files_for_tests/example_code4.txt", {2, 12}}]]

    nodes = get_nodes(1, 1)
    assert Duplex.equal_code(nodes, 1) == equals
    nodes = get_nodes(1, 11)
    assert Duplex.equal_code(nodes, 1) == equals
    nodes = get_nodes(1, 12)
    assert Duplex.equal_code(nodes, 1) == []
    nodes = get_nodes(12, 1)
    assert Duplex.equal_code(nodes, 1) == equals
    nodes = get_nodes(13, 1)
    assert Duplex.equal_code(nodes, 1) == []
  end

  test "compare nodes properly in case of async calculations" do
    nodes = get_nodes(1, 1)
    len = length(nodes)
    assert compare_nodes(nodes, len, 0, len - 2) == compare_nodes(nodes, len, 0, 10) ++ compare_nodes(nodes, len, 11, len - 2)
  end

  test "ranges for async jobs" do
    ranges = Duplex.get_ranges_for_jobs(300, 4)
    {start, _} = hd(ranges)
    assert start == 0
    {_, e} = ranges |> Enum.reverse |> hd
    assert e == 298
    assert Duplex.get_ranges_for_jobs(200, 1) == [{0, 198}]
    assert Duplex.get_ranges_for_jobs(1, 8) == []
    assert Duplex.get_ranges_for_jobs(2, 8) == [{0, 0}]
  end

  test "async calculations give the same result" do
    nodes = get_nodes(1, 1)
    assert Duplex.equal_code(nodes, 1) == Duplex.equal_code(nodes, 4)
    assert Duplex.equal_code(nodes, 2) == Duplex.equal_code(nodes, 9)
  end

  test "async file reading" do
    dir = "test/files_for_tests/"
    name = "example_code"
    ext = ".txt"
    files = ["#{dir}#{name}1#{ext}", "#{dir}#{name}2#{ext}", "#{dir}#{name}3#{ext}", "#{dir}#{name}4#{ext}"]
    chunks = for i <- 1..8 do
      Duplex.read_files(files, i, 1, 1)
    end
    assert chunks |> Enum.uniq |> length == 1
  end

end
