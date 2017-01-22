# Duplex

## Description

Duplex allows you to search for similar code blocks inside your Elixir project.

## Installation

1. Add `:duplicate_code_finder` to deps in `mix.exs`

```elixir
def deps do
  [{:duplicate_code_finder, "~> 0.1.1"}]
end
```
2. Update dependencies

```
mix deps.get
```

## Config

You can change default values on `config.exs` by adding next lines with your own values

```elixir
config :duplicate_code_finder, min_depth: 1 # filter AST nodes with depth more that min_depth
config :duplicate_code_finder, min_length: 3 # filter AST nodes with code-block length more than min_length
config :duplicate_code_finder, dirs: ["lib", "config", "web"] # directories to search for Elixir source files
config :duplicate_code_finder, n_jobs: 4 # number of threads
```

## Usage

```elixir
iex -S mix
Duplex.show_similar
```