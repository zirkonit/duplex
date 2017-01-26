# Duplex

## Description

Duplex allows you to search for similar code blocks inside your Elixir project.

## Installation as escript
Remotely (without repository cloning)
```
mix escript.install https://raw.githubusercontent.com/zirkonit/duplex/master/duplex
```

Locally
```
mix do escript.build, escript.install
```

## Usage as escript
```
cd /path/to/project
~/.mix/escripts/duplex
```

## Installation as dependency

1. Add `:duplex` to deps in `mix.exs`

```elixir
def deps do
  [{:duplex, "~> 0.1.1"}]
end
```
2. Update dependencies

```
mix deps.get
```

## Usage as dependency

```elixir
iex -S mix
Duplex.show_similar
```

## Config

You can change default values on `config.exs` by adding next lines with your own values

```elixir
config :duplex, threshold: 7 # filter AST nodes with `node.length + node.depth >= threshold`
# Than lower threshold, than simpler nodes will be included.
# Optimal value is around 7-10. Default is 7.
config :duplex, dirs: ["lib", "config", "web"] # directories to search for Elixir source files
config :duplex, n_jobs: 4 # number of threads
```
