# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kypello is a high-performance, S3-compatible object storage server. It is a community fork of MinIO that preserves OIDC/SSO and the Admin UI under GNU AGPLv3. The binary is named `kypello`. Environment variables accept both `MINIO_*` and `KYPELLO_*` prefixes.

## Build & Development Commands

```bash
make build          # Build ./kypello binary (CGO_ENABLED=0)
make install        # Build and copy to $GOPATH/bin/kypello
make lint           # golangci-lint + typos spell checker
make lint-fix       # Lint with auto-fix
make test           # Runs linters, builds, then unit tests
make test-race      # Unit tests with -race detector
make check-gen      # Verify generated code (msgp, stringer) is up to date
make verifiers      # lint + check-gen (run before committing)
```

### Running a single test

```bash
# Single test function in cmd package:
MINIO_API_REQUESTS_MAX=10000 CGO_ENABLED=0 go test -tags kqueue,dev -v -run TestFunctionName ./cmd

# Single test in an internal package:
CGO_ENABLED=0 go test -tags kqueue,dev -v -run TestName ./internal/somepkg
```

### Build tags

Always use `-tags kqueue` (required for build) and add `dev` for tests: `-tags kqueue,dev`.

### Integration test suites

```bash
make test-iam                    # IAM (LDAP, etcd, OpenID)
make test-replication            # Multi-site replication
make test-site-replication-ldap  # Site replication with LDAP
make verify                      # Full verification suite (requires install-race)
make verify-healing              # Healing and disk recovery
```

## Architecture

### Entry point

`main.go` → `cmd.Main(os.Args)`. Uses `github.com/minio/cli` for subcommands. The `internal/init` package **must** be the first import (runtime bootstrap).

### Core packages

- **`cmd/`** — Single flat package (~450 Go files) containing the entire server: S3 API handlers, admin API, erasure coding, IAM, storage layer, replication, lifecycle. All in `package cmd`.
- **`internal/`** — Shared internal libraries: `auth`, `grid` (inter-node RPC), `dsync` (distributed locking), `config`, `crypto`, `hash`, `kms`, `event`, `logger`, `http`, `s3select`.

### Key abstractions

- **`ObjectLayer`** interface (`cmd/object-api-interface.go`) — Central abstraction for all storage operations (Get/Put/Delete/ListObjects). Primary implementation is `erasureObjects`.
- **Erasure coding** (`cmd/erasure*.go`) — Data sharded across disks with parity. Erasure sets grouped into server pools.
- **XL Storage** (`cmd/xl-storage*.go`) — Direct disk I/O layer with XL metadata format.
- **IAM** (`cmd/iam*.go`) — Identity providers (LDAP, OIDC, built-in), policy engine, STS temporary credentials. Backends: in-memory, etcd, object store.
- **Internal grid** (`internal/grid/`) — Multiplexed inter-node RPC for distributed operations.

### Code generation

MessagePack serialization via `github.com/tinylib/msgp` and enum strings via `golang.org/x/tools/cmd/stringer`. Run `go generate ./...` to regenerate. Files end in `_gen.go`. The `make check-gen` target verifies these are committed.

## Linting

Uses golangci-lint v2 (`.golangci.yml`). Key enabled linters: gocritic, govet, staticcheck, revive, misspell (US locale), unused, modernize, forcetypeassert (except tests). Formatters: gofumpt, goimports.

The `typos` spell checker also runs during lint (config in `.typos.toml`).

## MCP Servers

Three MCP servers are available. Use them proactively rather than guessing at answers.

### GitHub (`mcp__github__*`)

Use for all interactions with the `kypello-io/kypello` repository on GitHub: issues, PRs, branches, commits, code search.

- **Read PR/issue details**: `pull_request_read` (method: `get`, `get_diff`, `get_files`, `get_review_comments`), `issue_read` (method: `get`, `get_comments`).
- **List/search**: `list_issues`, `list_pull_requests`, `search_issues`, `search_pull_requests`, `search_code`. Use `search_*` when filtering by author, keywords, or complex criteria; use `list_*` for simple enumeration.
- **Write operations**: `issue_write`, `create_pull_request`, `update_pull_request`, `pull_request_review_write`. When creating PRs, search for a PR template first (`pull_request_template.md` or `.github/PULL_REQUEST_TEMPLATE/`).
- **PR reviews**: Create a pending review with `pull_request_review_write` (method: `create`), add line comments with `add_comment_to_pending_review`, then submit with `pull_request_review_write` (method: `submit_pending`).
- **Pagination**: Use batches of 5-10 items. Pass `minimal_output: true` when full detail isn't needed.
- Always call `get_me` first if you need to know the authenticated user.

### Tavily (`mcp__tavily__*`)

Use for web search, content extraction, and research tasks when information is needed beyond the codebase or knowledge cutoff.

- **`tavily_search`**: General web search. Use `search_depth: "basic"` for quick lookups, `"advanced"` for thorough results. Set `topic: "general"` (default). Use `time_range` or `start_date`/`end_date` to scope results temporally.
- **`tavily_extract`**: Extract content from specific URLs. Use `extract_depth: "advanced"` for LinkedIn, protected sites, or pages with tables/embedded content.
- **`tavily_crawl`**: Crawl a website from a starting URL. Configure `max_depth` and `max_breadth` to control scope. Use `instructions` to guide which pages to return.
- **`tavily_map`**: Map a website's URL structure without extracting content. Useful for understanding site layout before targeted extraction.
- **`tavily_research`**: Deep multi-source research on a topic. Use `model: "mini"` for narrow tasks, `"pro"` for broad multi-subtopic research, `"auto"` to let it decide.

### Context7 (`mcp__context7__*`)

Use to fetch up-to-date documentation and code examples for any library or framework (e.g., Go stdlib, AWS SDK, MinIO client).

- **Step 1**: Call `resolve-library-id` with the library name and your query to get a Context7-compatible library ID. Do not skip this step unless the user provides an ID in `/org/project` format.
- **Step 2**: Call `query-docs` with the resolved library ID and a specific question.
- Limit to 3 calls per question. If no good match after 3 attempts, use the best result available.
- Prefer this over web search when looking up API signatures, usage patterns, or library-specific documentation.
