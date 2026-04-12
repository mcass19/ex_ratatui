# Contributing to ExRatatui

Thanks for your interest in contributing!

ExRatatui is a Rust NIF project, so contributions touch both Elixir and Rust code.

This guide will help you get set up.

## Setup

1. Clone the repo:

```sh
git clone https://github.com/mcass19/ex_ratatui.git
cd ex_ratatui
```

2. Install dependencies:

- **Elixir** 1.17+ and **Erlang/OTP** 26+
- **Rust** toolchain via [rustup](https://rustup.rs/)

3. Fetch deps and compile from source:

```sh
mix deps.get
export EX_RATATUI_BUILD=true
mix compile
```

The `EX_RATATUI_BUILD=true` env var tells the library to compile the Rust NIF
from source instead of downloading a precompiled binary.

## Running Tests

```sh
# Elixir tests (includes doctests)
mix test

# Elixir tests with coverage report
mix test --cover

# Rust tests
cargo test --manifest-path native/ex_ratatui/Cargo.toml
```

The default `mix test` run excludes tests tagged `:distributed` and `:slow`.
The `:slow` tag is reserved for heavyweight regression tests such as isolated
parallel cold-compile checks that would otherwise dominate local test time.

```sh
# Run only slow tests
mix test --only slow

# Include slow tests alongside the default suite
mix test --include slow
```

### Distribution integration tests

Full cross-node integration tests for the Erlang distribution transport are tagged `:distributed` and **excluded by default** (they require the test node to be distributed). To run them:

```sh
# Run only distribution integration tests
elixir --sname test -S mix test --only distributed

# Run all tests (unit + integration)
elixir --sname test -S mix test --include distributed
```

> **Note:** CI enforces **100% test coverage** on the Elixir side (NIF modules are
> excluded). If you add new public functions or branches, make sure to add
> corresponding tests. Run `mix test --cover` locally to check before pushing.

## Pull Requests

Before submitting a PR, make sure the following pass:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix dialyzer
mix rust.check
```

- Keep PRs focused — one feature or fix per PR
- Add tests for new functionality
- Update documentation (moduledocs, CHANGELOG, README if applicable)
- Follow existing code style and patterns
- Ensure CI passes before requesting review
