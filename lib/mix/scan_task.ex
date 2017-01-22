defmodule Mix.Tasks.Scan do
  use Mix.Task

  @shortdoc "Search for duplicates in the code"
  def run(_) do
    Duplex.show_similar
  end
end
