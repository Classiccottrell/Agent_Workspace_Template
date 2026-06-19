# DESIGN-ENGINEERING SKILL PROFILE
# Consolidated UI/UX skill extensions
# Root Orchestrator passes this profile to all active programming sub-agents

---

## BASELINE & STRUCTURE (baseline-ui · ui-skills-root)

- Start every component from semantic HTML — layout is structure, not decoration.
- Establish a spacing scale before writing any component (4pt or 8pt grid).
- Default to `flex` for one-axis layout, `grid` for two-axis layout.
- Avoid arbitrary pixel values; bind all sizing to the design token scale.
- Keep component files single-responsibility: one component, one file.

---

## ACCESSIBILITY (fixing-accessibility · wcag-audit-patterns)

- All interactive elements must be keyboard-reachable and announce via ARIA roles.
- Color contrast ratio: 4.5:1 minimum for body text, 3:1 for large text (WCAG AA).
- Never rely on color alone to convey state — pair with label, icon, or pattern.
- `<button>` for actions, `<a>` for navigation — never swap without ARIA override.
- Focus ring must always be visible; never `outline: none` without a custom replacement.
- Run axe-core or Lighthouse accessibility audit before every production deploy.
- Alt text: descriptive for informational images, empty (`alt=""`) for decorative.
- WCAG audit checklist: perceivable · operable · understandable · robust (POUR).

---

## MOTION & PERFORMANCE (fixing-motion-performance · 12-principles-of-animation)

**12 Animation Principles Applied to UI:**
1. Squash & stretch → subtle scale on press (0.97) for tactile feel.
2. Anticipation → brief delay before major state transitions.
3. Staging → animate one element at a time; avoid simultaneous noise.
4. Straight-ahead / pose-to-pose → use keyframes for complex, springs for simple.
5. Follow-through → `spring` easing over `ease-out` for natural deceleration.
6. Slow in/slow out → always ease, never linear (except loaders).
7. Arcs → translate along natural curves, not straight XY paths.
8. Secondary action → micro-interactions reinforce primary without competing.
9. Timing → 150–300ms for UI feedback; 300–600ms for layout transitions.
10. Exaggeration → reserved for onboarding, empty states, celebrations.
11. Solid drawing → motion must reinforce spatial relationships.
12. Appeal → motion should feel alive but not distracting.

**Performance:**
- `transform` and `opacity` only — never animate `width`, `height`, `top`, `left`.
- Use `will-change` sparingly; remove after animation completes.
- Respect `prefers-reduced-motion` — gate all decorative motion behind this media query.
- Target 60fps; budget < 10ms per frame for JS execution.
- Framer Motion: use `layout` prop for FLIP animations, `AnimatePresence` for exit.

---

## COMPONENT ARCHITECTURE (shadcn · react-doctor · frontend-design)

- Compound component pattern: `<Select>`, `<Select.Trigger>`, `<Select.Content>`.
- Controlled vs. uncontrolled: expose both via `value`/`defaultValue` pattern.
- Props API design: semantic names over implementation names (`onSelect` not `onClick`).
- Avoid prop drilling > 2 levels — use Context or composition.
- React Doctor rules:
  - No inline object/array creation in JSX (defeats memoization).
  - `useMemo` / `useCallback` only when profiler confirms re-render cost.
  - Virtualize lists > 50 items (TanStack Virtual or react-window).
  - Colocate state as low as possible; lift only when sibling sharing is required.
- Server components default; client boundary (`"use client"`) only at interaction leaf.

---

## INTERFACE FEEL (make-interfaces-feel-better · emil-design-eng · impeccable)

- Every interactive element needs 3 states: default · hover · active (pressed).
- Hover: subtle background or color shift (opacity 0.06–0.1 overlay).
- Active: `scale(0.97)` + 50ms spring. Communicates physicality.
- Loading: skeleton screens over spinners for content-shaped placeholders.
- Empty states: illustrative, actionable. Never a blank void.
- Error states: specific, not generic ("Invalid email" not "Error").
- Transitions between routes: 150ms fade or slide — no jarring cuts.
- Thumb-friendly tap targets: minimum 44×44px on mobile.
- Perceived performance > actual performance. Optimistic UI always.

---

## COLOR — OKLCH (oklch-skill)

- Use OKLCH for all color definitions: `oklch(L C H / alpha)`.
- OKLCH is perceptually uniform — lightness L=0.5 looks equally bright across hues.
- Derive palette: pick hue (H), fix chroma (C 0.12–0.18 for UI), sweep lightness.
- Dark mode: rotate lightness scale — do not just invert hex values.
- CSS custom properties for all color tokens:
  ```css
  --color-primary: oklch(0.55 0.18 264);
  --color-primary-hover: oklch(0.50 0.18 264);
  ```
- Test color pairs with APCA contrast (preferred over WCAG for perceptual accuracy).

---

## CLARITY & COMMUNICATION (clarify · audit · design-lab)

- One primary action per screen. One. Hierarchy enforces priority.
- Labels: verb + noun. "Save draft" not "Save". "Delete project" not "Delete".
- Tooltips for icon-only controls — always. No exceptions.
- Information density: scannable first, detailed on expand/hover.
- Whitespace is not wasted space — it is the primary contrast mechanism.
- Audit checklist before shipping:
  - [ ] Does every screen have a clear primary action?
  - [ ] Is the visual hierarchy legible in 5 seconds?
  - [ ] Are all states (loading, empty, error, success) handled?
  - [ ] Does it pass WCAG AA?
  - [ ] Does it work at 320px viewport width?

---

## BRUTALIST & TASTE CALIBRATION (brutalist-skill · gpt-taste · bencium-innovative-ux-designer)

- Brutalist approach: expose structure, not decoration. Function dictates form.
- Raw typography, monospace, high contrast — use intentionally, not by accident.
- Taste calibration: before shipping, ask "would this embarrass a senior designer?"
- Reference quality: best-in-class product UIs set the taste floor.
- Innovation: novel interaction patterns only when they reduce friction. Never novelty for novelty.
- Avoid: gradients on gradients, shadows on shadows, border-radius > 16px on cards.

---

## UX PRINCIPLES (ui-ux-pro-max · interface-design · frontend-slides)

- Hick's Law: more choices = more time. Limit options per decision point.
- Fitts's Law: make frequent actions large and close to the user's current focus.
- Jakob's Law: users spend most time on other sites. Match common patterns.
- Progressive disclosure: show defaults, reveal complexity on demand.
- Feedback loops: every action must have a visible, timely response.
- Don't make users think: navigation, affordances, and labels must be self-evident.
- Mobile-first: design at 390px, enhance upward. Never retrofit down.
- Undo > confirmation dialogs. Preference: let users undo over blocking them.

---

## SUB-AGENT INSTRUCTION BLOCK
When this skill profile is passed to a programming sub-agent, enforce:
1. All color tokens in OKLCH.
2. All animations respect `prefers-reduced-motion`.
3. All interactive elements have 3 visual states.
4. No `outline: none` without replacement focus ring.
5. Semantic HTML before any ARIA override.
6. Component props follow verb+noun convention.
7. List virtualization at > 50 items.
8. Single primary action per view/screen.
