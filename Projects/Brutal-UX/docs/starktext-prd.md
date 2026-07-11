# StarkText — Business Plan & PRD

**Product:** StarkText, a counter-culture publishing and newsletter platform built on UX Brutalism.
**One-liner:** The raw utility of words delivered via HTTP.
**Demo:** `/starktext` route in the Brutal UX app.
**Status:** Plan, execution-ready.

## 1. Executive Summary & Value Proposition — the Anti-Platform Manifesto

Medium and Substack are engagement companies that happen to host writing. Every feature they ship, claps, read-time estimates, recommendation feeds, pop-over subscribe walls, exists to keep the reader on the platform, not to move a thought from one head to another. Writers on those platforms are inventory.

StarkText is the anti-platform. The manifesto position: **stripping features is the premium.** Hacker News runs the most influential text community in tech on default fonts and zero avatars. text.npr.org exists because when things actually matter, NPR deletes its own design. motherfuckingwebsite.com made the argument a decade ago and it has never been refuted, only ignored. StarkText productizes that refusal: no likes, no comments, no algorithm, no read-time bar, no tracking pixel. A writer types markdown. A reader gets high-contrast monospaced text over HTTP. Done.

The market is real and underserved: tech writers, privacy advocates, philosophers, hackers, and minimalists who experience the modern web as hostile. They do not want a better feed. They want out of feeds entirely, without maintaining their own static-site toolchain.

**Value proposition:** the shortest distance between a thought and a reader, with a guarantee, contractual, not aspirational, that the platform will never insert itself between them.

## 2. Core Feature Loop

**Creation:**
1. Sign up with email. No profile photo, no bio prompt, no "pick 5 topics."
2. One screen: a raw markdown editor (a `<textarea>`, deliberately) with instant compiled preview beside it. No block editor, no slash commands, no AI writing assistant.
3. Hit PUBLISH. The post compiles to static HTML and is live at `yourname.starktext.net/slug` in under a second. Edits republish the same way.

**Reading:**
- Pure semantic HTML, system monospace, high contrast, one column. No JavaScript required to read anything, ever. That is a published guarantee, verifiable by view-source.
- RSS and Atom feeds on by default for every author. Full-text in the feed, no truncation-to-drive-clicks.
- Email subscription: plain-text email of the full post. No open-tracking pixel, no click-wrapped links.
- No recommendation engine. Discovery is the writer's own links, a plain chronological public firehose page, and an opt-in human-curated index. If a post travels, it travels because someone sent it to someone.

**The loop that retains writers:** publish → readers arrive from links and RSS → subscriber count (a plain number, updated on page load, no dashboard theatrics) → write again. No streaks, no "your stats are up 12%!" dopamine mail.

## 3. Brutal UX Constraints (frontend engineering rules)

- Reader pages: strict HTML5 semantic tags (`article`, `h1-h3`, `p`, `blockquote`, `pre`, `ul`). Zero `<div>` soup, zero external CSS frameworks. One inline stylesheet under 2KB.
- Zero JavaScript on reader pages. Not "minimal." Zero. Interactivity budget for readers is the browser itself: find-in-page, reader mode, print.
- Typography: system monospace stack. No web fonts, ever; a font download is a tax on the first word.
- Palette: `#000` on `#FFF`, `prefers-color-scheme` inverts it. Links are underlined, `#0000EE`. Nothing else.
- Layout: single column, max-width set in `ch` units for reading measure, `2px solid #000` rules between article sections. `border-radius: 0`.
- Editor: the writer-side app may use JavaScript for the live preview, but the compiled output must pass an automated audit: no script tags, no third-party requests, no tracking parameters. The audit runs on every publish and blocks violations.
- Performance: any article, full page weight under 20KB before images. Images opt-in, lazy, with required alt text.

## 4. Monetization Strategy

An anti-capitalist-feeling platform makes money the way Pinboard does: charge a small, honest fee for utility, and never monetize attention.

| Item | Price | Notes |
|------|-------|-------|
| Publishing | Free, forever | Unlimited posts, RSS, hosted subdomain. Free tier is the product, not a trial. |
| Custom domain mapping | $10/year flat | Covers cert automation and routing. Priced as utility, not as a plan. |
| Paid subscriptions for writers | 0% platform cut | Stripe direct between writer and reader; writers pay Stripe's fee and nothing to us. |
| Supporter license | $20/year optional | No features. A line on the invoice that says you want this to exist. Pinboard and SourceHut both proved people pay it. |

The zero-cut subscription line is the acquisition weapon against Substack's 10%. StarkText makes infrastructure money, not attention money, and the P&L stays legible: domains and supporters versus static hosting costs, which round toward zero at this page weight.

## 5. Go-To-Market & Growth

Building network effects without viral loops means borrowing distribution from places that already share links as a habit:

- **Launch:** Show HN plus the manifesto (below). The manifesto is the marketing; view-source on the manifesto page is the demo.
- **Seed writers:** hand-recruit 20 writers with existing audiences who already complain about Substack (privacy people, protocol bloggers, plaintext-email advocates). Migration tool imports from Substack/Medium exports in one upload.
- **Growth mechanics without algorithms:** every post footer carries one line, "Published on StarkText. No tracking. View source." That footer is the entire referral system. RSS-first design makes every feed reader a distribution channel we do not control and do not need to.
- **Webring, unironically:** an opt-in chronological index and per-topic rings maintained by humans. The retro mechanic is the brand.

Launch manifesto draft:

> **WORDS OVER EVERYTHING.**
>
> Your last platform measured your readers. It tracked their eyes, timed their attention, and sold the aggregate.
> We built the opposite. You write markdown. They read text. Nothing watches either of you.
> No likes. No comments. No algorithm. No pixel.
> If your writing needs an engagement loop to survive, let it die.
> If it needs readers, publish it here and send the link.
>
> StarkText. The raw utility of words delivered via HTTP.

## 6. Technical Architecture

Statically generated, edge-served, aggressively boring:

- **Compile:** markdown to HTML with a small strict pipeline (remark or a hand-rolled CommonMark subset) inside the publish service. Output is plain HTML files, no framework runtime. Astro or Next.js static export works for the writer-facing app shell; reader pages need no framework at all.
- **Hosting:** static files on an edge network (Cloudflare Pages / R2 or equivalent). Publish writes files and purges cache; global delivery is instant because there is nothing to render.
- **Writer app:** small SPA (editor, settings, subscriber list) talking to a thin API: Postgres for accounts/posts/subscribers, one queue for email fan-out.
- **Email:** plain-text via SES or Postmark, no tracking domains, List-Unsubscribe header done right.
- **Custom domains:** automated ACME certs, CNAME onto the edge. This is the $10/year cost center and it is nearly free at scale.
- **Privacy posture as architecture:** no analytics scripts anywhere; server-side request counts only, aggregated daily, shown to the writer as one number. Nothing exists that could be subpoenaed into a surveillance product later.
- **Performance budget:** reader TTFB under 100ms globally, full article render under 200ms on a 3G phone, enforced in CI against a corpus of real posts.

**Next move:** ship the compile-and-serve core with the manifesto as post #1, then recruit the first 20 writers by hand before any public signup.
