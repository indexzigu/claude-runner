---
name: claude-runner
description: Delegate a self-contained thinking or making task to Anthropic's Claude via the Claude Code CLI in this VM, and get the result back. Use for coding and debugging, code review, writing and editing documents, analyzing files or data in the VM, summarizing long material, planning and reasoning through a problem, or a second opinion from a different model family. Muse keeps everything that touches the user's accounts (email, calendar, Slack, Drive, purchases, deploys).
---

# claude-runner

Thin wrapper around `claude -p` (Claude Code, non-interactive mode). Muse stays the
orchestrator: it writes the task, runs this skill, reads the result, and decides
what to do next. Claude never talks to the user directly.

## Division of labor

| Muse does | Claude (via this skill) does |
|---|---|
| Talking to the user, decisions, priorities | Thinking, writing, coding, analysis on what Muse hands over |
| Anything using the user's accounts: Gmail, Calendar, Slack, Drive, Vercel, Shopify, browser logins, purchases | Work on files inside `--cwd` |
| Gathering inputs (fetch mail, download a file) and saving them into `--cwd` | Reading those files and producing the output |
| Sending, posting, publishing the result after the user approves | Returning text, or writing output files into `--cwd` |

**Rule for every TASK:** add the constraint `Do not use any MCP connectors
(Gmail, Slack, Calendar, Drive, Vercel, Shopify, etc.). Work only with files in
the working directory.` Claude Code in this VM is logged into the user's
claude.ai account and those connectors are visible to it; account actions must
go through Muse so the user's approvals still apply.

## Task types and how to call them

| Task | Mode | Typical STOP WHEN | Evidence to ask for |
|---|---|---|---|
| Code review, explain a codebase, second opinion | default (read-only) | N findings listed | file:line + quoted code per finding |
| Coding, debugging, writing tests | `--edits` | test/build command exits 0 | diff + command output |
| Write or edit a document (report, email draft, README, slides outline) | `--edits` | file written at the given path | path + first 20 lines |
| Summarize long material (transcripts, PDFs saved as text, logs) | default | summary returned | quotes for every number/claim |
| Analyze data (CSV/JSON in `--cwd`) | `--edits` if it should save a result file | answer + output file | the script/commands used + key numbers |
| Plan or reason through a decision | default, `--model opus` | options + recommendation | assumptions listed explicitly |

Model: `sonnet` (default) for most work; `--model opus` for hard reasoning,
long multi-file changes, or when a first attempt was weak.

## How to call

```bash
bash ~/workspace/skills/claude-runner/run.sh [--cwd DIR] [--model MODEL] [--timeout SEC] [--edits] "TASK"
```

Options must come **before** the task string (run.sh rejects anything after it).

- `TASK` — one self-contained instruction using the contract below. Long tasks:
  pipe via stdin instead of an argument.
- `--cwd DIR` — directory Claude works in. Use a dedicated folder per job, e.g.
  `~/workspace/jobs/<short-name>/`. Put all inputs there first.
- `--model MODEL` — `sonnet` (default) or `opus`.
- `--timeout SEC` — kill after N seconds (default 900). Raise for big jobs.
- `--edits` — Claude may create and edit files in `--cwd` without prompting.
  Without it Claude only reads and answers.

Claude can also run shell commands (tests, scripts, data processing). Keep jobs
inside `--cwd` and say so in CONSTRAINTS.

### Passing large inputs and getting large outputs

- **Inputs:** save them as files in `--cwd` (e.g. `input/mail.txt`, `data.csv`)
  and name the paths in the task. Do not paste huge text into the task string.
- **Outputs:** for anything longer than a page, ask Claude to write it to a file
  in `--cwd` (needs `--edits`) and return the path plus a short summary. Muse
  then reads the file and decides what to show or send.

## Contract to put in every TASK

```
GOAL: <what to achieve>
INPUTS: <files in --cwd Claude should read, or "none">
STOP WHEN: <observable done condition>
EVIDENCE NEEDED: <diff | command output | file path + excerpt | quotes>
CONSTRAINTS: Do not use any MCP connectors. Work only inside the working directory. <plus task-specific rules>
```

## Reading the result

- Exit 0 → stdout is the answer. Quote it, don't paraphrase numbers or file paths.
- Non-zero exit → stderr has the reason. Common cases:
  - `claude: command not found` → Claude Code is not installed in this VM.
  - auth / 401 errors → run `claude` interactively and `/login` (hand the browser to the user).
  - network blocked → Sentinel egress to `api.anthropic.com` / `claude.ai` not approved.
  - exit 2 `unexpected arguments after TASK` → move the options before the task.
  - timeout → task too big; split it or raise `--timeout`.
- Never report a result as verified unless the evidence is actually present.
  For coding tasks, re-run the STOP WHEN command yourself even if Claude says it passed.

## Fix loop for coding tasks (Muse runs it, do this by default)

1. Call claude-runner with `--edits` and the task contract.
2. Muse runs the STOP WHEN command itself in `--cwd` and captures stdout/stderr + exit code.
3. Exit 0 -> done. Report Claude's answer plus Muse's own command output as evidence.
4. Non-zero -> call claude-runner again with `--edits`, same `--cwd`, and a task of the form:
   `GOAL: make <command> pass. Previous attempt failed with: <last 60 lines of output>.
   STOP WHEN: <command> exits 0. CONSTRAINTS: <same as before>.`
5. Repeat at most **3 rounds** in total. After round 3, stop and report to the user:
   what was tried, the last failure output, and which files changed.

Do not ask the user between rounds; the loop is pre-approved. Stop early and ask
only if Claude proposes deleting files, touching paths outside `--cwd`, or changing
the test itself to make it pass.

## Examples

Coding:
```bash
bash ~/workspace/skills/claude-runner/run.sh --cwd ~/workspace/jobs/myapp --edits \
"GOAL: make tests/test_parser.py pass. INPUTS: the repo in this directory. STOP WHEN: pytest tests/test_parser.py exits 0. EVIDENCE NEEDED: unified diff + pytest output. CONSTRAINTS: Do not use any MCP connectors. Work only inside the working directory. Do not modify tests."
```

Writing from material Muse gathered:
```bash
bash ~/workspace/skills/claude-runner/run.sh --cwd ~/workspace/jobs/weekly-report --edits \
"GOAL: write a one-page weekly report in Korean from input/notes.txt. INPUTS: input/notes.txt. STOP WHEN: report.md exists. EVIDENCE NEEDED: path + first 20 lines. CONSTRAINTS: Do not use any MCP connectors. Work only inside the working directory. Every number must appear in the input."
```
