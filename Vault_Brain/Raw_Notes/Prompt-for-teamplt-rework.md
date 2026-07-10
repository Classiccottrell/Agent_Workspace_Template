

I want to take a critical look at this Agentic workflow templat.

my goal is to release a Directory set-up, workflow or "harness" if that's the right term im not sure. The point is that anyone will be able to easily install this and be up and running with a truly agentic workflow with no need to contuinialy copy agents, skills, automation, MCP or CLIs folder to folder or living some where at the user root of your computer. 

Stricly designed for Mac it can also easily be adjusted to windows, you can also set it up to work with Gemin or Claude.n Out of the box it comes with a roser of agents, a 2nd brain that automaticly indests web clipings, struchered or raw notes. 


I want you to: 
- give me critical impromvents to future proff this teamplte and make the note injestion configurable during the set up prosses.
- wargame out where this system might faile and make detailed plans on how to fix eatch issue found and step by step prompts I can feed to lesser modals.
- Find all the low hanging issues and fix them imidiatly.

Create a solid plan to wokr these into the Agentic workflow templat.
- I wan to add into the system the Github CLI - https://cli.github.com/, the point being that the user wont have to spend tokens having claude push and pulling commiting and sutch.
- I want to add into the system the Playwite CLI - https://playwright.dev/agent-cli/introduction , the point being that the system has the ability to create tests and lint and vet code.
 


Final step after all improvments are done. 


1 - Create a new Claude Skill: "/How-I-write"

- look back on all the conversations and writing I have done a create a skill.md that represents me and my writing styel. 

My voice: [Direct, outcome-focused. Personal without being precious. You lead with specifics—names frameworks, links real examples from your work, flags assumptions for Claude to verify before publishing.
No filler. No em dashes. First-person when it earns its place. You write like you think: "Here's the problem, here's why it matters, here's the move."
You respect terminology you've built (Systematic Clarity, Vault Brain, Terry Larry Berry) and expect Claude to use it—not swap it for generic language.
You structure asks precisely. Deliverable lists, not open-ended "help me think through." You want guided choices before execution, not options after.
Leverage-first mentality. Every sentence pulls its weight. Impatient with repetition or restating.
Your published writing (Substack piece on tape guns) shows the pattern: concrete observation → abstraction → application. No clichés. Insightful without sounding like an AI.]

Banned words:

Delve, unlock, harness, empower, elevate
Synergy, paradigm shift, ecosystem, holistic
Seamless, intuitive, elegant (lazy design descriptors)
Journey, narrative arc, storytelling (unless you're the one using them deliberately)
Explore, navigate (vague)
Cutting-edge, bleeding-edge, innovative, transformation
Dynamic, fluid, robust (placeholder adjectives)
Strategic/strategically (overused)
Leverage (you own this in your frameworks; generic use is banned)

Flagged (use sparingly):

"Approach" — fine if specific; vague if solo
"Consider" — passive; prefer "flag" or name the action
"Potentially," "possibly," "arguably" — hedge your bets or commit


My writing samples: 

Sample 1 ------------------------------------------------------------------------------------------


So when I was 20 and I’ve been out of school for a year I worked nine months as a carpenter assistant doing renovations demolishing and repairing one house by the end of it I was fired like go through a conversation that consisted of you just not cut out for this.

Multimedia has been in my blood drawing Photoshop film we’re all inspiration

To follow that passion I decided to spend $22,000 I didn’t have to go to Vancouver film school. To learn how to make a film.

With aspirations of making films like David Lynch and Sam rainy I went into that one year program. And  For a one year I learned 3-D, Photoshop, illustrator, finalcut, after effects, in design flash and basic portfolio management.

These concepts were not new to me and had previously been outlined in my high school art classes.

Striving for success I became the class representative and hosted the class show at the end of the year. This dismal site lacked for people who dropped out poor portfolios week films and overall no next steps as artists.

The largest lesson I learned was you just Gotta do it I found a job doing background acting and what I thought was going to be a successful film career

Sample 2 ----------------------------------------------------------------------------------------

Father lead me through this next 24 hours, let me seek you in every moment and situation I find my self in. Give me the grace for today.

This morning Asher gave me BBQ rub to put on steaks, last night me and Emily learned crib and I'm feeling exited to do some yard work and spend time with my boys.

#### Entry: hard day

We are currently staying and Doug and Gayle's the in-laws

- Fought with Emily on the way in this morning the conversation went from talking about the house to future plans to talk about how I felt about people drinking in Chelan. And if I needed people not to drink.
- When I got home, dinner was already made, we ate dinner. And I was

**Reflection**

My drinking, smoking and weed use was not to seek pleasure.

- it was my way of keeping some level of control of myself as I felt I was being controlled.
- It was where I thought my creativity and edge came from.

Sample 3 ----------------------------------------------------------------------------------------

Here are  three main ideas behind UX Brutalism.

1. Raw Functionality Over Aesthetic Perfection

UX Brutalism strips away unnecessary decoration and embraces a raw, direct approach to design. It prioritizes usability and efficiency, often resulting in interfaces that may appear harsh or unpolished but function exceptionally well.

2. Honest, Transparent Interactions

Instead of hiding complexity behind unnecessary layers of design, UX Brutalism presents things as they are. Users should immediately understand what an interface does without excessive onboarding, animations, or misleading affordances.

3. Minimalism Without Compromise

Unlike traditional minimalism, which often aims for elegance, UX Brutalism embraces starkness and contrast, ensuring that users can navigate interfaces quickly with clear, unambiguous visual hierarchy.


Sample 3 ----------------------------------------------------------------------------------------

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

Sample 4 ----------------------------------------------------------------------------------------


I hear you made the Rally CLI I got form Mark L, Nice work. 

I have put it into my Agentic workflow and also given the CLI a face lift with my UX skills. I was hoping to also extend the CLI to attach PRs in the Rally connection fields, but to do this I would need access to the source code and not the "GO" translation, any how heres the wrapper I put around the CLI to make the changes. Also inclued a link to my agentic workflow template. 

https://github.gwd.broadcom.net/dockcpdev/RALLY_CLI
https://github.gwd.broadcom.net/dockcpdev/Agent_Workspace_Template_0.1


Sample 5 ----------------------------------------------------------------------------------------


Got it working thank you! once I have this workspace touched and sufficiently white labeled. I will share the internal repo, and give it a spin. @Adam Keller  any luck with the mineral theme?
You, Yesterday 12:55 PM
Hey wanted to thank you guys again for hooking me up with the Rally CLI

I have taken it a littler further and added some niceties like a title in ASCII, Also been working on the connector function a little bit as I want to tie rally to specific PRs, still a WIP. 

Any how I have hosted it all on github, not sure it you guys already has a repo but thought I would pass along my minor improvements. I have also created my self a Rally_Agent.md just let me know if you want that. 

https://github.gwd.broadcom.net/dockcpdev/RALLY_CLI
You, Yesterday 2:53 PM
I am now understanding I have only created a cosmetic and interception layer in front of what you guys created in "GO". so, guessing to get my request to get Connectors working on the CLI should be directed at you and not the claude 😆



Sample 6 ----------------------------------------------------------------------------------------


Morning Idan, 

I think you might need to give the product copy a hard look and make sure its, presentation ready and human understandable.  

In, review I found I was not able to speak to things like, what each form field means and what would be in the info icons on each input. Specifically what sizes actually means in compute terms.  These points might need a little product explorations and additional supporting copy.
 
As I look at the workflow video again, how did you want me to use this in the prototype?  

When I watched the demo video I can see a few more screens that are not included in my simple prototype. How are we considering presenting this at the trade show?


Sample 7 ----------------------------------------------------------------------------------------

I hear you made the Rally CLI I got form Mark L, Nice work. 

I have put it into my Agentic workflow and also given the CLI a face lift with my UX skills. I was hoping to also extend the CLI to attach PRs in the Rally connection fields, but to do this I would need access to the source code and not the "GO" translation, any how heres the wrapper I put around the CLI to make the changes. Also inclued a link to my agentic workflow template. 



Sample 8 ----------------------------------------------------------------------------------------


1.0 VPAT Processes 
The VPAT is a document that corresponds to a product release. This document is used by sales and customers. Typically a customer will ask for this document so they can understand our level of compliance for their employees who will be using the software. The other typical use is sales will need to show we have this document when closing a deal.

VPAT Drive Location: 
NetOps and AppNeta VPAT folder - NetOps


Guidelines
The CSE team generates a VPAT every 6 months, aimed for a summer or winter release.
The VPAT covers released functionality and specific use cases.
Things in EA (early access) are excluded.
The review is performed by the CSE team lead by ( Naveen Gandamalla )
High level Process
A Product release is chosen that's 6 months from the last tested release. (Typically a Summer or Winter release)
The chosen product release is deployed to a testable environment during the QA phase of the release cycle. 
In AppNeta we use SRE’s environment ( https://app-endurance.pm-st.appneta.com/)
NetOps: http://smoke-suse-long-portal1.netops.broadcom.net:8181/pc/desktop/page?GroupPathIDs=1&GroupID=1
Communication and Scheduling with the CSE team.
Update CSE team on any new or significant changes to the Use case workflows that will be tested.
Give Naveen's team time to allocate resources for testing.
The CSE team performs a scan and produces a VPAT, along with a list of accessibility defects or bugs.
CSE Team logs bugs in a google sheet and confluence tickets for the product (shared with UX team).

Rally - Tracking process. 
Theme is “WCAG and Accessibility Compliance” Managed by Beaulah Vineela Pasupulati
Initiative is created that could span multiple PI’s
UX creates a feature under the initiative for PI work.
UX Created Stories for work performed during the PI.



2.0 Road to Compliance
Priority for resolving accessibility issues are determined based on the following criteria and process. 

Expectation
There can be customer driven changes that are ask for and can take priority over general issues that

Guidelines
UX Defines the Issues that will get done. The bugs are prioritized based on their relevance and the product direction.
Defects identified as relevant are vetted by PM and Eng management need to be given space in PI planning. (Create Rally tickets)
High level Process
This process spans the entire production pipeline, design, development, QA and released product.
UX team members review and rank the accessibility bugs based on severity, customer priority and product relevance. + Product Stakeholders. 
UX defines the bugs to work on.
Relative issues become defect work that can be scheduled to be done by PI.
Get in front of PM and Eng teams to define a timeline for the fixes.
Provide requirements guidance to QA/ Eng teams as they execute the tickets.
Report fixes / decisions made to the CSE team for the next review / Update the VPAT.
Areas of deprecated support need to be identified and communicated.

Outstanding Items / Conversations
How much bandwidth can we get for a PI to take action on compliance issues? 
Who do we need to meet with?
UX to develop a process for Eng management to pick up tickets. ← do something like we are doing for Atmosphere UX enhancements.
TBD: Write out what I think the process is.
What's the publicly hosted URL for customers?


End of Samples 


Rule: Use this on all content I ask you to write unless I say otherwise.



2 - Create a new page on Classiccottrell.ca (classiccottrell.github.io) i want to highlight this work, it should outline what this project is what it dose and the UX thinking behind it. get me to a good starting point and I can tweak the content but I want you to use the new How-I-write skill, that you will be creating. Also make sure the site follows the design system outlined in (ClassicCottrell_design-system)






