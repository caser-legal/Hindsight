# Standalone Hindsight with 9Router

This repository is an independent snapshot of Hindsight v0.9.0 configured to run
directly on macOS with Python. It does not require Docker. The production setup
uses Homebrew PostgreSQL 17 with pgvector, following Hindsight's official advice
to use external PostgreSQL instead of embedded pg0 for production.

## Architecture

Hindsight runs locally on `127.0.0.1:8888`, stores memories in a dedicated
PostgreSQL 17 database listening only on `127.0.0.1:5433`, and sends LLM requests
to the local OpenAI-compatible 9Router endpoint at `http://127.0.0.1:20128/v1`.
The PostgreSQL role uses SCRAM authentication and the database has pgvector
enabled. Embeddings use the local ONNX CPU backend, and result fusion uses the
local RRF reranker. The Control Plane runs at `http://localhost:9999`.

## First-time setup

Requirements:

- Python 3.11-3.13 on macOS
- Homebrew PostgreSQL 17 with pgvector for production
- Node.js and npm for the official Hindsight Control Plane
- 9Router running on port 20128
- A model or combo configured in 9Router

Run:

```bash
./scripts/local/setup-standalone.sh
```

The setup creates a private runtime at `~/.local/share/hindsight`, including its
`.venv`, installs this snapshot's API package with Intel-compatible local ONNX
dependencies, and installs the pinned official Control Plane package. Keeping
the runtime outside Documents also lets macOS `launchd` own the background
services reliably.

For a fresh production restore, provision PostgreSQL 17 with pgvector according
to Hindsight's official installation guide, then put its connection URL in the
ignored `.env` as `HINDSIGHT_API_DATABASE_URL`. The live database URL and
password are never committed.

## Configuration

The real local configuration is `.env`, which Git ignores. For a new checkout:

```bash
cp .env.9router.example .env
```

Enter the 9Router API key. The template uses the 9Router model or combo ID `1`.
If that ID is later unavailable, replace it with an exact ID returned by 9Router's
`/v1/models` endpoint. Add the external PostgreSQL connection URL for production.
Never commit `.env`; keep it mode 600.

## Start

Make sure 9Router is running, then run:

```bash
./scripts/local/start-standalone.sh
```

Hindsight becomes available at:

- Health: `http://127.0.0.1:8888/health`
- REST API: `http://127.0.0.1:8888`
- MCP: `http://127.0.0.1:8888/mcp/`
- Bank-pinned MCP: `http://127.0.0.1:8888/mcp/coding-agent::Hindsight/`
- Control Plane: `http://localhost:9999`

Verify it from another terminal:

```bash
curl http://127.0.0.1:8888/health
```

Stop it with `Ctrl-C` in the terminal where it is running.

## Combined `9router` command

On your Mac, `~/.local/bin/9router` points to the combined launcher. Typing
`9router` with no arguments starts 9Router when needed, starts Hindsight and the
Control Plane when needed under `launchd`, waits for their health checks, and
opens both local pages. `mind` starts the same services but opens only the
Hindsight Control Plane. Hindsight continues running after the command exits.
Any 9Router subcommand or option is passed unchanged to the original executable
at `/usr/local/bin/9router`.

The live Hindsight log is `~/.local/share/hindsight/hindsight.log`.

The launcher gives an existing Hindsight process a 30-second `/health` grace
period before replacing it. This follows the official remediation in Hindsight
issue #3099 for busy event loops that can miss short health probes.

The Control Plane launcher sources the mode-600 runtime `config.env` before
starting with `--hostname localhost`. If API or UI authentication is enabled
later with the official `HINDSIGHT_CP_DATAPLANE_API_KEY` or
`HINDSIGHT_CP_ACCESS_KEY` variables, the Control Plane inherits them without
putting secrets in a launchd plist or command line.

## Codex and Grok Build

Build the pinned coding-agent integration in this private snapshot and install it
against the self-hosted API:

```bash
cd hindsight-integrations/coding-agents
npm ci --no-audit --no-fund
npm run build
node dist/installer.js install codex grok-build \
  --server self-hosted --api-url http://127.0.0.1:8888
```

The Grok lifecycle hooks are installed as the official always-trusted global
hook file at `~/.grok/hooks/hindsight-coding-agents.json`; its MCP server remains
in `~/.grok/config.toml`. This avoids Grok 1.0.0's incorrect `hooks` unknown-key
warning while preserving `SessionStart`, `UserPromptSubmit`, and `Stop`.

For this machine, copy `scripts/local/hindsight-coding-agent.json.example` to
`~/.hindsight/coding-agent.json`. It pins both agents to the shared
`coding-agent::Hindsight` bank regardless of their working directory. Grok's
automatic hook reflection is disabled because hook harnesses have an official
25-second cap; Grok is instead instructed to call `hindsight_reflect` explicitly
for new goals. Codex keeps automatic reflection enabled.

## Memory backups

Install the daily macOS backup job:

```bash
./scripts/local/install-backup-launch-agent.sh
```

It runs the official `hindsight-admin backup` command at 03:15 local time,
validates each ZIP, publishes it atomically, stores it mode 600 under
`~/Library/Application Support/Hindsight/backups`, and keeps the latest 30 full
backups. The admin CLI uses the same runtime environment as the API, so it backs
up the same configured database without changing `HINDSIGHT_API_DATABASE_URL`.

Create a full backup immediately:

```bash
~/.local/share/hindsight/backup-hindsight.sh
```

Create an official portable export of one bank:

```bash
~/.local/share/hindsight/backup-hindsight.sh --bank 'coding-agent::Hindsight'
```

Full backups are consistent live snapshots created with Hindsight's documented
`REPEATABLE READ` transaction. Bank exports are the supported portable format
for moving one bank to another Hindsight instance.

## Backup scope

Git contains the source snapshot, setup scripts, and sanitized configuration
template. It intentionally excludes live API/database credentials, runtime
`.venv`, PostgreSQL data, memory-backup archives, logs, and other runtime state.
