defmodule Mix.Tasks.Duplex do
  use Mix.Task

  def run(args) do
    Duplex.main(args)
  end
end
