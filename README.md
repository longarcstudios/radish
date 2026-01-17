# Radish 🌱

**Autonomous coding loops with safety guardrails.**

Radish wraps autonomous AI coding sessions (Claude Code, Cursor, Aider, etc.) with blast radius control, auto-checkpoints, kill switches, and structured audit trails. Ship features overnight without the 4am disasters.

## Why Radish?

Autonomous coding agents are powerful but dangerous. They can:
- Delete critical files
- Overwrite production configs
- Spiral into infinite loops burning API credits
- Make changes that are hard to reverse

Radish provides the guardrails that let you sleep while agents work.

## Features

- **Blast Radius Control** — Restrict which files/directories agents can modify
- **Auto-Checkpoints** — Git commits at configurable intervals
- **Kill Switches** — Automatic termination on violation or timeout
- **Structured Audit Trails** — Every action logged for review
- **Cost Limits** — Stop before you burn through your API budget
- **Violation Detection** — Real-time monitoring for forbidden operations

## Quick Start

```bash
# Clone the repo
git clone https://github.com/longarcstudios/radish.git
cd radish

# Make executable
chmod +x radish.sh scripts/check_violations.sh

# Configure your session
cp radish.yaml.example radish.yaml
# Edit radish.yaml with your settings

# Run an autonomous session
./radish.sh "Implement user authentication feature"
```

## Configuration

Edit `radish.yaml` to configure your session:

```yaml
# radish.yaml
session:
  name: "feature-auth"
  timeout: 3600              # Max session duration (seconds)
  checkpoint_interval: 300   # Auto-commit every 5 minutes

guardrails:
  allowed_paths:
    - "src/**"
    - "tests/**"
  forbidden_paths:
    - ".env*"
    - "*.pem"
    - "secrets/**"
  forbidden_commands:
    - "rm -rf"
    - "DROP TABLE"
    - "format"

limits:
  max_files_changed: 50
  max_lines_changed: 2000
  max_cost_usd: 10.00

on_violation: "stop"         # stop | warn | checkpoint-and-continue
```

## How It Works

1. **Pre-flight checks** — Validates config, creates initial checkpoint
2. **Session wrapper** — Launches your agent with monitored stdin/stdout
3. **Real-time monitoring** — Watches file changes and command execution
4. **Violation detection** — Compares actions against guardrails
5. **Auto-checkpoints** — Periodic git commits with session metadata
6. **Post-session audit** — Generates structured log of all changes

## Commands

```bash
# Start a guarded session
./radish.sh "Your task description"

# Check for violations in current state
./scripts/check_violations.sh

# View session logs
ls -la logs/

# Rollback to last checkpoint
git reset --hard HEAD~1
```

## Telemetry

Radish v0.1.1+ includes optional cloud telemetry. Every checkpoint sends anonymous session data to help improve Radish.

**Data collected:**
- Session ID (random, not linked to you)
- Task description
- Agent type
- Checkpoint results (pass/fail)
- Violation types (if any)

**No personal data, code, or file contents are ever transmitted.**

### Opt-out

To disable telemetry, set the environment variable:

```bash
export RADISH_TELEMETRY=false
```

Or run with:

```bash
RADISH_TELEMETRY=false ./radish.sh "your task"
```

## Integration

Radish works with any autonomous coding tool:

```bash
# With Claude Code
./radish.sh --agent="claude" "Build the API endpoints"

# With Cursor
./radish.sh --agent="cursor" "Refactor the database layer"

# With Aider
./radish.sh --agent="aider" "Add unit tests"
```

## Audit Trail

Every session generates structured logs:

```
logs/
├── session-2024-01-15-143022/
│   ├── config.yaml          # Session configuration
│   ├── changes.json         # All file modifications
│   ├── commands.log         # Commands executed
│   ├── violations.json      # Any violations detected
│   └── summary.md           # Human-readable summary
```

## Philosophy

Radish follows the Long Arc Studios principle: **Permission is not proof.**

Just because an agent *can* do something doesn't mean it *should*. Radish provides the accountability layer that makes autonomous coding sessions auditable and reversible.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License - see [LICENSE](LICENSE)

---

Built by [Long Arc Studios](https://longarcstudios.com) — Infrastructure for the AI Era.
