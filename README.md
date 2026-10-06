# claude-runner

A thin, non-interactive bridge that lets an orchestrating agent (e.g. Meta Muse running
in its own VM) delegate well-specified tasks to Anthropic's Claude through the
Claude Code CLI (`claude -p`).

- `SKILL.md` — when to use it, how to call it, how to read results (Agent Skills format)
- `run.sh` — the wrapper: read-only by default, `--edits` to allow file changes,
  surfaces every failure on stderr with a non-zero exit code

## Install (inside the agent's VM)

```bash
mkdir -p ~/.muse/skills/claude-runner && cd ~/.muse/skills/claude-runner \
  && curl -fsSLO https://raw.githubusercontent.com/indexzigu/claude-runner/main/SKILL.md \
  && curl -fsSLO https://raw.githubusercontent.com/indexzigu/claude-runner/main/run.sh \
  && chmod +x run.sh && sha256sum SKILL.md run.sh
```

Requires Claude Code installed and logged in (`claude` → `/login`). No secrets are
stored in or read by this repo.

```bash
./run.sh "Reply with exactly: PONG"
```
