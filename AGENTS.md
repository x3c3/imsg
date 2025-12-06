# Repository Guidelines

## Project Structure & Module Organization
- `cmd/imsg` holds the CLI entrypoint (`main.go`) and top-level Cobra command wiring.
- `internal/db`, `internal/watch`, `internal/send`, `internal/util` contain SQLite access, polling/streaming, AppleScript send logic, and helpers; keep shared code inside `internal` to avoid external API drift.
- `bin/` is created by the build script for local artifacts; `coverage.out` is optional and should not be committed unless updating reports.

## Build, Test, and Development Commands
- `pnpm imsg` (or `go run ./cmd/imsg`) — run the CLI locally.
- `pnpm build` — compile to `bin/imsg` using the current module versions.
- `pnpm lint` — run `golangci-lint` with `gofmt`, `goimports`, `revive`, `staticcheck`, etc.; fix before sending a PR.
- `pnpm test` — execute `go test ./...`; use `-run` to target specific packages when iterating.

## Coding Style & Naming Conventions
- Go 1.24 module; rely on standard library patterns, idiomatic error handling, and early returns.
- Formatting is enforced by `gofmt`/`goimports`; do not hand-edit import order or indentation (tabs per Go defaults).
- Keep package-visible types intentional; prefer concrete types over `interface{}` and avoid global state in `internal` packages.
- Cobra command flags: prefer long-form, kebab-case (`--chat-id`, `--attachments`) consistent with existing commands.

## Testing Guidelines
- Unit tests live alongside code as `*_test.go`; name tests `TestFunctionBehavior` and table-drive where useful.
- For DB or watch logic, prefer deterministic fixtures over touching the user’s live Messages DB; skip or mark tests that require macOS integration.
- Aim to keep `go test ./...` clean; add regression tests for every bug fix touching parsing, filtering, or attachment metadata.

## Commit & Pull Request Guidelines
- Follow the existing short, lowercase prefixes seen in history (`ci:`, `chore:`, `fix:`, `feat:`) with an imperative summary (e.g., `fix: handle missing attachments`).
- PRs should include: brief description, steps to repro/verify, and outputs of `pnpm lint` and `pnpm test`. For CLI changes, include sample commands and before/after snippets.
- Keep changeset focused; avoid drive-by refactors unless they reduce risk or remove duplication in touched areas.

## Security & macOS Permissions
- The tool needs read-only access to `~/Library/Messages/chat.db`; ensure the terminal has Full Disk Access before running tests that touch the DB.
- Sending requires Automation permission for Messages.app and SMS relay configured in macOS/iOS; document any manual steps needed for reviewers.
