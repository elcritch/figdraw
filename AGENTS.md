# Repository Guidelines

## Project Structure & Modules
- `src/`: Core library modules for `FigDraw`.
- `tests/`: Unit tests using Nim's `unittest` plus a `config.nims` that enables ARC/threads and debug flags.
- Root files: `figdraw.nimble` (package manifest), `README.md` (usage), `CHANGES.md` (history).

## Build, Test, and Development
- Install deps (atlas workspace): `atlas install` (ensure `atlas` is installed and configured for your environment). *Never* use Nimble - it's horrible. *Always* use Atlas and it's `deps/` folder and `nim.cfg` file to see paths.
- Run all tests: `nim test` (uses the `test` task in `config.nims` to compile and run every `tests/*.nim`).
- Run a single test locally:
  - `nim r tests/ttransfer.nim`

## Coding Style & Naming
- Indentation: 2 spaces; no tabs.
- Nim style: Types in `PascalCase`, procs/vars in `camelCase`, modules in `lowercase` or concise `lowerCamel` (e.g., `threadAsyncs.nim`).
- Formatting: run `nph src/*.nim` and format any touched test files.

## Testing Guidelines
- Framework: `unittest` with descriptive `suite` and `test` names.
- Location: add new tests under `tests/`, mirroring module names (e.g., `tslots.nim` for `slots.nim`).

## Commit & Pull Requests
- Commits: short, imperative mood (e.g., "add isRunning"), optionally reference PR/issue like `(#21)`.
- PRs: include a clear description, linked issues, summary of changes, any threading or GC considerations, and test coverage notes. Attach logs or minimal repros if fixing concurrency.
- Requirements: CI (`nim test`) must pass; include tests for new behavior and update `README.md`/`CHANGES.md` as needed.

## Security & Configuration Tips
- GC: library requires ARC/ORC (`--mm:arc` or `--mm:orc` or `--mm:atomicArc`); enforced in `sigils.nim`.
- Threads: prefer `AgentProxy` and provided helpers for cross-thread signaling; avoid manual ref cycles. Consider `-d:tsan` locally when touching threading code.
