defmodule DuplexTest do
  use ExUnit.Case
  doctest Duplex
  import Duplex

  test "getting all .ex, .exs files" do
    assert Duplex.get_files("lib") == ["lib/mix/scan_task.ex", "lib/duplex.ex"]
    assert Duplex.get_files("path_does_not_exist") == []
  end

  test "_this app code_ has no duplicates" do
    assert Duplex.show_similar == []
  end

  def get_nodes(threshold) do
    dir = "test/files_for_tests/"
    name = "example_code"
    ext = ".txt"
    files = ["#{dir}#{name}1#{ext}", "#{dir}#{name}2#{ext}", "#{dir}#{name}3#{ext}", "#{dir}#{name}4#{ext}"]
    nodes = for file <- files do
      code_blocks(file, threshold)
    end
    nodes |> Enum.flat_map(&(&1))
  end

  test "equal code groups" do
    equals = [[{"test/files_for_tests/example_code1.txt", {1, 11}, 12},
               {"test/files_for_tests/example_code2.txt", {1, 11}, 12},
               {"test/files_for_tests/example_code4.txt", {2, 12}, 12}]]

    nodes = get_nodes(7)
    assert Duplex.equal_code(nodes) == equals
  end

  test "async file reading" do
    dir = "test/files_for_tests/"
    name = "example_code"
    ext = ".txt"
    files = ["#{dir}#{name}1#{ext}", "#{dir}#{name}2#{ext}", "#{dir}#{name}3#{ext}", "#{dir}#{name}4#{ext}"]
    chunks = for i <- 1..8 do
      Duplex.read_files(files, i, 7)
    end
    assert chunks |> Enum.uniq |> length == 1
  end

  test "shape hashes" do
    dir = "test/files_for_tests/"
    name = "example_code"
    ext = ".txt"
    files = ["#{dir}#{name}1#{ext}", "#{dir}#{name}2#{ext}", "#{dir}#{name}3#{ext}"]
    [nodes1, nodes2, nodes3] = for file <- files do
      code_blocks(file, 7)
    end
    {_, shape1} = nodes1 |> Enum.max_by(fn {_, shape} -> shape[:depth] end)
    {_, shape2} = nodes2 |> Enum.max_by(fn {_, shape} -> shape[:depth] end)
    {_, shape3} = nodes3 |> Enum.max_by(fn {_, shape} -> shape[:depth] end)
    h1 = shape1 |> Duplex.hash_shape
    h2 = shape2 |> Duplex.hash_shape
    h3 = shape3 |> Duplex.hash_shape
    assert h1 == h2
    assert h1 != h3
  end

end
