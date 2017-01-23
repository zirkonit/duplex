defmodule Duplex do

  @moduledoc """
    Duplex allows you to search for similar code blocks inside your Elixir
    project.
  """

  defp parse_args(args) do
    {args, _, _} = OptionParser.parse(args)
    args = args |> Enum.into(%{})
    extract = fn args, key, to_int ->
      if key in Map.keys(args) do
        if to_int do
          {parsed, _} = Integer.parse(args[key])
          parsed
        else
          args[key]
        end
      else
        nil
      end
    end
    min_depth = extract.(args, :mindepth, true)
    min_length = extract.(args, :minlength, true)
    n_jobs = extract.(args, :njobs, true)
    export_file = extract.(args, :export, false)
    {min_depth, min_length, n_jobs, export_file}
  end

  def main(args \\ []) do
    {min_depth, min_length, n_jobs, export_file} = parse_args(args)
    Duplex.show_similar(nil, min_depth, min_length, n_jobs, export_file)
  end

  defp flatten(e) do
    Enum.flat_map(e, &(&1))
  end

  # Recursively scan directory to find elixir source files
  def get_files(dir) do
    if File.exists?(dir) do
      {:ok, walker} = DirWalker.start_link(dir)
      walker |> DirWalker.next(100_000_000) |> Enum.filter(fn item ->
        ext = item |> String.split(".") |> Enum.reverse |> hd
        (ext == "ex") or (ext == "exs")
      end)
    else
      []
    end
  end

  def get_ast(filename) do
    try do
      Code.string_to_quoted!(File.read!(filename))
    rescue
      _ ->
        nil
    end
  end

  # Recursive AST tree search to get all it's nodes
  defp visit(tnode, nodes) do
    nodes = nodes ++ [tnode]
    ch = children(tnode)
    if ch do
      new_nodes = for c <- ch do
        {_, nodes} = visit(c, nodes)
        nodes
      end
      nodes = new_nodes |> flatten
      {ch, nodes}
    else
      {[], nodes}
    end
  end

  # Get all informative nodes from AST tree
  def code_blocks(file, min_depth, min_length) do
    {_, nodes} = visit(get_ast(file), [])
    nodes = nodes |> Enum.uniq |> Enum.filter(fn item ->
      case item do
        {_, _, nil} ->
          false
        {_, _, c} when is_list(c) ->
          true
        {_, _, _} ->
          false
        nil ->
          false
        _ ->
          !(Keyword.keyword?(item)) and is_tuple(item)
      end
    end)
    # calculate shapes only once
    nodes = for n <- nodes, do: {{n, file}, get_shape(n)}
    # filter short blocks, non deep blocks
    nodes = nodes |> Enum.filter(fn x -> deep?(x, min_depth) end)
    nodes = nodes |> Enum.filter(fn x -> long?(x, min_length) end)
    nodes = nodes |> Enum.reverse |> Enum.uniq_by(fn {_, s} -> s[:lines] end)
    nodes |> Enum.reverse
  end

  defp deep?({_, %{lines: {_, _}, depth: depth}}, min_depth) do
    depth >= min_depth
  end

  defp long?({_, %{lines: {min, max}, depth: _}}, min_length) do
    (max != nil) and (min != nil) and (max - min + 1 >= min_length)
  end

  defp read_content(map, files) do
    if length(files) > 0 do
      file = hd(files)
      map = map |> Map.put(file, file |> File.read! |> String.split("\n"))
      read_content(map, tl(files))
    else
      map
    end
  end

  defp get_configs(dirs, min_depth, min_length, n_jobs) do
    d_dirs = ["lib", "config", "web"]
    {d_min_depth, d_min_length, d_n_jobs} = {1, 4, 4}

    c_dirs = Application.get_env(:duplex, :dirs)
    c_min_depth = Application.get_env(:duplex, :min_depth)
    c_min_length = Application.get_env(:duplex, :min_length)
    c_n_jobs = Application.get_env(:duplex, :n_jobs)
    choose_one = fn i, j, k ->
      if i, do: i, else: if j, do: j, else: k
    end
    dirs = choose_one.(dirs, c_dirs, d_dirs)
    min_depth = choose_one.(min_depth, c_min_depth, d_min_depth)
    min_length = choose_one.(min_length, c_min_length, d_min_length)
    n_jobs = choose_one.(n_jobs, c_n_jobs, d_n_jobs)

    {dirs, min_depth, min_length, n_jobs}
  end

  def read_files(files, n_jobs, min_depth, min_length) do
    n_jobs = if n_jobs <= 0 do
      1
    else
      n_jobs
    end
    n_jobs = if length(files) < n_jobs do
      length(files)
    else
      n_jobs
    end
    size = div(length(files), n_jobs)
    chunks = for n <- 0..(n_jobs - 1) do
      cond do
        n == 0 ->
          Enum.slice(files, 0, size)
        n == n_jobs - 1 ->
          Enum.slice(files, n * size, 2 * size)
        true ->
          Enum.slice(files, n * size, size)
        end
    end
    tasks = for files <- chunks do
      Task.async(fn ->
        nodes = for file <- files do
          code_blocks(file, min_depth, min_length)
        end
        nodes = nodes |> flatten
        nodes
      end)
    end
    nodes = for task <- tasks do
      Task.await(task, timeout)
    end
    nodes = nodes |> flatten
    nodes
  end

  defp get_additional_lines(current, min, max, content) do
    f = fn i, acc ->
      if i == " " |> to_charlist |> hd do
        {:cont, acc + 1}
      else
        {:halt, acc}
      end
    end
    first = current |> hd |> to_charlist |> Enum.reduce_while(0, f)
    last = current |> Enum.reverse |> hd |> to_charlist
    last = last |> Enum.reduce_while(0, f)
    if first != last do
      item = content |> Enum.slice(max + 1..max + 1) |> hd
      if String.trim(item) == "end" do
        get_additional_lines(current ++ [item], min, max + 1, content)
      else
        {current, min, max}
      end
    else
      {current, min, max}
    end
  end

  # Main function to find equal code parts.
  # dirs - directories to scan for elixir source files
  # export_file - if not nil, write results to the file by this path
  def show_similar(dirs \\ nil, min_depth \\ nil, min_length \\ nil, n_jobs \\ nil, export_file \\ nil) do
     configs = get_configs(dirs, min_depth, min_length, n_jobs)
     {dirs, min_depth, min_length, n_jobs} = configs
    # scan dirs
    files = for d <- dirs do
      get_files(d)
    end
    files = files |> flatten
    IO.puts "Reading files..."
    nodes = read_files(files, n_jobs, min_depth, min_length)
    # get map of file contents (key, balue = filename, content)
    content = read_content(Map.new(), files)
    IO.puts "Searching for duplicates..."
    # get grouped equal code blocks
    groups = equal_code(nodes, n_jobs)
    space = ["---------------------------------------------------------------"]
    # get data to show
    all_data = for group <- groups do
      gr = for item <- group |> Enum.reverse do
        {file, {min, max}} = item
        min = min - 1
        max = max - 1
        c = Enum.slice(content[file], min..max)
        {c, min, max} = get_additional_lines(c, min, max, content[file])
        c = Enum.zip(min + 1..max + 1, c)
        c = for l <- c do
          {number, line} = l
          "#{number}: #{line}"
        end
        ["#{file}:"] ++ c ++ [""]
      end
      gr = gr |> flatten
      gr ++ space
    end
    all_data = all_data |> flatten
    nothing_found = "There are no duplicates"
    if export_file == nil do
      for item <- all_data do
        IO.puts item
      end
      if length(all_data) == 0 do
        IO.puts nothing_found
      end
    else
      all_data = if length(all_data) == 0 do
        [nothing_found]
      else
        all_data
      end
      write_file(export_file, all_data)
    end
    groups
  end

  defp write_file(filename, data) do
    try do
      {:ok, file} = File.open(filename, [:write])
      for d <- data do
        IO.binwrite(file, "#{d}\n")
      end
      File.close(file)
    rescue
      _ ->
        :error
    end
  end

  # Transform data from pairs to groups by equality
  defp group_equals(equals, grouped) do
    len = length(equals)
    if len > 0 do
      # fetch the first equal part from equals list
      {{n1, n2}, {lines1, lines2}, {s1, _}} = equals |> Enum.fetch!(0)
      # find pairs which have the same shape as the first pair
      group = if len > 1 do
        for i <- 1..len - 1 do
          {{n3, n4}, {lines3, lines4}, {_, s2}} = equals |> Enum.fetch!(i)
          if is_equal(s1, s2) do
            [{n3, lines3}, {n4, lines4}]
          else
            []
          end
        end
      else
        [[]]
      end
      group = group |> flatten
      group = [{n1, lines1}, {n2, lines2}] ++ group
      group = group |> Enum.filter(fn item -> item != nil end) |> Enum.uniq
      # add new group
      grouped = grouped ++ [group]
      # filter from equals list all pairs we found
      equals = Enum.filter(equals, fn item ->
        {{n1, n2}, {lines1, lines2}, _} = item
        not ({n1, lines1} in group and {n2, lines2} in group)
      end)
      # run recursively with new {equals, grouped}
      group_equals(equals, grouped)
    else
      {[], grouped}
    end
  end

  def compare_nodes(nodes, len_nodes, from, until) do
    # compare nodes with each other
    equals = if len_nodes > 2 do
      for i <- from..until do
        for j <- (i + 1)..(len_nodes - 1) do
          {{n1, file1}, s1} = Enum.fetch!(nodes, i)
          {{n2, file2}, s2} = Enum.fetch!(nodes, j)
          if is_equal(s1, s2) do
            {{{n1, file1}, {n2, file2}}, {s1[:lines], s2[:lines]}, {s1, s2}}
          end
        end
      end
    else
      [[]]
    end
    equals = equals |> flatten
    Enum.filter(equals, fn item -> item != nil end)
  end

  defp ranges(len, size, n_jobs, n, prev_end) do
    cond do
      n == 1 ->
        [{0, size}] ++ ranges(len, size, n_jobs, n + 1, size)
      n == n_jobs ->
        if prev_end + 1 < len - 2 do
          [{prev_end + 1, len - 2}]
        else
          []
        end
      true ->
        e = min(prev_end + size * n, len - 2)
        [{prev_end + 1, e}] ++ ranges(len, size, n_jobs, n + 1, e)
    end
  end

  def get_ranges_for_jobs(len, n_jobs) do
    cond do
      len < 2 ->
        []
      n_jobs < 1 ->
        get_ranges_for_jobs(len, 1)
      (len < 10) or (n_jobs == 1) ->
        [{0, len - 2}]
      n_jobs > len ->
        get_ranges_for_jobs(len, div(len, n_jobs))
      true ->
        size = div(len, Enum.sum(1..n_jobs))
        ranges(len, size, n_jobs, 1, -1)
    end
  end

  defp timeout do
    1_000 * 60 * 30
  end

  # Find equal code parts
  def equal_code(nodes, n_jobs) do
    len = length(nodes)
    tasks = for range <- get_ranges_for_jobs(len, n_jobs) do
      {min, max} = range
      Task.async(fn -> compare_nodes(nodes, len, min, max) end)
    end
    equals = for t <- tasks do
      Task.await(t, timeout)
    end
    equals = equals |> flatten
    # filter subsamples
    equals = equals |> equal_blocks
    equals = for {e, is_subsample} <- equals do
      unless Enum.any?(is_subsample), do: e
    end
    equals = equals |> Enum.filter(fn item -> item != nil end)
    # transform data from pairs to groups by equality
    {_, grouped} = group_equals(equals, [])
    # keep only filename, {min, max} line numbers of block
    groups = for group <- grouped do
      for item <- group do
        {{_, file}, lines} = item
        {file, lines}
      end
    end
    groups |> Enum.sort_by(fn gr ->
      {_, {min, max}} = gr |> hd
      - (max - min) * length(gr)
    end)
  end

  defp equal_blocks(equals) do
    for e1 <- equals do
      arr = for e2 <- equals do
        {{_, _}, {{min1, max1}, {min2, max2}}, {s1, _}} = e1
        {{_, _}, {{min3, max3}, {min4, max4}}, {s3, _}} = e2
        (s1[:depth] < s3[:depth]) and
        (min1 >= min3) and
        (max1 <= max3) and
        (min2 >= min4) and
        (max2 <= max4)
      end
      {e1, arr}
    end
  end

  # Get children of the node
  defp children(tnode) do
    case tnode do
      {_, _, nodes} ->
        nodes
      _ ->
        try do
          # works when node like [do: data1, else: data2]
          # returns [data1, data2]
          tnode = Enum.into(tnode, %{})
          Map.values(tnode)
        rescue
          _ ->
            if is_list(tnode) do
              tnode
            else
              nil
            end
        end
    end
  end

  # Comparison of 2 nodes by their shapes
  def is_equal(s1, s2) do
    # assume different variable names as equal
    current_eq = (s1[:variable] and s2[:variable]) or (s1[:name] == s2[:name])
    # assume different variable names as different
    # current_eq = s1[:name] == s2[:name]
    eq = if current_eq and s1[:depth] == s2[:depth] do
      if length(s1[:children]) == length(s2[:children]) do
        ch_eq = for {c1, c2} <- Enum.zip(s1[:children], s2[:children]) do
          is_equal(c1, c2)
        end
        Enum.all?(ch_eq)
      end
    end
    if eq == nil do
      false
    else
      eq
    end
  end

  # Get structured shape of the node for comparison
  def get_shape(tnode) do
    ch = children(tnode)
    ch = if ch do
      for c <- ch do
        get_shape(c)
      end
    else
      []
    end
    depth = if length(ch) == 0 do
      1
    else
      Enum.max_by(ch, fn item -> item[:depth] end)[:depth] + 1
    end
    case tnode do
      {name, _, content} ->
        # is node a variable?
        var = (content == nil)
        name = if is_atom(name) do
          name
        else
          "_"
        end
        %{name: name,
         lines: get_lines(tnode),
      children: ch,
      variable: var,
         depth: depth}
      _ ->
        if is_integer(tnode) or is_float(tnode) do
            %{name: tnode,
             lines: get_lines(tnode),
          children: ch,
          variable: false,
             depth: depth}
        else
            %{name: "_",
             lines: get_lines(tnode),
          children: ch,
          variable: false,
             depth: depth}
        end
    end
  end

  # Recursively go through the node and finds {min, max} line numbers
  defp get_lines(tnode, main \\ true) do
    current = case tnode do
      {_, data, _} ->
        case data do
          [line: l] ->
            l
          [counter: _, line: l] ->
            l
          _ ->
            nil
        end
      _ ->
        nil
    end
    ch = children(tnode)
    from_ch = if ch do
      for c <- ch do
        get_lines(c, false)
      end
    else
      []
    end
    from_ch = from_ch |> flatten
    current = Enum.filter(from_ch, fn item -> item != nil end) ++ [current]
    current = Enum.uniq(current)
    if main do
      {Enum.min(current), Enum.max(current)}
    else
      current
    end
  end

end
