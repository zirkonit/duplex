defmodule Duplex.Mixfile do
  use Mix.Project

  def project do
    [app: :duplex,
     version: "0.1.1",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     description: description(),
     package: package(),
     test_coverage: [tool: Coverex.Task],
     deps: deps(),
     escript: escript()]
  end

  def application do
    [applications: [:logger]]
  end

  def escript do
    [main_module: Duplex]
  end

  defp deps do
    [
      {:dogma, "~> 0.1", only: :dev},
      {:dir_walker, ">= 0.0.0"},
      # {:exprof, "~> 0.2.0"},
      {:ex_doc, ">= 0.0.0", only: :dev},
      {:credo, "~> 0.5", only: [:dev, :test]},
      {:coverex, "~> 1.4.10", only: :test}
    ]
  end

  defp description do
    """
    Duplex allows you to search for similar code blocks inside your project.

    ## Usage
    ```
    mix escript.install https://github.com/zirkonit/duplex/duplex
    cd /path/to/project
    ~/.mix/escripts/duplex
    ```
    or
    ```elixir
    iex -S mix
    Duplex.show_similar
    ```
    """
  end

  defp package do
    [
     name: :duplex,
     # files: ["lib", "priv", "mix.exs", "README*", "readme*", "LICENSE*", "license*"],
     maintainers: ["Ivan Cherevko", "Andrew Koryagin"],
     licenses: ["Apache 2.0"],
     links: %{},
    ]
  end

end
