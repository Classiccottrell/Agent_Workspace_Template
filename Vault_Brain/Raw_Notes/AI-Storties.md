# Product Requirement Document (PRD): The Web Connector AI Stories

## Executive Summary & Objectives
The Web Connector is a new piece of functionality within the AppNeta product that enables users to connect external services (such as Slack, ServiceNow, and Email) to receive AppNeta Alarms. This document captures the underlying design workflows, AI-assisted development processes, and user-facing AI capabilities developed during the project lifecycle.

---

## User Stories / Target Use Cases

| Story ID | As a... | I want to... | So that... |
| :--- | :--- | :--- | :--- |
| US-01 | Product Designer | Collaborate with the PM using functional Cursor prototypes aligned to Figma layouts | We can accelerate design decision-making, catch interaction gaps, and reduce blind spots in requirements. |
| US-02 | Product Designer | Use the Mineral Writing Editor gem to rephrase late-stage copy suggestions | The copy aligns with Mineral guidelines and is stakeholder-ready without delaying presentations. |
| US-03 | Product User | Leverage AI to generate a WebHook Handlebars template | I can quickly connect external services without writing complex template code from scratch. |
| US-04 | Product Designer | Generate live Git-style "Diff" interaction examples in Gemini Canvas | I can align with Product and Engineering on complex UI behaviors without designing every microscopic complexity in Figma. |

---

## Functional Requirements

### 1. Prototyping & Collaboration Loop
- **Rapid Onboarding:** Utilize working code prototypes (built via Cursor and existing APIs) as baseline references to grasp core project concepts quickly.
- **Bi-Directional Design Sync:** 
  - PM updates the live Cursor prototype based on new Figma layouts and design choices.
  - Design reviews the live build to identify interaction gaps before final requirement writing.

### 2. Copy & Compliance Management
- **Late-Stage Copy Refinement:** Integrate with the **Mineral Writing Editor 0.3 Gem** to review, rephrase, and polish ad-hoc copy suggestions.
- **Brand & Style Alignment:** Ensure all user-facing copy meets corporate compliance guidelines before stakeholder presentations, serving as a bridge to final Technical Writer reviews.
- **Resource Ecosystem:** Provide access to the broader UX toolset, including Tomas's *UX Brief Generator*.

### 3. User-Facing AI Template Generation
- **Handlebars Template Creator:** Embed an intuitive AI interface guiding users to generate WebHook Handlebars templates.
- **Gemini Canvas Ideation:** Use canvas-driven visual walkthroughs to evaluate multiple implementation structures and minimize production time.

### 4. Code Editor & Comparative Diff Interface
- **Git-Style Diff Interface:** Provide a comparative "Diff" view when users leverage AI to generate or modify code inside the body input of the connector form.
- **Interactive Hand-off:** Utilize live interaction canvases as functional reference artifacts for Engineering implementation and final UX requirement verification.

---

## Success Metrics & KPIs
- **Time to Delivery:** Significant reduction in design production hours for complex components (e.g., Diff interfaces) via generative canvas tools.
- **Alignment Velocity:** Elimination of layout blind spots prior to stakeholder presentations through parallel prototype-to-mock reviews.
- **Copy Compliance:** 100% of presentation-level product text compliant with Mineral writing guidelines.

---

## Appendix: Links & Resources
- **Mineral Writing Editor 0.3 Gem:** [Access Link](https://gemini.google.com/gem/1Tya5ARtGK0ssiplWG-Ba4HHxvjhDAvDN?usp=drive_link)
- **Shared Resource Directory:** AOD UX | Gem Directory
- **Live Visual Concepts:** AI Code Editor Concepts
- **Live Interaction Archetype:** GitStyle Diff