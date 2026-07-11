---
name: hero-image-selector
version: 2.0
author: West Coast Modern
description: >
  Select the best hero image(s) from a batch of real estate property photos for West Coast Modern.
  Use this skill whenever someone uploads multiple property photos and wants to identify the hero shot,
  narrow down a large photo set, score images for editorial quality, or sequence photos for a listing.
  Trigger even if the user just says "pick the best one", "which photo leads?", "help me cut these down",
  or drops a folder of images without explanation.
---

# Hero Image Selector Skill
## West Coast Modern — Property Photography Curation

---

## Purpose

Given a batch of property photos (uploaded directly or referenced by path), identify:
1. **The Hero** — single best image to lead the listing, email, and Instagram
2. **Hero Vertical Alternative** — best vertical crop or vertical-native photo for Instagram/email
3. **Hero 2** — second-best thumbnail option (backup)
4. **Shortlist** — top 5–8 for gallery and tour sequence
5. **Cuts** — images to discard with brief reason

This skill is designed to take Trent from 200+ photos → 50 reviewed → 5 hero candidates in one pass.

---

## Inputs

**Required:**
- A folder of images, OR images uploaded directly to the conversation

**Optional but recommended:**
- Property name (e.g. "Floating House", "Totem House")
- Property hook or story angle (e.g. "the totems are the story — try to hero one that shows them")
- Trent's taste reference document (paste contents of `TASTE_REFERENCE_TEMPLATE.md` if available)
- Delivery target: `MLS` | `Instagram` | `Email` | `Feature Story` | `All`

**If taste reference is not provided:** the skill defaults to the WCM Taste Profile below.

---

## WCM Taste Profile

These editorial values define what West Coast Modern selects for. This is the default calibration.

### What makes a strong EXTERIOR hero

1. **Architecture is the subject** — the building reads clearly, not cropped or obscured; full personality visible
2. **Natural, directional light** — golden hour, crisp morning, or atmospheric overcast; not flat midday
3. **West Coast materiality** — wood, concrete, glass, stone, and natural landscaping are visible
4. **Breathing room** — sky, treeline, ocean, or hillside gives context and scale
5. **Cinematic or atmospheric mood** — warmth, calm, aspiration; not clinical or transactional
6. **Clean foreground** — no cars, bins, construction, or clutter unless architecturally intentional
7. **Horizontal format preferred** — wide compositions read best as hero and thumbnail
8. **Tells the hook** — if the property has a defining story (totems, cantilevered over ocean, etc.), the hero should show it
9. **Reads at thumbnail** — test mentally: does this image work as a 400x300px thumbnail on a phone screen?

### What makes a strong INTERIOR hero

> Note: Interior heroes are only selected when no strong exterior exists. Flag this if it happens.

1. Great room or principal space — the most architectural room in the house
2. Natural light flooding in — interior shots live or die by window light
3. A clear sense of spatial depth and scale
4. Furniture and styling must be immaculate — any clutter disqualifies

### Automatic disqualifiers for hero role

- Overexposed or underexposed beyond recovery
- Heavy lens distortion without artistic intent
- Cluttered or busy foreground (cars, bins, staging props)
- Closed doors or blocked entries
- Bleak weather that reads depressing (not the same as moody — moody is intentional)
- Close-in detail shots (fixtures, handles, tile) — these are supporting content
- Interior-only shots when exterior exists
- Drone shots that are so high the house is a speck

---

## Scoring Rubric

Score each candidate image 1–10 per dimension:

| Dimension | What to assess |
|---|---|
| **Architecture clarity** | Does the building read clearly as the subject? Does it work at thumbnail size? |
| **Light quality** | Is the lighting flattering, natural, directional? No flat midday light? |
| **Composition** | Rule of thirds, leading lines, breathing room, horizon placement, clean foreground |
| **Emotional resonance** | Does this make someone stop scrolling? Does it create aspiration? |
| **Brand fit** | Does it feel like WCM — warm, editorial, design-forward, luxury without pretension? |
| **Technical quality** | Sharp focus, correct exposure, no blown highlights, clean color |

**Total score = sum of 6 dimensions (max 60)**

Tiebreaker question: *Which image would make someone stop scrolling on Instagram at 7am on a Tuesday?* That's the hero.

---

## Selection Process (Step by Step)

**Step 1 — Full scan, no scoring yet**
Review every image in the batch. Calibrate to the range. What's the ceiling? What's the floor? Note obvious disqualifiers.

**Step 2 — Identify exterior candidates**
Pull all exterior shots. These are the hero pool. Note any with unique architectural features or story hooks.

**Step 3 — Score each exterior candidate**
Apply the rubric. Be honest about weaknesses. Exceptional emotional resonance can outweigh a lower technical score.

**Step 4 — Compare top 3**
When 2–3 images are close, use the tiebreaker. The hero is the one that performs best as a single image with no context.

**Step 5 — Select vertical hero**
From the same exterior pool, find the best vertical composition. Can be a vertical-native shot or a vertical crop of the hero. Must work for Instagram Stories and email.

**Step 6 — Select Hero 2**
Second-best thumbnail option. Should feel distinct from Hero 1 — different angle or moment, not just a slight variation.

**Step 7 — Build shortlist**
Top 5–8 for gallery/tour sequence use. These feed the MLS and Instagram carousel.

**Step 8 — Output the report**

---

## Output Format

Always produce output in this exact structure:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
HERO IMAGE SELECTION REPORT
Property: [Name or "Untitled"]
Images reviewed: [count]
Date: [today]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

HERO (Primary — Horizontal)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Image: [filename or number]
Score: XX/60
Breakdown: Architecture X | Light X | Composition X | Resonance X | Brand X | Technical X
Why it's the hero:
[2–4 sentences in WCM voice — light, materiality, mood, composition, story hook]
Use for: Website hero, Email header, MLS image 1, Instagram feed (cropped), Feature Story

HERO VERTICAL ALTERNATIVE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Image: [filename or number]
Score: XX/60
Notes: [One sentence on what makes this the best vertical option]
Use for: Instagram Stories, Email verticals, Instagram carousel cover

HERO 2 (Backup / Second Lead)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Image: [filename or number]
Score: XX/60
Notes: [One sentence — what angle or moment this offers that's different from Hero 1]
Use for: Second email campaign, Instagram second post, A/B test option

SHORTLIST (Gallery & Tour Sequence)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. [filename] — XX/60 — [one-line reason + suggested sequence position]
2. [filename] — XX/60 — [one-line reason + suggested sequence position]
3. [filename] — XX/60 — [one-line reason + suggested sequence position]
4. [filename] — XX/60 — [one-line reason + suggested sequence position]
5. [filename] — XX/60 — [one-line reason + suggested sequence position]

SUGGESTED TOUR SEQUENCE (MLS / Website)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[Ordered list following WCM sequence: Setting → Arrival → Entry → Great Room → Dining → Kitchen → ...]
e.g.
1. [filename] — Setting / establishing exterior
2. [filename] — Sense of arrival / street appeal
3. [filename] — Entry / threshold
...

CUTS — Do Not Use for Hero or Gallery
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[filename] — [one-line reason — be specific]
[filename] — [one-line reason]
...

FLAGS / NOTES FOR TRENT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[Any edge cases, close calls, or questions that warrant Trent's eye]
```

---

## Edge Cases

| Situation | How to handle |
|---|---|
| **No exterior shots** | Flag loudly. Ask if exteriors exist. If not, select best interior with full caveat. |
| **Drone vs ground level** | Drone works for site context (ocean, acreage, landscape). Ground works for architectural detail. Choose by which shows the hook better. |
| **Dusk / night shots** | Can hero if mood is exceptional. Flag that these may perform differently in email (dark thumbails). |
| **Multiple structures / complex sites** | Pick the image that best represents the *experience* of owning this property. |
| **No clear winner (two images tied)** | Say so explicitly. Present both as a toss-up and explain what each prioritizes. Let Trent decide. |
| **Property has a story hook** | Prioritize showing the hook in the hero. Note if no images capture it. |
| **Vertical-only set** | Select best vertical, flag the format gap, suggest it may need a crop to horizontal for web. |

---

## Taste Calibration (Paste Before Running)

For highest accuracy, paste Trent's completed `TASTE_REFERENCE_TEMPLATE.md` before uploading photos.

```
TASTE REFERENCE — [Property Name]
Hero selected: [description]
Why it worked: [Trent's words]
What was passed over: [brief note]
```

10 examples = well-calibrated. Even 3–4 helps significantly.
Without examples, defaults to the WCM Taste Profile above.

---

## Delivery Formats Served by This Skill

| Deliverable | Images needed | Hero role |
|---|---|---|
| Website listing page | 1 horizontal hero | Primary |
| MLS | Up to 40, hero first | Image 1 |
| Email 1 (House Release) | 6 verticals | First vertical |
| Email 2 (Tour Announcement) | 5 verticals + 1 horizontal | Horizontal header |
| Instagram Release Post | 10 verticals (carousel) | Cover image |
| Instagram Feed | 3-post grid plan | Lead post |
| Feature Story | 1 horizontal master | Full bleed cover |
