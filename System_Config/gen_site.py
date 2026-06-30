#!/usr/bin/env python3
"""
gen_site.py -- keep docs/index.html in sync with source files.

Managed sections:
  <!-- gen:agents-start --> ... <!-- gen:agents-end -->
  <!-- gen:jobs-start -->   ... <!-- gen:jobs-end -->
  inline: <!-- gen:agent-count -->N<!-- /gen:agent-count -->
  inline: <!-- gen:jobs-count -->N<!-- /gen:jobs-count -->

Sources:
  .claude/agents/*.md  -- name + description from YAML frontmatter
  System_Config/install_*.sh -- discovered job installers

Usage:
  python3 System_Config/gen_site.py          # update docs/index.html in place
  python3 System_Config/gen_site.py --check  # exit 1 if site is stale (healthcheck)
  python3 System_Config/gen_site.py --dry-run # print what would change, no write
"""
import os, re, glob, sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(SCRIPT_DIR)
AGENTS_DIR = os.path.join(ROOT, '.claude', 'agents')
HTML_PATH = os.path.join(ROOT, 'docs', 'index.html')

JOB_META = {
    'install_daily_ingest.sh':   ('Daily ingest',   'daily 07:00 + at login',   'Reads new <code>Vault_Brain/sources/*.md</code> clips and files them into the wiki &mdash; one headless <code>claude -p</code> call per clip, content-hash dedup.'),
    'install_healthcheck.sh':    ('Health check',   'at login + every 4h',       'Probes layers A&ndash;H (orchestration, automation, knowledge, persistence, projects, doc currency, repo hygiene, decision hygiene) and writes the status dashboard to <code>status_page.html</code>, then publishes the snapshot to the <a class="body-link" href="health.html">microsite dashboard</a>.'),
    'install_friday_process.sh': ('Weekly notes',   'Fridays 19:00',             'Writes a 1&ndash;2 sentence weekly summary into the Master Note and regenerates <code>docs/index.html</code> via <code>gen_site.py</code>.'),
    'install_monday_init.sh':    ('Monday init',    'at login + Mon 08:00',      "Creates the week's ISO-named note from <code>Weekly_Note_Template.md</code>, carries forward open tasks, and inserts a row in the Master Note weekly index."),
    'install_sync_skills.sh':    ('Skill sync',     'on install + hourly',       'Watches <code>~/.agents/skills/</code> for <code>npx</code>-installed skills and syncs them to <code>~/.claude/skills/</code>, then flags new arrivals in the <code>master-orchestrator</code> index.'),
}

EXCLUDED_AGENTS = set()

HAND_OFF = {
    'architect':         'coder',
    'coder':             'orchestrator',
    'eng-manager':       'architect, coder',
    'archivist':         'orchestrator',
    'curator':           'orchestrator',
    'creative-director': 'orchestrator',
}

def read_frontmatter(path):
    with open(path) as f:
        content = f.read()
    if not content.startswith('---'):
        return None
    end = content.find('---', 3)
    if end == -1:
        return None
    fm = content[3:end]
    name_m = re.search(r'^name:\s*(.+)$', fm, re.MULTILINE)
    desc_m = re.search(r'^description:\s*(.+)$', fm, re.MULTILINE)
    if not name_m:
        return None
    desc = desc_m.group(1).strip() if desc_m else ''
    short = re.split(r'[.;]', desc)[0].strip()
    if len(short) > 80:
        short = short[:77] + '...'
    return {'name': name_m.group(1).strip(), 'short_desc': short}

def get_agents():
    agents = []
    for path in sorted(glob.glob(os.path.join(AGENTS_DIR, '*.md'))):
        info = read_frontmatter(path)
        if info and info['name'] not in EXCLUDED_AGENTS:
            agents.append(info)
    return agents

def get_jobs():
    scripts = sorted(glob.glob(os.path.join(SCRIPT_DIR, 'install_*.sh')))
    jobs = []
    for s in scripts:
        name = os.path.basename(s)
        if name in JOB_META:
            jobs.append((name, JOB_META[name]))
        else:
            title = name.replace('install_','').replace('.sh','').replace('_',' ').title()
            jobs.append((name, (title, 'scheduled', 'Installed by <code>' + name + '</code>.')))
    return jobs

def build_agents_rows(agents):
    rows = []
    for a in agents:
        name = a['name']
        scope = a['short_desc']
        hand = HAND_OFF.get(name, 'orchestrator')
        row = '              <tr><td><strong>' + name + '</strong></td><td>' + scope + '</td><td><code>.claude/agents/' + name + '.md</code></td><td>' + hand + '</td></tr>'
        rows.append(row)
    return '\n'.join(rows)

def build_job_cards(jobs):
    cards = []
    for fname, (title, sched, desc) in jobs:
        card = (
            '          <div class="job">\n'
            '            <div class="pip-row"><span class="pip" aria-hidden="true"></span><span>healthy</span></div>\n'
            '            <h3>' + title + '</h3>\n'
            '            <p class="sched tabnum">' + sched + '</p>\n'
            '            <p>' + desc + '</p>\n'
            '            <p class="inst">' + fname + '</p>\n'
            '          </div>'
        )
        cards.append(card)
    return '\n'.join(cards)

def replace_block(html, marker, new_content):
    start = '<!-- gen:' + marker + '-start -->'
    end   = '<!-- gen:' + marker + '-end -->'
    pat = re.compile(re.escape(start) + r'.*?' + re.escape(end), re.DOTALL)
    return pat.sub(start + '\n' + new_content + '\n' + end, html)

def replace_inline(html, marker, new_val):
    pat = re.compile(r'<!-- gen:' + re.escape(marker) + r' -->.*?<!-- /gen:' + re.escape(marker) + r' -->', re.DOTALL)
    return pat.sub('<!-- gen:' + marker + ' -->' + new_val + '<!-- /gen:' + marker + ' -->', html)

def main():
    check_mode = '--check' in sys.argv
    dry_run    = '--dry-run' in sys.argv

    with open(HTML_PATH) as f:
        original = f.read()

    html = original
    agents = get_agents()
    jobs   = get_jobs()

    html = replace_block(html, 'agents', build_agents_rows(agents))
    html = replace_block(html, 'jobs',   build_job_cards(jobs))
    html = replace_inline(html, 'agent-count', str(len(agents)))
    html = replace_inline(html, 'jobs-count',  str(len(jobs)))

    if html == original:
        print('gen_site: site is already up to date.')
        sys.exit(0)

    if check_mode:
        print('gen_site: site is STALE -- run python3 System_Config/gen_site.py to update.')
        sys.exit(1)

    if dry_run:
        import difflib
        diff = difflib.unified_diff(original.splitlines(), html.splitlines(), lineterm='', n=2)
        print('\n'.join(list(diff)[:60]))
        sys.exit(0)

    with open(HTML_PATH, 'w') as f:
        f.write(html)
    print('gen_site: updated ' + HTML_PATH)
    print('  agents: ' + str(len(agents)) + '  jobs: ' + str(len(jobs)))

if __name__ == '__main__':
    main()
