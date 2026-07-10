#!/usr/bin/env bash
# healthcheck.sh — workspace architecture health check → status_page.html
# Probes every layer (orchestration, automation, knowledge base, persistence,
# projects) and renders a self-contained HTML status page + status.json.
#
# It publishes the snapshot as docs/status.js (a window.__STATUS__ assignment) +
# docs/status.json, which docs/health.html reads via a <script> tag (not fetch).
#
# To make the LIVE GitHub Pages dashboard auto-update WITHOUT churning your working
# tree, the snapshot is written + committed ONLY inside a detached worktree pinned to
# origin/main (Pages' source) at ~/Library/Caches/agent-workspace-health-publish, then
# pushed — the job's own checkout is never touched. Best-effort: any git/auth failure
# just logs and we still exit 0. (For a fresh LOCAL view, open status_page.html.)
#
# Scheduled via launchd — see healthcheck.plist.tmpl (label com.<username>.vaultbrain.healthcheck)
#   Activate:   bash System_Config/install_healthcheck.sh
#   Manual:     bash System_Config/healthcheck.sh
#   View:       open System_Config/status_page.html  ·  or the microsite docs/health.html
#
# Deliberately NOT `set -e`: a failing probe is a result to REPORT, not a reason
# to abort. bash 3.2 compatible (no associative arrays). Always exits 0.

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

# WORKSPACE / VAULT / SOURCES / LOG_DIR / LABEL_PREFIX come from config.sh.
SYSCFG="$WORKSPACE/System_Config"
MANIFEST="$SOURCES/.ingested.log"
AGENTS="$WORKSPACE/.claude/agents"
# Claude Code stores per-project memory under a slug of the workspace path.
WS_SLUG="$(printf '%s' "$WORKSPACE" | sed 's|/|-|g')"
MEMDIR="$HOME/.claude/projects/${WS_SLUG}/memory"
OUT_HTML="$SYSCFG/status_page.html"
OUT_JSON="$SYSCFG/status.json"
INGEST_LABEL="$LABEL_PREFIX.dailyingest"
HEALTH_LABEL="$LABEL_PREFIX.healthcheck"

NOW_HUMAN="$(date '+%Y-%m-%d %H:%M:%S %Z')"
NOW_EPOCH="$(date +%s)"

TOTAL=0; PASS_N=0; WARN_N=0; FAIL_N=0
OVERALL="PASS"
ROWS=""; SECTIONS=""; JSON_ITEMS=""
CUR_SECTION=""; CUR_ICON=""

esc()      { printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }
json_esc() { printf '%s' "$1" | tr '\n\r\t' '   ' | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# check <PASS|WARN|FAIL> <name> <detail>
check() {
  local st="$1" name="$2" detail="$3" dot comma=""
  TOTAL=$((TOTAL + 1))
  case "$st" in
    PASS) PASS_N=$((PASS_N + 1)); dot="ok" ;;
    WARN) WARN_N=$((WARN_N + 1)); dot="warn"; [ "$OVERALL" = "PASS" ] && OVERALL="WARN" ;;
    FAIL) FAIL_N=$((FAIL_N + 1)); dot="fail"; OVERALL="FAIL" ;;
    *)    st="WARN"; WARN_N=$((WARN_N + 1)); dot="warn"; [ "$OVERALL" = "PASS" ] && OVERALL="WARN" ;;
  esac
  ROWS="${ROWS}<tr class=\"${dot}\"><td class=\"s\"><span class=\"dot ${dot}\"></span>${st}</td><td class=\"n\">$(esc "$name")</td><td class=\"d\">$(esc "$detail")</td></tr>"
  [ -n "$JSON_ITEMS" ] && comma=","
  JSON_ITEMS="${JSON_ITEMS}${comma}{\"layer\":\"$(json_esc "$CUR_SECTION")\",\"status\":\"${st}\",\"name\":\"$(json_esc "$name")\",\"detail\":\"$(json_esc "$detail")\"}"
}

begin_section() { ROWS=""; CUR_SECTION="$1"; CUR_ICON="$2"; }
end_section()   { SECTIONS="${SECTIONS}<section><h2>${CUR_ICON} $(esc "$CUR_SECTION")</h2><table>${ROWS}</table></section>"; }

# newest mtime (epoch) among the given paths; 0 if none exist
newest_mtime() {
  local m=0 t p
  for p in "$@"; do
    [ -e "$p" ] || continue
    t=$(stat -f %m "$p" 2>/dev/null || echo 0)
    [ "$t" -gt "$m" ] && m="$t"
  done
  echo "$m"
}

# doc_check <name> <readme_path> <documented files...>  — WARN if any documented
# file changed AFTER the README was last touched (i.e. the README is stale).
doc_check() {
  local name="$1" readme="$2"; shift 2
  if [ ! -s "$readme" ]; then check WARN "Doc: $name" "README missing or empty"; return; fi
  local rmt srct age
  rmt=$(stat -f %m "$readme" 2>/dev/null || echo 0)
  srct=$(newest_mtime "$@")
  if [ "$srct" -gt "$rmt" ]; then
    age=$(( (srct - rmt) / 3600 ))
    check WARN "Doc: $name" "stale — documented file changed ${age}h after the README; review & update"
  else
    check PASS "Doc: $name" "up to date"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# LAYER A — Orchestration & Agents
# ════════════════════════════════════════════════════════════════════════════
begin_section "Orchestration & Agents" "&#129517;"
[ -s "$WORKSPACE/CLAUDE.md" ] && check PASS "Orchestrator instructions" "CLAUDE.md present" || check FAIL "Orchestrator instructions" "CLAUDE.md missing or empty"
[ -s "$WORKSPACE/.AGENT.MD" ] && check PASS "Coordination matrix" ".AGENT.MD present" || check WARN "Coordination matrix" ".AGENT.MD missing or empty"
for rf in claude.md architect.md coder.md; do
  [ -s "$WORKSPACE/$rf" ] && check PASS "Role file: $rf" "present" || check WARN "Role file: $rf" "missing or empty"
done
if [ -d "$AGENTS" ]; then
  acount=$(find "$AGENTS" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  if [ "$acount" -ge 1 ]; then check PASS "Subagents directory" ".claude/agents/ present (${acount} files)"; else check FAIL "Subagents directory" ".claude/agents/ exists but is EMPTY"; fi
  roster_total=0; roster_ok=0; roster_names=""
  for ag in architect coder eng-manager archivist curator creative-director; do
    f="$AGENTS/$ag.md"
    roster_total=$((roster_total + 1))
    if [ -s "$f" ]; then
      # count DISTINCT required keys in the first frontmatter block (dup lines don't inflate it)
      d=0
      for k in name description tools model; do
        awk -v key="$k" '/^---$/{n++; next} n==1 && $0 ~ ("^" key ":"){hit=1} END{exit !hit}' "$f" && d=$((d + 1))
      done
      if [ "$d" -ge 4 ]; then
        roster_ok=$((roster_ok + 1))
        roster_names="${roster_names}${roster_names:+, }${ag}"
      else
        check WARN "Agent: $ag" "frontmatter incomplete (${d}/4 required keys)"
      fi
    else
      check FAIL "Agent: $ag" "missing or empty ${ag}.md"
    fi
  done
  if [ "$roster_ok" -eq "$roster_total" ]; then
    check PASS "Agent roster" "${roster_ok}/${roster_total} agents complete (${roster_names})"
  else
    check WARN "Agent roster" "${roster_ok}/${roster_total} complete — see below"
  fi
else
  check FAIL "Subagents directory" ".claude/agents/ MISSING — roles are prose only"
fi
end_section

# ════════════════════════════════════════════════════════════════════════════
# LAYER B — Automation & Scheduling
# ════════════════════════════════════════════════════════════════════════════
begin_section "Automation & Scheduling" "&#9881;"
[ -f "$HOME/Library/LaunchAgents/${INGEST_LABEL}.plist" ] && check PASS "Ingest LaunchAgent" "plist installed" || check FAIL "Ingest LaunchAgent" "plist NOT installed"
iline="$(launchctl list 2>/dev/null | grep "$INGEST_LABEL" || true)"
if [ -n "$iline" ]; then
  iexit="$(printf '%s' "$iline" | awk '{print $2}')"
  if   [ "$iexit" = "0" ]; then check PASS "Ingest job state" "loaded; last exit 0"
  elif [ "$iexit" = "-" ]; then check WARN "Ingest job state" "loaded; not run yet this session"
  else                          check FAIL "Ingest job state" "loaded; last exit ${iexit} (failed — check Full Disk Access)"; fi
else
  check FAIL "Ingest job state" "not loaded in launchd"
fi
if [ -f "$SYSCFG/logs/daily_ingest.log" ]; then
  # Tie recency to a SUCCESSFUL-completion marker, not just any log line, so a
  # stale timestamp from before a failing streak can't read as fresh.
  lts="$(grep -E 'daily_ingest done|no new clips' "$SYSCFG/logs/daily_ingest.log" | grep -oE '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]' | tail -1 | tr -d '[]')"
  if [ -n "$lts" ]; then
    lep="$(date -j -f '%Y-%m-%d %H:%M:%S' "$lts" +%s 2>/dev/null || echo 0)"
    if [ "$lep" -eq 0 ]; then check WARN "Ingest recency" "last run time unparseable"
    else
      age=$(( (NOW_EPOCH - lep) / 3600 ))
      if [ "$age" -le 36 ]; then check PASS "Ingest recency" "last successful run ${age}h ago (${lts})"
      else                       check WARN "Ingest recency" "last success ${age}h ago — stale (>36h)"; fi
    fi
  else check WARN "Ingest recency" "no successful-completion line in log"; fi
else
  check WARN "Ingest recency" "no ingest log yet"
fi
for ws in monday_init.sh friday_archive.sh; do
  [ -f "$SYSCFG/$ws" ] && check PASS "Weekly script: $ws" "present" || check WARN "Weekly script: $ws" "missing"
done
# Weekly note automation is wired via launchd LaunchAgents (preferred) or cron.
# Capture once + match in-shell: `launchctl list | grep -q` trips SIGPIPE under
# `set -o pipefail` (grep exits on first hit → launchctl dies 141 → the pipeline
# reads as false), making detection flaky by output position.
mon_sched=""; fri_sched=""
ll_out="$(launchctl list 2>/dev/null || true)"
cron_out="$(crontab -l 2>/dev/null || true)"
case "$ll_out" in *"$LABEL_PREFIX.mondayinit"*)    mon_sched="launchd";; esac
case "$ll_out" in *"$LABEL_PREFIX.fridayprocess"*) fri_sched="launchd";; esac
if [ -z "$mon_sched" ]; then case "$cron_out" in *monday_init*) mon_sched="cron";; esac; fi
if [ -z "$fri_sched" ]; then case "$cron_out" in *friday_process*|*friday_archive*) fri_sched="cron";; esac; fi
if [ -n "$mon_sched" ] && [ -n "$fri_sched" ]; then
  check PASS "Weekly automation wiring" "monday_init ($mon_sched) + Friday close-out ($fri_sched) scheduled"
elif [ -n "$mon_sched" ] || [ -n "$fri_sched" ]; then
  check WARN "Weekly automation wiring" "partial — monday=${mon_sched:-none}, friday=${fri_sched:-none}"
else
  check WARN "Weekly automation wiring" "monday_init / Friday close-out not scheduled (manual)"
fi
hline="$(launchctl list 2>/dev/null | grep "$HEALTH_LABEL" || true)"
[ -n "$hline" ] && check PASS "Health-check job" "self-scheduled in launchd" || check WARN "Health-check job" "not installed (run install_healthcheck.sh)"
end_section

# ════════════════════════════════════════════════════════════════════════════
# LAYER C — Knowledge Base (Vault_Brain)
# ════════════════════════════════════════════════════════════════════════════
begin_section "Knowledge Base (Vault_Brain)" "&#128218;"
for d in sources wiki inbox concepts weekly-logs archive; do
  [ -d "$VAULT/$d" ] && check PASS "Vault dir: ${d}/" "present" || check WARN "Vault dir: ${d}/" "missing"
done
[ -s "$VAULT/wiki/_index.md" ] && check PASS "Wiki index" "_index.md present" || check FAIL "Wiki index" "_index.md missing or empty"
[ -s "$VAULT/Master Note.md" ] && check PASS "Master note" "present" || check WARN "Master note" "missing or empty"
if [ -d "$SOURCES" ]; then
  touch "$MANIFEST" 2>/dev/null || true
  scanned=0; pending=0; plist=""; changed=0; clist=""
  while IFS= read -r f; do
    b="$(basename "$f")"
    case "$b" in _*|.*) continue ;; esac
    scanned=$((scanned + 1))
    rec="$(awk -F'\t' -v n="$b" '$NF==n{print $1; exit}' "$MANIFEST")"
    if [ -z "$rec" ]; then
      pending=$((pending + 1)); plist="${plist} ${b}"
    else
      # sources are meant to be immutable — recorded content hash should still match
      live="$(shasum -a 256 "$f" 2>/dev/null | awk '{print $1}')"
      if printf '%s' "$rec" | grep -qE '^[0-9a-f]{64}$' && [ -n "$live" ] && [ "$rec" != "$live" ]; then
        changed=$((changed + 1)); clist="${clist} ${b}"
      fi
    fi
  done < <(find "$SOURCES" -maxdepth 1 -type f -name '*.md' 2>/dev/null)
  if   [ "$scanned" -eq 0 ]; then check WARN "Source ingestion" "no source clips present in sources/"
  elif [ "$pending" -eq 0 ]; then check PASS "Source ingestion" "all ${scanned} clip(s) ingested"
  else check WARN "Source ingestion" "${pending}/${scanned} clip(s) pending:${plist}"; fi
  [ "$changed" -eq 0 ] && check PASS "Source immutability" "no ingested clip changed since ingest" || check WARN "Source immutability" "${changed} clip(s) changed after ingest (sources should be immutable):${clist}"
  legacy=$(awk -F'\t' 'NF<2 && $0!=""{c++} END{print c+0}' "$MANIFEST")
  [ "$legacy" -eq 0 ] && check PASS "Manifest format" "all entries content-hashed" || check WARN "Manifest format" "${legacy} legacy name-only entr(ies)"
  wcnt=$(find "$VAULT/wiki" -maxdepth 1 -type f -name '*.md' ! -name '_index.md' 2>/dev/null | wc -l | tr -d ' ')
  scnt=$(find "$SOURCES" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  if   [ "$scnt" -gt 0 ] && [ "$wcnt" -eq 0 ]; then check FAIL "Wiki coverage" "0 wiki pages from ${scnt} source clip(s) — curator never ran?"
  elif [ "$wcnt" -eq 0 ]; then check WARN "Wiki coverage" "no wiki pages yet"
  else check PASS "Wiki coverage" "${wcnt} wiki page(s) from ${scnt} source clip(s)"; fi
else
  check FAIL "Source ingestion" "sources/ directory missing"
fi
YEAR=$(date +%G); WEEK=$(date +%V)
wn="$VAULT/weekly-logs/${YEAR}-W${WEEK}.md"
[ -f "$wn" ] && check PASS "Current weekly note" "${YEAR}-W${WEEK}.md present" || check WARN "Current weekly note" "${YEAR}-W${WEEK}.md missing (run monday_init.sh)"
end_section

# ════════════════════════════════════════════════════════════════════════════
# LAYER D — Persistence & Config
# ════════════════════════════════════════════════════════════════════════════
begin_section "Persistence & Config" "&#128450;"
[ -s "$WORKSPACE/.claudeignore" ] && check PASS "Context guard" ".claudeignore present" || check WARN "Context guard" ".claudeignore missing or empty"
SLJ="$WORKSPACE/.claude/settings.local.json"
if [ -s "$SLJ" ]; then
  if command -v python3 >/dev/null 2>&1 && ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$SLJ" >/dev/null 2>&1; then
    check FAIL "Project permissions" "settings.local.json present but INVALID JSON"
  else
    check PASS "Project permissions" "settings.local.json valid"
  fi
else
  check WARN "Project permissions" "settings.local.json missing or empty"
fi
if [ -d "$MEMDIR" ]; then
  if [ -f "$MEMDIR/MEMORY.md" ]; then
    check PASS "Memory index" "MEMORY.md present"
    unindexed=0; dead=0; empty=0
    for mf in "$MEMDIR"/*.md; do
      [ -e "$mf" ] || continue
      bn="$(basename "$mf")"
      [ "$bn" = "MEMORY.md" ] && continue
      grep -q "($bn)" "$MEMDIR/MEMORY.md" 2>/dev/null || unindexed=$((unindexed + 1))
      [ -s "$mf" ] || empty=$((empty + 1))
    done
    while IFS= read -r linked; do
      [ -z "$linked" ] && continue
      [ -s "$MEMDIR/$linked" ] || dead=$((dead + 1))   # missing OR empty linked target
    done < <(grep -oE '\([a-z0-9_]+\.md\)' "$MEMDIR/MEMORY.md" 2>/dev/null | tr -d '()')
    if [ "$unindexed" -eq 0 ] && [ "$dead" -eq 0 ] && [ "$empty" -eq 0 ]; then check PASS "Memory index linkage" "index and files in sync"
    else check WARN "Memory index linkage" "${unindexed} unindexed, ${dead} missing/empty link(s), ${empty} empty file(s)"; fi
  else
    check FAIL "Memory index" "MEMORY.md missing"
  fi
else
  check FAIL "Memory store" "memory dir missing"
fi
[ -r "$HOME/.config/anthropic/key" ] && check PASS "Headless auth" "key file present" || check PASS "Headless auth" "login keychain (key file optional)"
end_section

# ════════════════════════════════════════════════════════════════════════════
# LAYER E — Projects & Delivery
# ════════════════════════════════════════════════════════════════════════════
begin_section "Projects & Delivery" "&#128679;"
if [ -d "$WORKSPACE/Projects" ]; then
  pc=$(find "$WORKSPACE/Projects" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  check PASS "Projects workspace" "${pc} project folder(s)"
  [ -s "$WORKSPACE/Projects/.AGENT.MD" ] && check PASS "Eng-manager scope" "Projects/.AGENT.MD present" || check WARN "Eng-manager scope" "Projects/.AGENT.MD missing or empty"
else
  check FAIL "Projects workspace" "Projects/ missing"
fi
if [ -d "$WORKSPACE/Final_Products" ]; then
  [ -f "$WORKSPACE/Final_Products/INDEX.md" ] && check PASS "Final_Products index" "INDEX.md present" || check WARN "Final_Products index" "INDEX.md missing (nothing shipped yet)"
else
  check WARN "Final_Products" "directory missing"
fi
end_section

# ════════════════════════════════════════════════════════════════════════════
# LAYER F — Documentation Currency (READMEs vs the files they document)
# ════════════════════════════════════════════════════════════════════════════
begin_section "Documentation Currency" "&#128221;"
doc_check "Workspace/README" "$WORKSPACE/README.md" "$WORKSPACE/CLAUDE.md" "$WORKSPACE/.AGENT.MD" "$AGENTS"/*.md
doc_check "System_Config/README" "$SYSCFG/README.md" "$SYSCFG"/*.sh "$SYSCFG"/*.plist.tmpl
doc_check "Vault_Brain/README" "$VAULT/README.md" "$VAULT/CLAUDE.md" "$SYSCFG/daily_ingest.sh" "$SYSCFG/monday_init.sh" "$SYSCFG/friday_archive.sh"
doc_check ".AGENT.MD workspace map" "$WORKSPACE/.AGENT.MD" "$AGENTS"/*.md
end_section


# ════════════════════════════════════════════════════════════════════════════
# LAYER G — Repo Hygiene (no harness worktrees leaked into the tracked tree)
# ════════════════════════════════════════════════════════════════════════════
begin_section "Repo Hygiene" "&#129529;"
# committed gitlinks (mode 160000) under .claude/ in HEAD, plus any staged in the index
gl_head=$(git -C "$WORKSPACE" ls-tree -r HEAD -- .claude 2>/dev/null | awk '$2=="commit"{print $4}')
gl_idx=$(git -C "$WORKSPACE" ls-files -s -- .claude 2>/dev/null | awk '$1=="160000"{print $4}')
gl_all=$(printf '%s\n%s\n' "$gl_head" "$gl_idx" | grep -v '^$' | sort -u | tr '\n' ' ')
if [ -n "$gl_all" ]; then
  check FAIL "No worktree gitlinks tracked" "committed/staged gitlink(s) under .claude/: ${gl_all}"
else
  check PASS "No worktree gitlinks tracked" "no 160000 gitlinks under .claude/"
fi
if grep -q '^\.claude/worktrees/' "$WORKSPACE/.gitignore" 2>/dev/null; then
  check PASS ".claude/worktrees ignored" ".gitignore rule present"
else
  check WARN ".claude/worktrees ignored" ".gitignore missing .claude/worktrees/ rule"
fi
end_section
# ════════════════════════════════════════════════════════════════════════════
# LAYER H — Decision Hygiene
# ════════════════════════════════════════════════════════════════════════════
begin_section "Decision Hygiene" "&#128196;"
dec_count=0; dec_newest=0; dec_newest_name=""
if [ -d "$MEMDIR" ]; then
  while IFS= read -r mf; do
    [ -s "$mf" ] || continue
    if awk '/^---$/{n++; next} n==1 && /^[[:space:]]+type:[[:space:]]*decisions/{hit=1} n>=2{exit} END{exit !hit}' "$mf" 2>/dev/null; then
      dec_count=$((dec_count + 1))
      mt=$(stat -f %m "$mf" 2>/dev/null || echo 0)
      if [ "$mt" -gt "$dec_newest" ]; then dec_newest="$mt"; dec_newest_name="$(basename "$mf")"; fi
    fi
  done < <(find "$MEMDIR" -maxdepth 1 -name 'decision_*.md' 2>/dev/null)
fi
if [ "$dec_count" -eq 0 ]; then
  check WARN "Decision log" "no decision memories found — capture architectural decisions as type: decisions in memory/"
else
  check PASS "Decision log" "${dec_count} decision(s) recorded (latest: ${dec_newest_name})"
  if [ "$dec_newest" -gt 0 ]; then
    age_days=$(( (NOW_EPOCH - dec_newest) / 86400 ))
    if [ "$age_days" -le 7 ]; then
      check PASS "Decision recency" "most recent decision ${age_days}d ago"
    else
      check WARN "Decision recency" "most recent decision ${age_days}d ago — log recent architectural choices"
    fi
  fi
fi
end_section

# ════════════════════════════════════════════════════════════════════════════
# LAYER I — Ingest Observability (Card #10 / #20: pending, ingested, trend)
# ════════════════════════════════════════════════════════════════════════════
begin_section "Ingest" "&#128229;"
ing_pending=0; ing_total=0
ING_OLD_IFS="$IFS"; IFS=':'
ING_DIRS=($INGEST_SOURCES)
IFS="$ING_OLD_IFS"
for isd in "${ING_DIRS[@]}"; do
  [ -n "$isd" ] || continue
  isdir="$VAULT/$isd"
  [ -d "$isdir" ] || continue
  imf="$isdir/.ingested.log"; touch "$imf" 2>/dev/null || true
  while IFS= read -r isf; do
    isb="$(basename "$isf")"
    case "$isb" in _*|.*) continue ;; esac
    awk -F'\t' -v n="$isb" '$NF==n{f=1} END{exit !f}' "$imf" || ing_pending=$((ing_pending + 1))
  done < <(find "$isdir" -maxdepth 1 -type f -name '*.md' 2>/dev/null)
  ing_total=$((ing_total + $(wc -l < "$imf" | tr -d ' ')))
done
if [ "$ing_pending" -eq 0 ]; then check PASS "Clips pending" "0 pending across INGEST_SOURCES"
else check WARN "Clips pending" "${ing_pending} clip(s) pending across INGEST_SOURCES"; fi
check PASS "Clips ingested (total)" "${ing_total} clip(s) recorded across manifests"

wiki_page_count=$(find "$VAULT/wiki" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
jobs_loaded=$(launchctl list 2>/dev/null | grep -c vaultbrain || true)
jobs_loaded="${jobs_loaded:-0}"

METRICS="$LOG_DIR/metrics.tsv"
mkdir -p "$LOG_DIR"
rotate_log "$METRICS" 1000
rotate_log "$SYSCFG/logs/healthcheck.log" 2000
[ -s "$METRICS" ] || printf 'date\tclips_pending\tclips_ingested_total\tjobs_loaded\twiki_pages\n' > "$METRICS"
printf '%s\t%d\t%d\t%d\t%d\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$ing_pending" "$ing_total" "$jobs_loaded" "$wiki_page_count" >> "$METRICS"

last_metrics_line="$(tail -1 "$METRICS" | tr '\t' ' ')"
check PASS "Last metrics snapshot" "${last_metrics_line}"
end_section

# ════════════════════════════════════════════════════════════════════════════
# RENDER
# ════════════════════════════════════════════════════════════════════════════
case "$OVERALL" in
  PASS) BANNER="ALL SYSTEMS OPERATIONAL"; BCLASS="ok" ;;
  WARN) BANNER="OPERATIONAL &mdash; WARNINGS"; BCLASS="warn" ;;
  FAIL) BANNER="ATTENTION REQUIRED"; BCLASS="fail" ;;
esac
HOST="$(hostname -s 2>/dev/null || echo localhost)"

TMP="$(mktemp 2>/dev/null || echo "${OUT_HTML}.tmp")"
cat > "$TMP" <<HTML
<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="300">
<title>Agent Workspace &middot; Status</title>
<style>
:root{--bg:#0d1117;--card:#161b22;--bd:#30363d;--tx:#e6edf3;--mut:#8b949e;--ok:#3fb950;--warn:#d29922;--fail:#f85149}
*{box-sizing:border-box}
body{margin:0;font:15px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:var(--bg);color:var(--tx);padding:32px}
.wrap{max-width:920px;margin:0 auto}
h1{font-size:20px;margin:0 0 4px;letter-spacing:.3px}
.sub{color:var(--mut);font-size:13px;margin-bottom:24px}
.banner{border-radius:12px;padding:18px 22px;margin-bottom:22px;font-weight:600;font-size:17px;display:flex;align-items:center;gap:14px;border:1px solid}
.banner.ok{background:rgba(63,185,80,.12);border-color:var(--ok);color:var(--ok)}
.banner.warn{background:rgba(210,153,34,.12);border-color:var(--warn);color:var(--warn)}
.banner.fail{background:rgba(248,81,73,.12);border-color:var(--fail);color:var(--fail)}
.counts{margin-left:auto;font-size:13px;font-weight:500;color:var(--mut)}
.counts b{color:var(--tx)}
section{background:var(--card);border:1px solid var(--bd);border-radius:12px;margin-bottom:16px;overflow:hidden}
h2{font-size:15px;margin:0;padding:13px 18px;border-bottom:1px solid var(--bd);background:rgba(255,255,255,.02)}
table{width:100%;border-collapse:collapse}
td{padding:9px 18px;border-top:1px solid var(--bd);vertical-align:top}
tr:first-child td{border-top:0}
.s{white-space:nowrap;width:78px;font-size:12px;font-weight:600;color:var(--mut)}
.n{width:215px;font-weight:500}
.d{color:var(--mut);font-size:13px}
.dot{display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:7px;vertical-align:middle}
.dot.ok{background:var(--ok)}.dot.warn{background:var(--warn)}.dot.fail{background:var(--fail)}
tr.fail .d{color:#ffb4ad}tr.warn .d{color:#e8c877}
.ft{color:var(--mut);font-size:12px;text-align:center;margin-top:22px}
.ft code{color:var(--tx);background:rgba(255,255,255,.06);padding:1px 6px;border-radius:5px}
</style></head><body><div class="wrap">
<h1>Agent Workspace &middot; System Status</h1>
<div class="sub">Multi-agent workspace health check &middot; auto-refreshes every 5 min</div>
<div class="banner ${BCLASS}"><span>${BANNER}</span><span class="counts"><b>${PASS_N}</b> pass &middot; <b>${WARN_N}</b> warn &middot; <b>${FAIL_N}</b> fail</span></div>
${SECTIONS}
<div class="ft">Generated ${NOW_HUMAN} &middot; ${HOST} &middot; <a href="run_healthcheck.command" style="font-size:12px;border:1px solid var(--bd);background:var(--card);color:var(--mut);padding:2px 10px;border-radius:5px;text-decoration:none;margin-left:6px">&#8635; run now</a> &middot; <button onclick="location.reload()" style="font-size:12px;cursor:pointer;border:1px solid var(--bd);background:var(--card);color:var(--mut);padding:2px 10px;border-radius:5px">&#8635; reload</button></div>
</div></body></html>
HTML
mv "$TMP" "$OUT_HTML"

TMPJ="$(mktemp 2>/dev/null || echo "${OUT_JSON}.tmp")"
printf '{"generated":"%s","overall":"%s","pass":%d,"warn":%d,"fail":%d,"checks":[%s]}\n' \
  "$NOW_HUMAN" "$OVERALL" "$PASS_N" "$WARN_N" "$FAIL_N" "$JSON_ITEMS" > "$TMPJ"
mv "$TMPJ" "$OUT_JSON"

# NOTE: the snapshot is NOT written into the local working tree's docs/. Doing so
# rewrote tracked docs/status.{js,json} on every run, leaving the checkout perpetually
# dirty. The Pages publish below writes + commits status.* inside the dedicated
# origin/main worktree instead, so the live site updates without churning your tree.

mkdir -p "$SYSCFG/logs"
hlog() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] publish: $1" >> "$SYSCFG/logs/healthcheck.log"; }

# Publish the snapshot to GitHub Pages (which serves docs/ from origin/main) so the
# live health.html auto-updates. The job normally runs with a FEATURE branch checked
# out, so committing in-place would land status.* on the wrong branch and collide with
# in-flight work. Instead push through a dedicated worktree pinned to origin/main —
# detached so it never hijacks the local `main` ref or touches the user's checkout.
# ponytail: best-effort; any git/auth failure just logs and we still exit 0.
PUBLISH_WT="$HOME/Library/Caches/agent-workspace-health-publish"
if command -v git >/dev/null 2>&1 && git -C "$WORKSPACE" rev-parse --git-dir >/dev/null 2>&1; then
  if [ ! -e "$PUBLISH_WT/.git" ]; then
    git -C "$WORKSPACE" worktree prune 2>/dev/null || true
    git -C "$WORKSPACE" worktree add -q --detach "$PUBLISH_WT" origin/main 2>/dev/null \
      || hlog "worktree add failed (no origin/main yet?) — skipping"
  fi
  if [ -e "$PUBLISH_WT/.git" ] \
     && git -C "$PUBLISH_WT" fetch -q origin main 2>/dev/null \
     && git -C "$PUBLISH_WT" reset -q --hard origin/main 2>/dev/null; then
    if [ -d "$PUBLISH_WT/docs" ]; then
      cp "$OUT_JSON" "$PUBLISH_WT/docs/status.json" 2>/dev/null || true
      { printf 'window.__STATUS__='; cat "$OUT_JSON"; printf ';\n'; } > "$PUBLISH_WT/docs/status.js"
      git -C "$PUBLISH_WT" add docs/status.json docs/status.js 2>/dev/null || true
      if git -C "$PUBLISH_WT" diff --cached --quiet 2>/dev/null; then
        hlog "no status change — nothing to publish"
      elif git -C "$PUBLISH_WT" -c user.name=healthcheck -c user.email=healthcheck@local \
             commit -q -m "chore(health): publish status snapshot [skip ci]" 2>/dev/null \
           && git -C "$PUBLISH_WT" push -q origin HEAD:main 2>/dev/null; then
        hlog "pushed status snapshot to origin/main"
      else
        hlog "commit/push failed (auth or non-fast-forward) — will retry next run"
      fi
    else
      hlog "origin/main has no docs/ dir yet — merge the dashboard branch first"
    fi
  else
    hlog "fetch/reset origin/main failed — skipping publish this run"
  fi
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] healthcheck: ${OVERALL} (pass=${PASS_N} warn=${WARN_N} fail=${FAIL_N})" >> "$SYSCFG/logs/healthcheck.log"
echo "Status: ${OVERALL} — ${PASS_N} pass / ${WARN_N} warn / ${FAIL_N} fail"
echo "Wrote ${OUT_HTML}"
exit 0
