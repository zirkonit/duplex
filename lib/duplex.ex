defmodule Duplex do

  @moduledoc """
    Duplex allows you to search for similar code blocks inside your Elixir
    project.
  """

  def help_text do
    """
    Duplex escript usage:

    --help - show this message
    --threshold - filter AST nodes by `node.length + node.depth >= threshold`.
                  Than lower threshold, than simpler nodes will be included.
                  Optimal value is around 7-10. Default is 7.
    --njobs - number of threads will be used for AST parsing
    --file - file to export output
    """
  end

  def parse_args(args) do
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
    help = extract.(args, :help, false)
    threshold = extract.(args, :threshold, true)
    n_jobs = extract.(args, :njobs, true)
    export_file = extract.(args, :file, false)
    {help, threshold, n_jobs, export_file}
  end

  def main(args \\ []) do
    {help, threshold, n_jobs, export_file} = parse_args(args)
    if help do
      IO.puts help_text
      help_text
    else
      Duplex.show_similar(nil, threshold, n_jobs, export_file)
    end
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

  defp filter_nodes(nodes) do
    nodes |> Enum.uniq |> Enum.filter(fn item ->
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
  end

  # Get all informative nodes from AST tree
  def code_blocks(file, threshold) do
    {_, nodes} = visit(get_ast(file), [])
    nodes = filter_nodes(nodes)
    # calculate shapes only once
    nodes = for n <- nodes, do: {{n, file}, get_shape(n)}
    # filter short blocks, non deep blocks
    nodes = nodes |> Enum.filter(fn x -> valid_line_numbers?(x) end)
    nodes = nodes |> Enum.filter(fn x -> deep_long?(x, threshold) end)
    nodes = nodes |> Enum.reverse |> Enum.uniq_by(fn {_, s} -> s[:lines] end)
    nodes |> Enum.reverse
  end

  defp valid_line_numbers?({_, %{lines: {min, max}, depth: _}}) do
    (max != nil) and (min != nil)
  end

  defp deep_long?({_, %{lines: {min, max}, depth: depth}}, threshold) do
    len = max - min + 1
    len + depth >= threshold
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

  defp get_configs(dirs, threshold, n_jobs) do
    d_dirs = ["lib", "config", "web"]
    {d_threshold, d_n_jobs} = {7, 4}

    c_dirs = Application.get_env(:duplex, :dirs)
    c_threshold = Application.get_env(:duplex, :threshold)
    c_n_jobs = Application.get_env(:duplex, :n_jobs)
    choose_one = fn i, j, k ->
      if i, do: i, else: if j, do: j, else: k
    end
    dirs = choose_one.(dirs, c_dirs, d_dirs)
    threshold = choose_one.(threshold, c_threshold, d_threshold)
    n_jobs = choose_one.(n_jobs, c_n_jobs, d_n_jobs)

    {dirs, threshold, n_jobs}
  end

  defp read_by_chunk(chunks, threshold) do
    tasks = for files <- chunks do
      Task.async(fn ->
        nodes = for file <- files do
          code_blocks(file, threshold)
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

  def read_files(files, n_jobs, threshold) do
    n_jobs = if n_jobs <= 0, do: 1, else: n_jobs
    n_jobs = if length(files) < n_jobs, do: length(files), else: n_jobs
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
    read_by_chunk(chunks, threshold)
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
        spaces = item |> to_charlist |> Enum.reduce_while(0, f)
        if spaces >= first do
          get_additional_lines(current ++ [item], min, max + 1, content)
        else
          {current, min, max}
        end
      else
        {current, min, max}
      end
    else
      {current, min, max}
    end
  end

  defp get_output_data(groups, content) do
    space = ["---------------------------------------------------------------"]
    # get data to show
    all_data = for group <- groups do
      gr = for item <- group |> Enum.reverse do
        {file, {min, max}, _} = item
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
    all_data |> flatten
  end

  # Main function to find equal code parts.
  # dirs - directories to scan for elixir source files
  # export_file - if not nil, write results to the file by this path
  def show_similar(dirs \\ nil, t_hold \\ nil, n_jobs \\ nil, export \\ nil) do
    configs = get_configs(dirs, t_hold, n_jobs)
    {dirs, t_hold, n_jobs} = configs
    # scan dirs
    files = for d <- dirs do
      get_files(d)
    end
    files = files |> flatten
    IO.puts "Reading files..."
    nodes = read_files(files, n_jobs, t_hold)
    # get map of file contents (key, balue = filename, content)
    content = read_content(Map.new(), files)
    IO.puts "Searching for duplicates..."
    # get grouped equal code blocks
    groups = nodes |> equal_code
    all_data = groups |> get_output_data(content)
    nothing_found = "There are no duplicates"
    if export == nil do
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
      write_file(export, all_data)
    end
    groups
  end

  def write_file(filename, data) do
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

  defp timeout do
    1_000 * 60 * 30
  end

  def hash_map(nodes, map \\ %{}) do
    if length(nodes) > 0 do
      {{n, file}, s} = nodes |> hd
      hash = hash_shape(s)
      map = if hash in Map.keys(map) do
        Map.put(map, hash, map[hash] ++ [{file, s[:lines], s[:depth]}])
      else
        Map.put(map, hash, [{file, s[:lines], s[:depth]}])
      end
      hash_map(nodes |> tl, map)
    else
      map
    end
  end

  def hash_shape(shape, hash \\ "") do
    tmp = if shape[:variable], do: "var", else: inspect(shape[:name])
    current = "#{hash}#{tmp}#{length(shape[:children])}"
    if length(shape[:children]) > 0 do
      ch_hashes = for ch <- shape[:children] do
        hash_shape(ch)
      end
      current <> (ch_hashes |> Enum.join(""))
    else
      current
    end
  end

  # Find equal code parts
  def equal_code(nodes) do
    groups = nodes |> hash_map
    # keep only groups with size > 1
    hashes = groups |> Map.keys
    single_nodes = hashes |> Enum.filter(fn hash ->
      length(groups[hash]) == 1
    end)
    groups = Map.drop(groups, single_nodes)
    # filter subsamples
    keys = Map.keys(groups)
    not_subsamples = Enum.filter(keys, fn hash ->
      not subsample?(hash, keys)
    end)
    groups = for hash <- not_subsamples, do: groups[hash]
    groups = for gr <- groups do
      gr |> Enum.sort_by(fn {file, {min, _}, _} ->
        {file, -min}
      end)
    end
    groups |> Enum.sort_by(fn gr ->
      {_, {min, max}, depth} = gr |> hd
      - (max - min + depth) * length(gr)
    end)
  end

  defp subsample?(hash, keys) do
    tmp = for key <- keys do
      String.length(hash) < String.length(key) and String.contains?(key, hash)
    end
    Enum.any?(tmp)
  end

  # Get children of the node
  defp children(tnode) do
    case tnode do
      {_, _, nodes} ->
        nodes
      _ ->
        cond do
          Keyword.keyword?(tnode) ->
            tnode |> Enum.into(%{}) |> Map.values
          is_list(tnode) ->
            tnode
          true ->
            nil
        end
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
