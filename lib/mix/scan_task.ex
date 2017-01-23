defmodule Mix.Tasks.Scan do
  use Mix.Task

  @shortdoc "Search for duplicates in the code"
  @moduledoc @shortdoc
  def run(_) do
    Duplex.show_similar
  end
end
