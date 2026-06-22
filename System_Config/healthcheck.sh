#!/usr/bin/env bash
# healthcheck.sh — workspace architecture health check → status_page.html
# Probes every layer (orchestration, automation, knowledge base, persistence,
# projects) and renders a self-contained HTML status page + status.json.
#
# Scheduled via launchd — see healthcheck.plist.tmpl (label com.<username>.vaultbrain.healthcheck)
#   Activate:   bash System_Config/install_healthcheck.sh
#   Manual:     bash System_Config/healthcheck.sh
#   View:       open System_Config/status_page.html
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
  for ag in architect coder eng-manager archivist curator; do
    f="$AGENTS/$ag.md"
    if [ -s "$f" ]; then
      # count DISTINCT required keys in the first frontmatter block (dup lines don't inflate it)
      d=0
      for k in name description tools model; do
        awk -v key="$k" '/^---$/{n++; next} n==1 && $0 ~ ("^" key ":"){hit=1} END{exit !hit}' "$f" && d=$((d + 1))
      done
      if [ "$d" -ge 4 ]; then check PASS "Agent: $ag" "frontmatter complete (name/description/tools/model)"; else check WARN "Agent: $ag" "frontmatter incomplete (${d}/4 required keys)"; fi
    else
      check FAIL "Agent: $ag" "missing or empty ${ag}.md"
    fi
  done
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
<div class="ft">Generated ${NOW_HUMAN} &middot; ${HOST} &middot; regenerate with <code>bash System_Config/healthcheck.sh</code></div>
</div></body></html>
HTML
mv "$TMP" "$OUT_HTML"

TMPJ="$(mktemp 2>/dev/null || echo "${OUT_JSON}.tmp")"
printf '{"generated":"%s","overall":"%s","pass":%d,"warn":%d,"fail":%d,"checks":[%s]}\n' \
  "$NOW_HUMAN" "$OVERALL" "$PASS_N" "$WARN_N" "$FAIL_N" "$JSON_ITEMS" > "$TMPJ"
mv "$TMPJ" "$OUT_JSON"

mkdir -p "$SYSCFG/logs"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] healthcheck: ${OVERALL} (pass=${PASS_N} warn=${WARN_N} fail=${FAIL_N})" >> "$SYSCFG/logs/healthcheck.log"
echo "Status: ${OVERALL} — ${PASS_N} pass / ${WARN_N} warn / ${FAIL_N} fail"
echo "Wrote ${OUT_HTML}"
exit 0
