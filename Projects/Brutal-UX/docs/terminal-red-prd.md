# Terminal Red — Business Plan & PRD

**Product:** Terminal Red, a B2B incident command and server monitoring dashboard built on UX Brutalism.
**One-liner:** Ugly and fast beats pretty and slow when the site is down.
**Demo:** `/terminal-red` route in the Brutal UX app.
**Status:** Plan, execution-ready.

## 1. Executive Summary & Value Proposition

During an outage, cognitive load is the enemy and every design flourish is a tax paid in downtime. Gartner-class estimates put enterprise downtime at $5,600+ per minute [verify: refresh this figure and source before any deck goes out]. Against that number, a 400ms dashboard transition is not a design choice, it is a line item. Modern observability suites (Datadog, Grafana Cloud, New Relic) are built to look impressive in the sales demo: gradients, animated charts, skeleton loaders. At 3am with the primary database down, those same features slow the human in the loop.

Terminal Red is the opposite bet. It looks like the Bloomberg Terminal because the Bloomberg Terminal is what interfaces look like when every pixel has to earn money: black background, high-contrast utility colors, immense data density, zero decoration. The pitch to a CTO is one sentence: **your SREs read state faster and act faster on an interface with nothing to interpret, and minutes of MTTR are dollars.**

Value proposition: the fastest read-and-act surface in incident response. Not a prettier pane of glass, a faster human.

## 2. Core Feature Loop

The Incident Command protocol:

1. **Alert fires.** The affected node block flips to a hard-flashing absolute-red state (CSS `steps()`, no fade). A full-width red bar stamps across the top of the dashboard with the incident ID and elapsed timer. No sound design, no toast queue; the screen itself is the alarm.
2. **Read.** Raw logs stream into a plain HTML table, newest first, terminal-green on black, capped ring buffer. Filter is a single text input applying instantly per keystroke. No log-level color rainbow; ERROR lines are red, everything else is green. Metrics are printed numbers that jump when the value changes, not line charts that animate toward it.
3. **Act.** Every remediation is a single-click trigger wired to a pre-approved runbook command: KILL NODE, RESTART SERVICE, DRAIN TRAFFIC, ROLL BACK. Click means execute, now. No "Are you sure?" modal, no loading spinner; the button flips to EXECUTED with the return code beside it. Safety lives in RBAC and pre-authorization at configuration time, not in confirmation friction at execution time. An engineer authorized to see the button is authorized to press it.
4. **Record.** Every click and every state change appends to an immutable incident timeline (raw table, exportable) that becomes the post-mortem source of truth. No one reconstructs the incident from Slack scrollback.

## 3. Brutal UX Constraints (frontend engineering rules)

- Layout: raw wireframe boxes. `2px solid` borders (white on black), rigid CSS grid sized by data density, no card shadows, no border-radius.
- Palette: `#000000` background, `#FFFFFF` structure, `#00FF00` data streams, `#FF0000` alerts and destructive triggers. Nothing else. No gradients anywhere in the product, enforced by lint rule.
- Alerts: hard binary flash via `steps(1)`. A fading alert is an alert that understates itself.
- Logs: strict HTML `<table>` rows, monospace, no virtual-scroll library until a real dump proves the DOM cap insufficient. Ring buffer caps visible rows so the DOM never grows unbounded.
- Motion: zero transitions, zero easing, zero skeleton loaders. Data that has not arrived renders as `--`.
- Triggers: one click, immediate dispatch, result code printed inline. Confirmation modals are banned by the design constitution; if a command is too dangerous for one click, it should not have been granted to that role.
- Type: system monospace only. Uppercase labels. Density target: a 27" monitor shows 40+ nodes and 60+ log lines without scrolling.

## 4. B2B Monetization Strategy

Utility-based pricing, itemized, no "Contact Sales" fog:

| Plan | Price | What it covers |
|------|-------|----------------|
| Per-Node | $15/node/month | Full dashboard, alerting, log streaming, incident timeline. Public price list, no negotiation theater. |
| Trigger Pack | +$500/month flat | Runbook execution triggers, RBAC, audit log. Flat because safety infrastructure should not scale with fear. |
| Self-Hosted | $30k/year site license | Full binary, runs in the customer's VPC. Banks and healthcare will pay double for data that never leaves. |

Egress and storage billed at raw cloud cost plus a printed 10% handling multiplier, itemized on every invoice. The invoice IS the brand: the only monitoring vendor whose bill you can read.

## 5. Go-To-Market Strategy

SREs are not reached by ads; they are reached by respect.

- **Where they are:** Hacker News, r/sre and r/devops, SREcon and Monitorama hallway tracks, the incident.io/PagerDuty post-mortem blog readership, and on-call Slack communities.
- **Wedge:** open-source the read-only dashboard core (the Grafana playbook, executed with more severity). The paid product is triggers, RBAC, and the audit timeline, the parts a company needs the moment more than three people share an on-call rotation.
- **Content:** post real MTTR comparisons, "same incident, two dashboards" screen recordings. The demo sells itself because the difference is visible in the first second.
- **Pitch to the CTO:** bottom-up adoption first, then the economic memo: MTTR minutes saved times downtime cost per minute versus per-node price. Terminal Red is bought as insurance with a visible deductible.
- **Anti-marketing as marketing:** the homepage is the live dashboard with fake data. No hero video, no customer-logo carousel. "This is the product. It loads in 200ms. Yours does not."

## 6. Technical Architecture

High-throughput, low-latency, boring on purpose:

- **Ingest:** agents and webhooks land on a Go (or Rust) ingest tier, into NATS or Kafka for fan-out. Hot metrics state lives in Redis; long-term logs in ClickHouse, which exists for exactly this table-scan workload.
- **Transport:** WebSockets from edge nodes to the browser, one multiplexed connection per client, server-side coalescing to a fixed tick (100ms) so a log storm becomes batched appends, never a message flood.
- **Frontend:** brutally lightweight DOM. Preact or vanilla TS, no virtual-DOM churn on the hot path. Log stream appends use direct DOM writes into the capped table; off-screen rows are dropped from the tree. No charting library in the incident view at all; numbers are text.
- **Triggers:** signed command dispatch to per-customer runners (SSM/Salt/Ansible adapters), result codes streamed back over the same socket. Every dispatch written to an append-only audit store before execution is acknowledged.
- **Performance budget:** initial load under 100KB JS, alert-to-pixel under 150ms end to end, 10k log lines/minute sustained without frame drops, enforced by load-test CI.

**Next move:** build the read-only OSS core against fake ingest, get it on Hacker News, and let the KILL NODE screenshot do the acquisition.
