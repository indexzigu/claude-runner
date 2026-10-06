---
name: claude-runner
description: Delegate a well-specified task to Anthropic's Claude via the Claude Code CLI installed in this VM. Use for coding tasks, long multi-file reasoning, code review, or a second opinion from a different model family. Do not use for tasks that need Muse's own browser, connectors, or credentials.
---

# claude-runner

Thin wrapper around `claude -p` (Claude Code, non-interactive mode). Muse stays the
orchestrator: it writes the task, runs this skill, reads the result, and decides
what to do next. Claude never talks to the user directly.

## When to use

- The task is **well specified** (clear goal, clear done-condition) and
  **independently verifiable** (tests, diff, a file to inspect).
- Coding work inside a repo on this VM: implement, refactor, fix a failing test,
  write tests, explain a codebase.
- Review or second opinion on code/plans Muse produced itself.

## When NOT to use

- Anything requiring Muse's browser, connectors, purchases, or stored credentials.
  Claude has no access to them and must not be given secrets.
- Vague or open-ended asks ("make it better"). Narrow the task first.
- Tasks where the user expects Muse's own judgment (decisions, priorities).

## How to call

```bash
bash ~/.muse/skills/claude-runner/run.sh [--cwd DIR] [--model MODEL] [--timeout SEC] [--edits] "TASK"
```

- `TASK` — one self-contained instruction. Include: goal, acceptance criterion,
  files/paths involved, and what evidence to return. Long tasks: pipe via stdin
  instead of an argument.
- `--cwd DIR` — repo/project directory Claude should work in (default: current).
- `--model MODEL` — e.g. `sonnet` (default, cheaper) or `opus`.
- `--timeout SEC` — kill after N seconds (default 900).
- `--edits` — allow Claude to edit files in `--cwd` without prompting. Omit for
  read-only analysis/review (safer default).

Output: Claude's final answer as plain text on stdout. Exit code 0 on success.

## Reading the result

- Exit 0 → stdout is the answer. Quote it, don't paraphrase numbers or file paths.
- Non-zero exit → stderr has the reason. Common cases:
  - `claude: command not found` → Claude Code is not installed in this VM.
  - auth / 401 errors → run `claude` interactively and `/login` (hand the browser to the user).
  - network blocked → Sentinel egress to `api.anthropic.com` / `claude.ai` not approved.
  - timeout → task too big; split it.
- Never report a result as verified unless the evidence Claude returned (diff,
  test output) is actually present. If Claude says it ran tests, re-run them.

## Contract to put in every TASK

```
GOAL: <what to achieve>
STOP WHEN: <observable done condition>
EVIDENCE NEEDED: <diff | test output | list of files | summary>
CONSTRAINTS: <files not to touch, style rules, no network, etc.>
```

## Example

```bash
bash ~/.muse/skills/claude-runner/run.sh --cwd ~/code/myapp --edits \
"GOAL: make tests/test_parser.py pass. STOP WHEN: pytest tests/test_parser.py exits 0. EVIDENCE NEEDED: unified diff + pytest output. CONSTRAINTS: do not modify tests."
```
