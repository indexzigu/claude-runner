#!/usr/bin/env bash
# claude-runner: non-interactive bridge from Muse to Claude Code (`claude -p`).
# Usage: run.sh [--cwd DIR] [--model MODEL] [--timeout SEC] [--edits] "TASK"
#        echo "TASK" | run.sh [options]
# Prints Claude's final answer on stdout. Exit 0 = success; otherwise stderr explains.
set -euo pipefail

CWD="$PWD"
MODEL="sonnet"
TIMEOUT=900
PERMISSION_MODE="plan"   # read-only unless --edits
TASK=""

usage() { sed -n '2,5p' "$0" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cwd)     [[ $# -ge 2 ]] || usage; CWD="$2"; shift 2 ;;
    --model)   [[ $# -ge 2 ]] || usage; MODEL="$2"; shift 2 ;;
    --timeout) [[ $# -ge 2 ]] || usage; TIMEOUT="$2"; shift 2 ;;
    --edits)   PERMISSION_MODE="acceptEdits"; shift ;;
    -h|--help) usage ;;
    --)        shift; TASK="${1:-}"; shift || true; break ;;
    -*)        echo "run.sh: unknown option: $1" >&2; usage ;;
    *)         TASK="$1"; shift; break ;;
  esac
done
# Options must come BEFORE the task; anything left over would be silently ignored.
if [[ $# -gt 0 ]]; then
  echo "run.sh: unexpected arguments after TASK: $*  (put options before the task string)" >&2
  exit 2
fi

# Task from stdin if not given as an argument.
if [[ -z "$TASK" ]]; then
  if [[ -t 0 ]]; then
    echo "run.sh: no task given (pass as argument or via stdin)" >&2; exit 2
  fi
  TASK="$(cat)"
fi
[[ -n "${TASK//[[:space:]]/}" ]] || { echo "run.sh: task is empty" >&2; exit 2; }

# Preflight: binary, directory.
if ! command -v claude >/dev/null 2>&1; then
  echo "run.sh: 'claude' not found. Install Claude Code first: curl -fsSL https://claude.ai/install.sh | bash" >&2
  exit 127
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "run.sh: 'python3' not found; it is needed to parse claude's JSON output" >&2
  exit 127
fi
[[ -d "$CWD" ]] || { echo "run.sh: --cwd not a directory: $CWD" >&2; exit 2; }
[[ "$TIMEOUT" =~ ^[0-9]+$ ]] || { echo "run.sh: --timeout must be an integer" >&2; exit 2; }

# timeout(1) may be absent on minimal images; fall back to no timeout but say so.
TIMEOUT_CMD=()
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD=(timeout --kill-after=10 "$TIMEOUT")
else
  echo "run.sh: warning: 'timeout' not available, running without a time limit" >&2
fi

OUT="$(mktemp)"; ERR="$(mktemp)"
trap 'rm -f "$OUT" "$ERR"' EXIT

# --output-format json gives a single JSON object with .result (final text),
# .is_error, .num_turns, .total_cost_usd. Keep stdin closed so claude never waits on a tty.
set +e
(
  cd "$CWD" &&
  ${TIMEOUT_CMD[@]+"${TIMEOUT_CMD[@]}"} claude -p "$TASK" \
    --model "$MODEL" \
    --permission-mode "$PERMISSION_MODE" \
    --output-format json \
    --allowedTools Bash \
    </dev/null >"$OUT" 2>"$ERR"
)
RC=$?
set -e

if [[ $RC -eq 124 || $RC -eq 137 ]]; then
  echo "run.sh: timed out after ${TIMEOUT}s (exit $RC). Split the task or raise --timeout." >&2
  [[ -s "$ERR" ]] && cat "$ERR" >&2
  exit 124
fi

if [[ $RC -ne 0 ]]; then
  echo "run.sh: claude exited with code $RC" >&2
  [[ -s "$ERR" ]] && cat "$ERR" >&2
  [[ -s "$OUT" ]] && { echo "--- stdout ---" >&2; cat "$OUT" >&2; }
  exit "$RC"
fi

# Extract .result; surface is_error as a failure even if the process exited 0.
python3 - "$OUT" <<'PY'
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read()
try:
    d = json.loads(raw)
except json.JSONDecodeError:
    # Not JSON (older CLI or unexpected output): pass through verbatim.
    sys.stdout.write(raw)
    sys.exit(0)
if isinstance(d, list):          # some versions emit a list of events; take the last result
    d = next((e for e in reversed(d) if isinstance(e, dict) and "result" in e), d[-1] if d else {})
if d.get("is_error"):
    sys.stderr.write("run.sh: claude reported is_error=true\n" + str(d.get("result", raw)) + "\n")
    sys.exit(1)
res = d.get("result")
if res is None:
    sys.stderr.write("run.sh: no 'result' field in claude output; raw output follows\n")
    sys.stderr.write(raw + "\n")
    sys.exit(1)
sys.stdout.write(res if res.endswith("\n") else res + "\n")
meta = {k: d[k] for k in ("num_turns", "total_cost_usd", "duration_ms") if k in d}
if meta:
    sys.stderr.write("run.sh: " + json.dumps(meta) + "\n")
PY
