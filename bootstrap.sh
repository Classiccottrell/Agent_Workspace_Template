#!/usr/bin/env bash
#
# bootstrap.sh — one-command setup for the Agent Workspace Template.
#
# Operates IN PLACE at the location you cloned to. It is idempotent and safe:
# it never deletes or overwrites your data. Re-run it any time.
#
#   ./bootstrap.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

SYSCFG="$ROOT/System_Config"

echo "=================================================="
echo " Agent Workspace Template — bootstrap"
echo " Workspace: $ROOT"
echo "=================================================="
echo

# ---------------------------------------------------------------------------
# 1. Make scripts executable.
# ---------------------------------------------------------------------------
echo "→ Making scripts executable…"
chmod +x "$ROOT/bootstrap.sh"
if [ -d "$SYSCFG" ]; then
  for f in "$SYSCFG"/*.sh; do
    [ -e "$f" ] || continue
    chmod +x "$f"
  done
fi

# ---------------------------------------------------------------------------
# 2. Ensure the log directory exists (launchd opens its redirect targets here).
# ---------------------------------------------------------------------------
echo "→ Ensuring System_Config/logs exists…"
mkdir -p "$SYSCFG/logs"

# ---------------------------------------------------------------------------
# 3. Seed .mcp.json from the example if absent (never overwrite an existing one).
# ---------------------------------------------------------------------------
if [ ! -f "$ROOT/.mcp.json" ] && [ -f "$ROOT/.mcp.json.example" ]; then
  cp "$ROOT/.mcp.json.example" "$ROOT/.mcp.json"
  echo "→ Created .mcp.json from .mcp.json.example."
  echo "    Edit .mcp.json to add your MCP servers, then enable them in"
  echo "    .claude/settings.json under enabledMcpjsonServers."
elif [ -f "$ROOT/.mcp.json" ]; then
  echo "→ .mcp.json already present — leaving it untouched."
fi
echo

# ---------------------------------------------------------------------------
# 4. Prerequisite check (informational — does not block).
# ---------------------------------------------------------------------------
echo "→ Checking prerequisites…"
# Agent CLI — this workspace is provider-agnostic. Prefer agy (Gemini/Antigravity),
# fall back to claude (Claude Code). Mirrors the resolution order in config.sh.
if command -v agy >/dev/null 2>&1; then
  echo "    [ok]   Gemini CLI (agy / Antigravity) found: $(command -v agy)"
elif command -v gemini >/dev/null 2>&1; then
  echo "    [ok]   Gemini CLI found: $(command -v gemini)"
elif command -v claude >/dev/null 2>&1; then
  echo "    [ok]   Claude Code CLI found: $(command -v claude)"
else
  echo "    [warn] No agent CLI found on PATH (need 'agy', 'gemini', or 'claude')."
  echo "           Gemini CLI:  https://github.com/google-gemini/gemini-cli"
  echo "           Claude Code: https://docs.claude.com/en/docs/claude-code"
fi

case "$(uname -s)" in
  Darwin) echo "    [ok]   macOS detected — background automation (launchd) is available." ;;
  *)      echo "    [warn] Not macOS — the launchd automation will not install here;"
          echo "           the agents and the Vault_Brain wiki still work." ;;
esac

# Optional tooling — nothing below blocks the install.
if command -v gh >/dev/null 2>&1; then
  echo "    [ok]   GitHub CLI (gh) found: $(command -v gh)"
  if ! gh auth status >/dev/null 2>&1; then
    echo "           Not authenticated yet — run: gh auth login"
  fi
else
  echo "    [opt]  GitHub CLI (gh) not found — agents use it for commit/push/PR"
  echo "           without burning model tokens. Install: brew install gh"
fi
if command -v node >/dev/null 2>&1 && command -v npx >/dev/null 2>&1; then
  echo "    [ok]   node/npx found: $(node --version)"
else
  echo "    [opt]  node/npx not found — needed by skill sync (npx skills) and"
  echo "           Playwright. Install: brew install node"
fi
if command -v python3 >/dev/null 2>&1; then
  echo "    [ok]   python3 found: $(command -v python3)"
else
  echo "    [opt]  python3 not found — needed by the doc-currency hook and the"
  echo "           weekly site generator. Install: brew install python3"
fi

echo "    [note] To run the background automation, grant Full Disk Access to /bin/bash"
echo "           (System Settings → Privacy & Security → Full Disk Access; drag in"
echo "           /bin/bash via Finder ⌘⇧G → /bin). See System_Config/README.md."
echo

# ---------------------------------------------------------------------------
# 5. Scheduling choice — auto (launchd agents) vs manual (run by hand) vs skip.
# ---------------------------------------------------------------------------
SCHEDULE="skip"
if [ "$(uname -s)" = "Darwin" ]; then
  echo "Weekly-note + ingest automation — how do you want to run it?"
  echo "  [a] auto   — install launchd agents: daily ingest (07:00), health check,"
  echo "               Friday close-out (16:30), Monday note init (login + Mon 08:00),"
  echo "               skill sync (on npx install + hourly)"
  echo "  [m] manual — no agents; you run the scripts by hand when you want"
  echo "  [s] skip   — decide later (default)"
  printf "Choose [a/m/s]: "
  if [ -t 0 ]; then
    read -r REPLY || REPLY=""
  else
    REPLY=""
    echo "(non-interactive: skipping — install later with the commands below)"
  fi
  case "$REPLY" in
    [aA]|[aA][uU][tT][oO])         SCHEDULE="auto" ;;
    [mM]|[mM][aA][nN][uU][aA][lL]) SCHEDULE="manual" ;;
    *)                             SCHEDULE="skip" ;;
  esac
fi

case "$SCHEDULE" in
  auto)
    echo
    echo "→ Installing launchd agents (auto scheduling)…"
    bash "$SYSCFG/install_daily_ingest.sh"
    bash "$SYSCFG/install_healthcheck.sh"
    bash "$SYSCFG/install_friday_process.sh"
    bash "$SYSCFG/install_monday_init.sh"
    bash "$SYSCFG/install_sync_skills.sh"
    echo "→ Automation installed. Verify with: launchctl list | grep vaultbrain"
    ;;
  manual)
    echo
    echo "→ Manual mode — no agents installed. Run the weekly scripts by hand:"
    echo "      bash System_Config/monday_init.sh      # start the week (DRY_RUN=1 to preview)"
    echo "      bash System_Config/friday_process.sh   # close out the week"
    echo "      bash System_Config/daily_ingest.sh     # ingest new clips"
    echo "    Switch to auto anytime by running the install_*.sh scripts."
    ;;
  *)
    echo
    echo "→ Skipping scheduling for now. Install later — auto (all five agents):"
    echo "      bash System_Config/install_daily_ingest.sh"
    echo "      bash System_Config/install_healthcheck.sh"
    echo "      bash System_Config/install_friday_process.sh"
    echo "      bash System_Config/install_monday_init.sh"
    echo "      bash System_Config/install_sync_skills.sh"
    echo "    …or just run them by hand (manual): bash System_Config/monday_init.sh, etc."
    ;;
esac

# ---------------------------------------------------------------------------
# 5b. Knowledge Base strategy selection.
# ---------------------------------------------------------------------------
echo
KB_STRATEGY="obsidian"
echo "→ Knowledge Base strategy — how will you view and clip notes?"
echo "  [1] Obsidian + Obsidian Web Clipper  (default)"
echo "        Native wikilinks, graph view, and backlinks."
echo "        Obsidian Web Clipper saves web pages to Vault_Brain/sources/."
echo "        Guide: docs/kb-obsidian.md"
echo "  [2] VS Code + MarkSnip"
echo "        Foam extension for graph, backlinks, and wikilinks in VS Code."
echo "        MarkSnip browser extension clips web pages to Vault_Brain/sources/."
echo "        Guide: docs/kb-vscode.md"
printf "Choose [1/2, default 1]: "
if [ -t 0 ]; then
  read -r KB_REPLY || KB_REPLY=""
else
  KB_REPLY=""
  echo "(non-interactive: defaulting to Obsidian + Obsidian Web Clipper)"
fi
case "$KB_REPLY" in
  2) KB_STRATEGY="vscode" ;;
  *) KB_STRATEGY="obsidian" ;;
esac

# Write KB_STRATEGY into config.sh (sed -i requires a backup extension on macOS bash 3.2)
sed -i.bak "s/^KB_STRATEGY=.*/KB_STRATEGY=\"${KB_STRATEGY}\"/" "$SYSCFG/config.sh" && rm -f "$SYSCFG/config.sh.bak"

echo "    [ok]   KB_STRATEGY set to: $KB_STRATEGY"

if [ "$KB_STRATEGY" = "vscode" ]; then
  echo "    [ok]   Writing Vault_Brain/.vscode/extensions.json with recommended extensions…"
  mkdir -p "$ROOT/Vault_Brain/.vscode"
  cat > "$ROOT/Vault_Brain/.vscode/extensions.json" << 'VSCJSON'
{
  "recommendations": [
    "foam.foam-vscode",
    "bierner.github-markdown-preview",
    "CodeSmith.markdown-inline-editor-vscode",
    "foam.foam-vscode-paste-image",
    "Gruntfuggly.todo-tree"
  ]
}
VSCJSON
  echo "    [ok]   Open Vault_Brain/ in VS Code and install recommended extensions."
fi

# ---------------------------------------------------------------------------
# 5c. Note ingestion configuration (all defaults are safe — Enter to accept).
# ---------------------------------------------------------------------------
echo
echo "→ Note ingestion — the daily job that wikifies clips and notes into Vault_Brain."
if [ -t 0 ]; then
  printf "  Source folders inside Vault_Brain/, colon-separated [sources]: "
  read -r ING_SOURCES || ING_SOURCES=""
  printf "  Provider — auto / claude / gemini [auto]: "
  read -r ING_PROVIDER || ING_PROVIDER=""
  printf "  Daily run hour, 0-23 [7]: "
  read -r ING_HOUR || ING_HOUR=""
  printf "  Per-clip budget in USD, claude only [1.00]: "
  read -r ING_BUDGET || ING_BUDGET=""
else
  ING_SOURCES=""; ING_PROVIDER=""; ING_HOUR=""; ING_BUDGET=""
  echo "  (non-interactive: keeping defaults — sources, auto, 07:00, \$1.00)"
fi
# Validate; anything odd falls back to the default already in config.sh.
case "$ING_PROVIDER" in claude|gemini|auto) ;; *) ING_PROVIDER="" ;; esac
case "$ING_HOUR" in [0-9]|1[0-9]|2[0-3]) ;; *) ING_HOUR="" ;; esac
case "$ING_BUDGET" in *[!0-9.]*|"") ING_BUDGET="" ;; esac
[ -n "$ING_SOURCES" ]  && sed -i.bak "s|^INGEST_SOURCES=.*|INGEST_SOURCES=\"\${INGEST_SOURCES:-${ING_SOURCES}}\"|"   "$SYSCFG/config.sh"
[ -n "$ING_PROVIDER" ] && sed -i.bak "s|^INGEST_PROVIDER=.*|INGEST_PROVIDER=\"\${INGEST_PROVIDER:-${ING_PROVIDER}}\"|" "$SYSCFG/config.sh"
[ -n "$ING_HOUR" ]     && sed -i.bak "s|^INGEST_HOUR=.*|INGEST_HOUR=\"\${INGEST_HOUR:-${ING_HOUR}}\"|"                "$SYSCFG/config.sh"
[ -n "$ING_BUDGET" ]   && sed -i.bak "s|^INGEST_MAX_BUDGET=.*|INGEST_MAX_BUDGET=\"\${INGEST_MAX_BUDGET:-${ING_BUDGET}}\"|" "$SYSCFG/config.sh"
rm -f "$SYSCFG/config.sh.bak"
echo "    [ok]   Ingestion config: sources=${ING_SOURCES:-sources} provider=${ING_PROVIDER:-auto} hour=${ING_HOUR:-7} budget=\$${ING_BUDGET:-1.00}"
if [ "$SCHEDULE" = "auto" ] && [ -n "$ING_HOUR" ]; then
  echo "    [note] Re-rendering the ingest schedule with your hour…"
  bash "$SYSCFG/install_daily_ingest.sh" >/dev/null
  echo "    [ok]   Daily ingest rescheduled to ${ING_HOUR}:00."
fi

# ---------------------------------------------------------------------------
# 6. Remote Git repository (optional).
# ---------------------------------------------------------------------------
echo
echo "→ Remote Git repository (optional)"
echo "  Link this workspace to a remote repo to push/pull from another machine."

GIT_REMOTE=""
if git remote get-url origin >/dev/null 2>&1; then
  echo "    [ok]   Remote already configured: $(git remote get-url origin)"
elif [ -t 0 ]; then
  # gh path: create the repo for the user instead of asking for a URL.
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    printf "  Create a private GitHub repo for this workspace with gh? [y/N]: "
    read -r GH_REPLY || GH_REPLY=""
    case "$GH_REPLY" in
      [yY]*)
        git branch -M main
        if gh repo create "$(basename "$ROOT")" --private --source . --remote origin --push; then
          echo "    [ok]   Repo created and pushed via gh."
        else
          echo "    [warn] gh repo create failed — add a remote manually later."
        fi
        ;;
      *) echo "    [skip] No remote configured. Later: gh repo create --private --source . --push" ;;
    esac
  else
    printf "  Enter remote URL (leave blank to skip): "
    read -r GIT_REMOTE || GIT_REMOTE=""
  fi
else
  echo "  (non-interactive: skipping — add manually: git remote add origin <url>)"
fi

if [ -n "$GIT_REMOTE" ]; then
  git remote add origin "$GIT_REMOTE" 2>/dev/null || git remote set-url origin "$GIT_REMOTE"
  git branch -M main
  git push -u origin main
  echo "    [ok]   Remote set: $GIT_REMOTE"
elif ! git remote get-url origin >/dev/null 2>&1; then
  echo "    [skip] No remote configured. Add later:"
  echo "           git remote add origin <url>   (or: gh repo create --private --source . --push)"
  echo "           git branch -M main && git push -u origin main"
fi

# ---------------------------------------------------------------------------
# Hook wiring — doc currency check (idempotent).
# ---------------------------------------------------------------------------
echo "→ Wiring doc-currency hook into .claude/settings.json…"
HOOK_PY="$ROOT/.claude/hooks/readme-currency-check.py"
SETTINGS="$ROOT/.claude/settings.json"
if [ -f "$HOOK_PY" ] && [ -f "$SETTINGS" ] && command -v python3 >/dev/null 2>&1; then
  python3 - "$SETTINGS" "$HOOK_PY" << 'PYEOF2'
import json, sys
settings_path, hook_path = sys.argv[1], sys.argv[2]
with open(settings_path) as f:
    s = json.load(f)
hooks = s.setdefault("hooks", {})
pt = hooks.setdefault("PostToolUse", [])
pt[:] = [h for h in pt if "readme-currency-check" not in str(h)]
pt.append({
    "matcher": "Write|Edit|MultiEdit",
    "hooks": [{
        "type": "command",
        "command": f'python3 "{hook_path}" 2>/dev/null || true',
        "timeout": 15,
        "statusMessage": "README currency check"
    }]
})
with open(settings_path, "w") as f:
    json.dump(s, f, indent=2)
    f.write("\n")
PYEOF2
  echo "    [ok]   Doc-currency hook wired at: $HOOK_PY"
else
  echo "    [skip] python3 not found or files missing — wire manually:"
  echo "           Add to .claude/settings.json > hooks > PostToolUse (see docs/)"
fi

# ---------------------------------------------------------------------------
# 7. Next steps.
# ---------------------------------------------------------------------------
echo
echo "=================================================="
echo " Done. Next steps:"
echo "=================================================="

if [ "$KB_STRATEGY" = "vscode" ]; then
  echo " 1. Open Vault_Brain/ in VS Code:"
  echo "      code Vault_Brain/"
  echo "    Install recommended extensions when prompted, then open the Foam graph:"
  echo "      ⌘⇧P → Foam: Show Graph"
  echo "    Full guide: docs/kb-vscode.md"
else
  echo " 1. Open the knowledge vault in Obsidian:"
  echo "      Open Vault_Brain/ (not the workspace root) as an Obsidian vault."
  echo "    Install the Obsidian Web Clipper browser extension."
  echo "    Import the bundled template: System_Config/obsidian-webclipper-template.json"
  echo "    Full guide: docs/kb-obsidian.md"
fi

echo " 2. Drop a clip or note into Vault_Brain/sources/ to feed the wiki."
echo " 3. Run the health check and open the dashboard:"
echo "      bash System_Config/healthcheck.sh"
echo "      open System_Config/status_page.html"
echo " 4. Start working from this folder: run 'agy'/'gemini' (Gemini/Antigravity) or 'claude' (Claude Code)."
echo
echo " Reference: README.md, .AGENT.MD, System_Config/README.md, Vault_Brain/README.md"
echo
