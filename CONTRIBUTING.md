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

# Rust
mix rust.check
```

> **Note:** CI enforces **100% test coverage** on the Elixir side (NIF modules are
> excluded). If you add new public functions or branches, make sure to add
> corresponding tests. Run `mix test --cover` locally to check before pushing.

### Distribution tests

Full cross-node integration tests for the Erlang distribution transport are tagged `:distributed` and **excluded by default** (they require the test node to be distributed). To run them:

```sh
# Run only distributed tests
elixir --sname test -S mix test --only distributed

# Run all tests (unit + distributed)
elixir --sname test -S mix test --include distributed
```

### Regression tests

The `:slow` tag is reserved for heavyweight regression tests such as isolated parallel cold-compile checks that would otherwise dominate local test time.

```sh
# Run only slow tests
mix test --only slow

# Include slow tests alongside the default suite
mix test --include slow
```

## Branching and Commits

- Branch from `main` for all work.
- Keep commits focused and atomic — one logical change per commit.
- Prefix commit subjects with a type: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`.

## Pull Requests

Before submitting a PR, make sure the following pass:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix dialyzer
mix test --cover
mix rust.check
```

### PR Guidelines

- Each PR should stay focused on a single feature or fix.
- Follow the existing code style and patterns in the codebase.
- Make sure CI passes before requesting review.

### Documentation Expectations

- Every new public function should include both a `@doc` and a `@spec`. Prefer runnable `## Examples` — doctests count toward the 100% coverage bar.
- Every new public module should have a `@moduledoc` describing its purpose.
- New widgets need three things:
  1. A `@moduledoc` with field descriptions and at least one usage example.
  2. An entry in the [Building UIs](guides/core/building_uis.md) guide.
  3. An entry in the [widgets cheatsheet](guides/cheatsheets/widgets.cheatmd).
- Any new feature or changed behaviour should have a CHANGELOG entry under `[Unreleased]`, grouped under `Added` / `Changed` / `Fixed` / `Removed` per [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
- Breaking changes should include a "Migration" note in the CHANGELOG entry that explains what callers need to change.
- If a feature introduces a guide-worthy topic, add or update a guide in `guides/` and update the README accordingly.
- Run `mix docs` locally and skim the output — broken links and missing `extras` entries are easy to miss.

### Testing Expectations

- **Widgets** — add a widget-level test using the headless backend (`ExRatatui.init_test_terminal/2`). See [Testing](guides/internals/testing.md).
- **Runtime / app behaviour** — add an app-level test under `test_mode`, driving the runtime with `ExRatatui.Runtime.inject_event/2` and asserting on snapshots or emitted messages.
- **Transports** — if your change touches SSH or Erlang distribution, extend the tagged suites (`:distributed`, `:slow`).
- Coverage is enforced at 100% on the Elixir side (NIFs excluded). Run `mix test --cover` before pushing.
