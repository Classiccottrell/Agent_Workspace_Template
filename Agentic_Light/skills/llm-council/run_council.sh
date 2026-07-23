#!/usr/bin/env bash
# run_council.sh — LLM Council orchestrator.
#
# 5 advisors (agents/council/*.md) argue a question in parallel → their
# positions are anonymized (Advisor A..E, shuffled per run) → each advisor
# peer-reviews the other four, in parallel → a chairman (agents/council/
# chairman.md) synthesizes one decision report → report is written to
# brain/council_decisions/ and indexed in brain/wiki/index.md.
#
# Usage:
#   bash run_council.sh "<question>"
#   echo "<question>" | bash run_council.sh
#
# Advisor/chairman identity, model, and invocation CLI are configured in
# advisors.json (provider-agnostic schema). Only the "claude" cli path is
# wired with safety flags here — a non-Claude cli enabled from
# _disabled_examples would need its own flag mapping added below; this is a
# deliberate scope boundary (schema proven extensible, execution not).
#
# Does NOT invoke Agentic_Light/System_Config/run_agent.sh directly: each
# advisor needs its own cli/model from advisors.json, so invoke_agent()
# below is the "equivalent headless call" using the same watchdog/timeout
# discipline as run_agent.sh's run_agent().
#
# Bash 3.2-safe: no associative arrays, no mapfile.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSCFG="$(cd "$SCRIPT_DIR/../../System_Config" && pwd)"
CALLER_PATH="$PATH"
# shellcheck source=../../System_Config/config.sh
source "$SYSCFG/config.sh"
validate_config || echo "[run_council] WARNING: config validation reported issues — continuing." >&2
# config.sh pins PATH to a fixed list (mac/Linux standard locations); restore
# the invoking shell's PATH as a fallback so advisor cli resolution below
# isn't narrower than what the caller already had available (e.g. a
# node-version-managed npm global bin holding the real `claude`).
PATH="$PATH:$CALLER_PATH"

ADVISORS_JSON="$SCRIPT_DIR/advisors.json"
COUNCIL_DIR="$WORKSPACE/agents/council"
COUNCIL_DECISIONS="$BRAIN/council_decisions"
INDEX_FILE="$BRAIN/wiki/index.md"
SENTINEL="<!-- COUNCIL-INDEX-INSERT -->"
LABELS="A B C D E"

MAX_SECONDS="${COUNCIL_MAX_SECONDS:-180}"
MAX_BUDGET="${COUNCIL_MAX_BUDGET:-1.00}"

mkdir -p "$LOG_DIR" "$COUNCIL_DECISIONS"
LOG_FILE="$LOG_DIR/llm-council.$(date +%Y%m%d-%H%M%S).log"

if [[ ! -f "$ADVISORS_JSON" ]]; then
  echo "run_council.sh: advisors.json not found: $ADVISORS_JSON" >&2
  exit 1
fi
if command -v jq >/dev/null 2>&1; then :; elif command -v python3 >/dev/null 2>&1; then :; else
  echo "run_council.sh: needs jq or python3 to parse advisors.json — neither found." >&2
  exit 1
fi

# ── QUESTION ─────────────────────────────────────────────────────────────
if [[ $# -ge 1 ]]; then
  QUESTION="$1"
elif [[ ! -t 0 ]]; then
  QUESTION="$(cat -)"
else
  echo "usage: run_council.sh \"<question>\"  (or pipe the question via stdin)" >&2
  exit 1
fi
QUESTION="$(printf '%s' "$QUESTION" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
if [[ -z "$QUESTION" ]]; then
  echo "run_council.sh: empty question" >&2
  exit 1
fi

# ── TMPDIR (trap-cleaned) ────────────────────────────────────────────────
TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/agentic-light-council.XXXXXX")"
trap 'rm -rf "$TMPDIR"' EXIT INT TERM

# ── JSON ACCESSORS (jq primary, python3 fallback) ───────────────────────
json_advisor_ids() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.advisors[].id' "$ADVISORS_JSON"
  else
    python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
for a in d.get("advisors", []):
    print(a["id"])
' "$ADVISORS_JSON"
  fi
}

json_advisor_field() {
  local id="$1" field="$2"
  if command -v jq >/dev/null 2>&1; then
    case "$field" in
      cli)  jq -r --arg id "$id" '.advisors[] | select(.id==$id) | .invoke.cli' "$ADVISORS_JSON" ;;
      args) jq -r --arg id "$id" '.advisors[] | select(.id==$id) | (.invoke.args // []) | join(" ")' "$ADVISORS_JSON" ;;
      *)    jq -r --arg id "$id" --arg f "$field" '.advisors[] | select(.id==$id) | .[$f] // empty' "$ADVISORS_JSON" ;;
    esac
  else
    python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
aid, field = sys.argv[2], sys.argv[3]
a = next((x for x in d.get("advisors", []) if x["id"] == aid), None)
if a is None:
    sys.exit(0)
if field == "cli":
    print(a.get("invoke", {}).get("cli", ""))
elif field == "args":
    print(" ".join(a.get("invoke", {}).get("args", [])))
else:
    print(a.get(field, ""))
' "$ADVISORS_JSON" "$id" "$field"
  fi
}

json_chairman_field() {
  local field="$1"
  if command -v jq >/dev/null 2>&1; then
    case "$field" in
      cli)  jq -r '.chairman.invoke.cli' "$ADVISORS_JSON" ;;
      args) jq -r '(.chairman.invoke.args // []) | join(" ")' "$ADVISORS_JSON" ;;
      *)    jq -r --arg f "$field" '.chairman[$f] // empty' "$ADVISORS_JSON" ;;
    esac
  else
    python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
field = sys.argv[2]
c = d.get("chairman", {})
if field == "cli":
    print(c.get("invoke", {}).get("cli", ""))
elif field == "args":
    print(" ".join(c.get("invoke", {}).get("args", [])))
else:
    print(c.get(field, ""))
' "$ADVISORS_JSON" "$field"
  fi
}

# ── HEADLESS INVOCATION (watchdog: TERM then KILL, mirrors run_agent.sh) ──
invoke_agent() {
  local cli="$1" argsline="$2" prompt="$3" outfile="$4"
  if ! command -v "$cli" >/dev/null 2>&1; then
    printf '(advisor skipped: CLI "%s" not found in this environment)\n' "$cli" > "$outfile"
    echo "[run_council] WARN: cli '$cli' not found — skipped ($outfile)" >&2
    return 0
  fi

  local -a argv=()
  local a
  for a in $argsline; do argv+=("$a"); done

  local pid rc wd
  case "$cli" in
    claude)
      "$cli" "${argv[@]}" "$prompt" \
        --allowedTools "Read,Grep,Glob" \
        --disallowedTools "Bash,Write,Edit,NotebookEdit,WebFetch,WebSearch,Task,KillShell" \
        --permission-mode acceptEdits \
        --max-budget-usd "$MAX_BUDGET" \
        > "$outfile" 2>>"$LOG_FILE" &
      ;;
    *)
      # Non-Claude cli: pass prompt through configured args as-is. Provider-
      # specific safety flags are out of scope for this schema proof.
      "$cli" "${argv[@]}" "$prompt" > "$outfile" 2>>"$LOG_FILE" &
      ;;
  esac
  pid=$!
  ( sleep "$MAX_SECONDS"; kill -TERM "$pid" 2>/dev/null
    sleep 15;             kill -KILL "$pid" 2>/dev/null ) &
  wd=$!
  disown "$wd" 2>/dev/null || true
  if wait "$pid"; then rc=0; else rc=$?; fi
  kill "$wd" 2>/dev/null || true
  return "$rc"
}

strip_frontmatter() {
  # Drop the leading YAML "---" block. Two reasons: (1) it's agent-loader
  # metadata, not persona content the advisor needs; (2) a prompt literally
  # starting with "---" gets misparsed as a flag by yargs-style CLI parsers
  # (claude included) when it immediately follows -p on argv.
  awk '
    NR==1 && $0 ~ /^---[[:space:]]*$/ { infm=1; next }
    infm && $0 ~ /^---[[:space:]]*$/ { infm=0; next }
    infm { next }
    { print }
  ' "$1"
}

build_prompt() {
  # build_prompt <role-file> [extra sections already newline-joined] — echoes to stdout.
  local role_file="$1"; shift
  strip_frontmatter "$role_file"
  printf '\n\n'
  printf '%s\n' "$@"
}

# ── STEP 1: PARALLEL ADVISOR PASS ────────────────────────────────────────
echo "[run_council] Step 1/5 — dispatching 5 advisors in parallel…" >&2
ADV_IDS="$(json_advisor_ids)"
if [[ -z "$ADV_IDS" ]]; then
  echo "run_council.sh: advisors.json has no advisors[]" >&2
  exit 1
fi

ADV_PIDS=""
for id in $ADV_IDS; do
  role_file="$(json_advisor_field "$id" role_file)"
  cli="$(json_advisor_field "$id" cli)"
  args="$(json_advisor_field "$id" args)"
  role_path="$COUNCIL_DIR/$role_file"
  outfile="$TMPDIR/advisor-${id}.md"
  if [[ ! -f "$role_path" ]]; then
    echo "[run_council] ERROR: role file missing for $id: $role_path" >&2
    printf '(role file missing: %s)\n' "$role_path" > "$outfile"
    continue
  fi
  prompt="$(build_prompt "$role_path" \
    "## Question" "$QUESTION" "" \
    "Respond with a single self-contained position statement (a few paragraphs) per the Output instructions in your role above. You have not seen any other advisor's position yet — do not address them.")"
  invoke_agent "$cli" "$args" "$prompt" "$outfile" &
  ADV_PIDS="$ADV_PIDS $!"
done
wait $ADV_PIDS 2>/dev/null || true
echo "[run_council] Step 1/5 — done." >&2

# ── STEP 2: ANONYMIZE (Fisher-Yates shuffle, per-run) ────────────────────
echo "[run_council] Step 2/5 — anonymizing…" >&2
ids_array=()
for id in $ADV_IDS; do ids_array+=("$id"); done
labels_array=($LABELS)

shuffled=("${ids_array[@]}")
n=${#shuffled[@]}
i=$((n - 1))
while [[ $i -gt 0 ]]; do
  j=$(( RANDOM % (i + 1) ))
  tmp="${shuffled[i]}"; shuffled[i]="${shuffled[j]}"; shuffled[j]="$tmp"
  i=$((i - 1))
done

: > "$TMPDIR/anonymized.md"
idx=0
while [[ $idx -lt $n ]]; do
  id="${shuffled[idx]}"
  label="${labels_array[idx]}"
  {
    echo "### Advisor ${label}"
    echo
    cat "$TMPDIR/advisor-${id}.md"
    echo
  } >> "$TMPDIR/anonymized.md"
  idx=$((idx + 1))
done

# own_label <id> — linear scan (5 elements, no assoc arrays in bash 3.2).
own_label() {
  local target="$1" k
  k=0
  while [[ $k -lt $n ]]; do
    if [[ "${shuffled[k]}" == "$target" ]]; then
      echo "${labels_array[k]}"
      return
    fi
    k=$((k + 1))
  done
}

# ── STEP 3: PARALLEL PEER REVIEW (each advisor sees the other four) ──────
echo "[run_council] Step 3/5 — dispatching peer review…" >&2
PEER_PIDS=""
for id in $ADV_IDS; do
  role_file="$(json_advisor_field "$id" role_file)"
  cli="$(json_advisor_field "$id" cli)"
  args="$(json_advisor_field "$id" args)"
  role_path="$COUNCIL_DIR/$role_file"
  outfile="$TMPDIR/peer-${id}.md"
  [[ -f "$role_path" ]] || { printf '(role file missing: %s)\n' "$role_path" > "$outfile"; continue; }

  exclude_label="$(own_label "$id")"
  others=""
  k=0
  while [[ $k -lt $n ]]; do
    if [[ "${labels_array[k]}" != "$exclude_label" ]]; then
      others="${others}### Advisor ${labels_array[k]}
$(cat "$TMPDIR/advisor-${shuffled[k]}.md")

"
    fi
    k=$((k + 1))
  done

  prompt="$(build_prompt "$role_path" \
    "## Question" "$QUESTION" "" \
    "## Anonymized Positions From The Other Advisors" "$others" \
    "Critique and rank these positions from your lens. You do not know whether any of these is your own prior answer — treat all four as external. Be specific about strengths, blind spots, and which position you'd weight most heavily and why.")"
  invoke_agent "$cli" "$args" "$prompt" "$outfile" &
  PEER_PIDS="$PEER_PIDS $!"
done
wait $PEER_PIDS 2>/dev/null || true
echo "[run_council] Step 3/5 — done." >&2

: > "$TMPDIR/peer-review.md"
idx=0
while [[ $idx -lt $n ]]; do
  id="${shuffled[idx]}"
  label="${labels_array[idx]}"
  {
    echo "#### Peer review by Advisor ${label}"
    echo
    cat "$TMPDIR/peer-${id}.md"
    echo
  } >> "$TMPDIR/peer-review.md"
  idx=$((idx + 1))
done

# ── STEP 4: CHAIRMAN SYNTHESIS (sequential — depends on steps 1-3) ───────
echo "[run_council] Step 4/5 — chairman synthesis…" >&2
chairman_role_file="$(json_chairman_field role_file)"
chairman_cli="$(json_chairman_field cli)"
chairman_args="$(json_chairman_field args)"
chairman_role_path="$COUNCIL_DIR/$chairman_role_file"
chairman_out="$TMPDIR/chairman-output.md"

if [[ -f "$chairman_role_path" ]]; then
  chairman_prompt="$(build_prompt "$chairman_role_path" \
    "## Question" "$QUESTION" "" \
    "## Advisor Positions (Anonymized)" "$(cat "$TMPDIR/anonymized.md")" \
    "## Peer Review Notes" "$(cat "$TMPDIR/peer-review.md")" \
    "Respond with EXACTLY these three markdown sections, in this order, and nothing else — do not restate the Question or Advisor Positions, they are assembled separately:" \
    "## Chairman Synthesis" "## Decision" "## Dissents")"
  invoke_agent "$chairman_cli" "$chairman_args" "$chairman_prompt" "$chairman_out" || true
else
  echo "[run_council] ERROR: chairman role file missing: $chairman_role_path" >&2
  printf '## Chairman Synthesis\n(chairman role file missing: %s)\n\n## Decision\n(none — chairman unavailable)\n\n## Dissents\n(none recorded)\n' "$chairman_role_path" > "$chairman_out"
fi
echo "[run_council] Step 4/5 — done." >&2

# ── STEP 5: WRITE REPORT + INDEX ─────────────────────────────────────────
echo "[run_council] Step 5/5 — writing report…" >&2
DATE="$(date +%Y-%m-%d)"
SLUG="$(printf '%s' "$QUESTION" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-60)"
[[ -z "$SLUG" ]] && SLUG="question"
REPORT_BASENAME="${DATE}-${SLUG}"
REPORT_FILE="$COUNCIL_DECISIONS/${REPORT_BASENAME}.md"
if [[ -e "$REPORT_FILE" ]]; then
  REPORT_BASENAME="${REPORT_BASENAME}-${RANDOM}"
  REPORT_FILE="$COUNCIL_DECISIONS/${REPORT_BASENAME}.md"
fi

TITLE_ESC="$(printf '%s' "$QUESTION" | sed 's/"/\\"/g')"

{
  echo "---"
  echo "title: \"${TITLE_ESC}\""
  echo "type: council-decision"
  echo "tags: []"
  echo "updated: ${DATE}"
  echo "---"
  echo
  echo "## Question"
  echo "$QUESTION"
  echo
  echo "## Advisor Positions (Anonymized)"
  echo
  cat "$TMPDIR/anonymized.md"
  echo "## Peer Review Notes"
  echo
  cat "$TMPDIR/peer-review.md"
  cat "$chairman_out"
} > "$REPORT_FILE"
echo "[run_council] Report written: $REPORT_FILE" >&2

# ── INDEX (backup → rewrite → validate → rollback, per monday_init.sh) ───
WIKILINK="[[council_decisions/${REPORT_BASENAME}]]"
INDEX_ROW="| ${WIKILINK} | decision | ${DATE} |"

if [[ ! -f "$INDEX_FILE" ]]; then
  echo "[run_council] WARNING: wiki index not found at $INDEX_FILE — row NOT added." >&2
elif ! grep -Fq "$SENTINEL" "$INDEX_FILE"; then
  echo "[run_council] WARNING: sentinel not found in wiki index — row NOT added." >&2
elif grep -Fq "| ${WIKILINK} |" "$INDEX_FILE"; then
  echo "[run_council] wiki index already has a row for ${WIKILINK} — not duplicating."
else
  BACKUP="$LOG_DIR/wiki-index.$(date +%s).bak"
  cp "$INDEX_FILE" "$BACKUP"
  PRE_ROWS=$(grep -cE '^\| \[\[' "$INDEX_FILE" || true)

  if awk -v row="$INDEX_ROW" -v sent="$SENTINEL" '
        index($0, sent) && !done { print row; done=1 } { print }
      ' "$INDEX_FILE" > "$INDEX_FILE.tmp"; then
    POST_ROWS=$(grep -cE '^\| \[\[' "$INDEX_FILE.tmp" 2>/dev/null || true)
    if ! grep -Fq "$SENTINEL" "$INDEX_FILE.tmp" || [[ "$POST_ROWS" -lt $((PRE_ROWS + 1)) ]]; then
      rm -f "$INDEX_FILE.tmp"
      cp "$BACKUP" "$INDEX_FILE"
      echo "[run_council] VALIDATION FAILED — rolled back from $BACKUP" >&2
    else
      mv "$INDEX_FILE.tmp" "$INDEX_FILE"
      rm -f "$BACKUP"
      echo "[run_council] wiki index row added for ${WIKILINK}."
    fi
  else
    rm -f "$INDEX_FILE.tmp"
    cp "$BACKUP" "$INDEX_FILE"
    echo "[run_council] WARNING: index update failed — rolled back from $BACKUP" >&2
  fi
fi

echo "$REPORT_FILE"
