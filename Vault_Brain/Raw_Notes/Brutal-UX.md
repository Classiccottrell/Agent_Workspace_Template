
Brutal UX Project Execution

Act as a Principal Developer, Product Manager, and Technical Architect. You are executing the "Brutal UX" (UX Brutalism) project. This design philosophy ignores traditional psychology principles and embraces raw economic principles (efficiency, utility, scarcity).

Execute the following three phases sequentially.


Phase 1: Repository Setup & Design System Foundation
Create a new repository for this project. Initialize the environment and establish the mathematical constraints of the Brutal UX design system.

Core Constraints:

Typography: System fonts only (monospace, system-ui, or Arial). No custom web fonts.

Palette: Pure binary contrast. #000000 (Black), #FFFFFF (White), and high-visibility utility colors only for active states.

Borders: Heavy, un-aliased lines. 2px solid #000000 for everything. border-radius: 0.

Layout: Strict, rigid grids determined by content, not aesthetic whitespace.

Initialization Commands:
Execute the following to set up the base UI components:
npx shadcn@latest init --preset b1oVxvbG --template next --pointer

Global CSS Variables:
Apply these exact variables to the global stylesheet to enforce the stark, high-contrast theme:

CSS
:root {
  --background: oklch(1 0 0);
  --foreground: oklch(0.145 0 0);
  --card: oklch(1 0 0);
  --card-foreground: oklch(0.145 0 0);
  --popover: oklch(1 0 0);
  --popover-foreground: oklch(0.145 0 0);
  --primary: oklch(0.205 0 0);
  --primary-foreground: oklch(0.985 0 0);
  --secondary: oklch(0.97 0 0);
  --secondary-foreground: oklch(0.205 0 0);
  --muted: oklch(0.97 0 0);
  --muted-foreground: oklch(0.556 0 0);
  --accent: oklch(0.97 0 0);
  --accent-foreground: oklch(0.205 0 0);
  --destructive: oklch(0.577 0.245 27.325);
  --border: oklch(0.922 0 0);
  --input: oklch(0.922 0 0);
  --ring: oklch(0.708 0 0);
  --chart-1: oklch(0.87 0 0);
  --chart-2: oklch(0.556 0 0);
  --chart-3: oklch(0.439 0 0);
  --chart-4: oklch(0.371 0 0);
  --chart-5: oklch(0.269 0 0);
  --radius: 0;
  --sidebar: oklch(0.985 0 0);
  --sidebar-foreground: oklch(0.145 0 0);
  --sidebar-primary: oklch(0.205 0 0);
  --sidebar-primary-foreground: oklch(0.985 0 0);
  --sidebar-accent: oklch(0.97 0 0);
  --sidebar-accent-foreground: oklch(0.205 0 0);
  --sidebar-border: oklch(0.922 0 0);
  --sidebar-ring: oklch(0.708 0 0);
}

.dark {
  --background: oklch(0.145 0 0);
  --foreground: oklch(0.985 0 0);
  --card: oklch(0.205 0 0);
  --card-foreground: oklch(0.985 0 0);
  --popover: oklch(0.205 0 0);
  --popover-foreground: oklch(0.985 0 0);
  --primary: oklch(0.922 0 0);
  --primary-foreground: oklch(0.205 0 0);
  --secondary: oklch(0.269 0 0);
  --secondary-foreground: oklch(0.985 0 0);
  --muted: oklch(0.269 0 0);
  --muted-foreground: oklch(0.708 0 0);
  --accent: oklch(0.269 0 0);
  --accent-foreground: oklch(0.985 0 0);
  --destructive: oklch(0.704 0.191 22.216);
  --border: oklch(1 0 0 / 10%);
  --input: oklch(1 0 0 / 15%);
  --ring: oklch(0.556 0 0);
  --chart-1: oklch(0.87 0 0);
  --chart-2: oklch(0.556 0 0);
  --chart-3: oklch(0.439 0 0);
  --chart-4: oklch(0.371 0 0);
  --chart-5: oklch(0.269 0 0);
  --sidebar: oklch(0.205 0 0);
  --sidebar-foreground: oklch(0.985 0 0);
  --sidebar-primary: oklch(0.488 0.243 264.376);
  --sidebar-primary-foreground: oklch(0.985 0 0);
  --sidebar-accent: oklch(0.269 0 0);
  --sidebar-accent-foreground: oklch(0.985 0 0);
  --sidebar-border: oklch(1 0 0 / 10%);
  --sidebar-ring: oklch(0.556 0 0);
}



Phase 2: Brutal UX Microsite & Component Sandbox
Build a comprehensive single-page component dashboard out of the README concept. It must act as both documentation and an interactive sandbox. Reject traditional UX psychology—no soft shadows, no gradients, no rounded corners, no smooth micro-interactions. Emulate high-contrast wireframes and the slapstick cause-and-effect of David Lynch's "Dumbland."

Structure the page into three distinct sections, divided by thick 3px solid #000 borders:

Design System Manifesto & Tokens: Document the three market lenses of Brutal UX: Zero-Tariff Interfaces (exposing mechanisms immediately), The Scarcity Engine (eliminating non-transactional visual elements), and Slapstick Cause-and-Effect (immediate, unbuffered binary consequences). Display the typography scale and color palette.

Brutal Component Repository: Create interactive cards showcasing raw components. Buttons must be pure rectangles that switch active states instantly (zero ease-in-out). Input fields must be stark white boxes. Include a "TRIGGER SLAPSTICK ACTION" button that instantly triggers an aggressive DOM change with zero animation.

Application Specimen (The "No-Bullsh*t" Ledger): Embed a functional mini-app within the dashboard. Allow users to type a utility task, assign an economic value, and add it to a rigid table. Clicking delete must vanish the item from the DOM instantly.





Phase 3: Ready-for-Market Product Plans
Generate three complete, execution-ready business plans, Product Requirement Documents (PRDs) and sample micro site for the following applications based entirely on the Brutal UX philosophy. Each plan must detail the target market, monetization strategy reflecting raw transparency, core feature loops, and engineering architecture optimized for zero latency.



Product 1: The "No-Bullsh*t" Budget Tracker
A financial app for the F.I.R.E community and anti-consumerists. Zero graphs, zero colorful categories, zero insights. A stark, high-contrast ledger where net liquidity changes instantly upon data entry.

Act as a Principal Product Manager and Technical Architect. Generate a complete, execution-ready business plan, product requirement document (PRD), and technical stack recommendation for a financial web application called "NetZero."

THE CONCEPT:
NetZero is a personal finance app built on the principles of "UX Brutalism." It rejects the psychology-driven design of competitors (like YNAB, Mint, or Monarch). There are no colorful pie charts, no gamification, no "You saved!" animations, and no pastel categories. It is a stark, high-contrast, brutalist ledger. The user inputs an expense or income, and their net liquidity updates instantly with zero latency or transition animations. 

TARGET AUDIENCE: 
The F.I.R.E (Financial Independence, Retire Early) community, freelancers, and anti-consumerists who are tired of financial apps treating them like children. They want extreme data density and absolute reality regarding their cash flow.

REQUIRED OUTPUT SECTIONS:
1. Executive Summary & Value Proposition: Define the exact problem this solves and the psychological hook of "brutal honesty" in finance.
2. Core Feature Loop: Map out the user journey. How do they onboard? (Hint: It should be instant, no tutorials). How does the ledger work?
3. Brutal UX Constraints: Define the strict visual and interaction rules for the frontend engineers (e.g., pure #000 and #FFF, system monospace fonts, immediate DOM updates).
4. Monetization Strategy: Align the pricing with the philosophy. (e.g., No subscription traps. A pure, transparent fee—either a one-time purchase or a raw pass-through cost for bank-sync API calls).
5. Go-To-Market & Marketing Copy: Draft the homepage hero copy. It should sound stark, aggressive, and highly compelling.
6. Technical Architecture: Recommend a stack optimized for instant state changes and high-speed ledger calculations (e.g., React with a local-first architecture like SQLite/RxDB).



Product 2: Incident Command Dashboard
A B2B SaaS tool for DevOps and SREs. Beautiful UI is a liability during server outages. Design this with raw wireframe boxes, flashing absolute-red alerts, terminal-green data streams, and immediate single-click terminal triggers with no "Are you sure?" modals.

Act as a Principal Product Manager and Technical Architect. Generate a complete, execution-ready business plan, PRD, and technical stack recommendation for a B2B SaaS tool called "Terminal Red."

THE CONCEPT:
Terminal Red is an incident command and server monitoring dashboard for DevOps and SRE (Site Reliability Engineering) teams, built strictly on "UX Brutalism." When a server goes down, cognitive load peaks. Beautiful UI gradients and smooth transitions are dangerous liabilities. This dashboard is pure, un-aliased reality. It uses stark wireframe boxes, terminal-green data streams, and absolute-red flashing alerts. Interactions rely on "slapstick cause-and-effect"—if you hit the "Kill Node" button, the server is severed instantly. No "Are you sure?" modal, no loading spinners.

TARGET AUDIENCE:
DevOps engineers, SREs, Tier 3 IT support, and emergency dispatch teams who require high-density data, zero friction, and absolute transparency during crisis management.

REQUIRED OUTPUT SECTIONS:
1. Executive Summary & Value Proposition: Pitch why "ugly and fast" saves millions of dollars in enterprise downtime compared to "pretty and slow."
2. Core Feature Loop: Detail the Incident Command protocol. What happens when an alert triggers? How are raw logs displayed? How are execution commands triggered?
3. Brutal UX Constraints: Define the visual rules. (e.g., no border-radii, pure high-contrast layouts, raw HTML table structures for log streams, zero animations).
4. B2B Monetization Strategy: Structure an enterprise pricing model based on utility (e.g., per-node monitored, or a raw compute-cost multiplier).
5. Go-To-Market Strategy: Outline a developer-centric acquisition strategy. Where do SREs hang out, and how do we pitch this to CTOs?
6. Technical Architecture: Define a high-throughput, low-latency stack. Focus on WebSockets for real-time data streaming and a brutally lightweight DOM to prevent browser freezing during massive log dumps.



Product 3: A Counter-Culture Publishing Platform
A publishing tool for minimalists and privacy advocates. Strip away formatting bloat, engagement loops, algorithms, and read-time indicators. Writers type raw markdown; readers view high-contrast monospaced text. Optimize purely for the transmission of information.


Act as a Principal Product Manager and Technical Architect. Generate a complete, execution-ready business plan, PRD, and technical stack recommendation for a publishing platform called "StarkText."

THE CONCEPT:
StarkText is a counter-culture blogging and newsletter platform built on "UX Brutalism." Substack and Medium optimize for engagement loops, read times, and algorithms. StarkText optimizes purely for thought and the transmission of information. Writers type in raw markdown. Readers view it in high-contrast monospaced text. There are no likes, no comments, no recommended reading algorithms, and no aesthetic bloat. It is the raw utility of words delivered via HTTP.

TARGET AUDIENCE:
Tech writers, privacy advocates, philosophers, hackers, and minimalist creators who view modern web design as hostile and manipulative.

REQUIRED OUTPUT SECTIONS:
1. Executive Summary & Value Proposition: Define the "Anti-Platform" manifesto. Why is stripping away features a premium selling point?
2. Core Feature Loop: Explain the creation process (Markdown editor, instant compilation) and the reading experience (pure text, RSS feeds by default, no tracking pixels).
3. Brutal UX Constraints: Detail the exact constraints for the UI. (e.g., strict HTML5 semantic tags, no external CSS frameworks, system fonts only, no Javascript required to read an article).
4. Monetization Strategy: How does an anti-capitalist-feeling platform make money? (e.g., completely free to publish, but writers pay a flat $10/year for custom domain mapping; zero platform cut on writer subscriptions).
5. Go-To-Market & Growth: How do you build a network effect without built-in viral social loops? Draft the launch manifesto.
6. Technical Architecture: Recommend a highly scalable, statically generated stack (e.g., Markdown to HTML via a lightweight framework like Astro or Next.js static exports, hosted on edge networks for instant global delivery).


------

Here are 10 web resources, platforms, and manifestos that perfectly embody the principles of Brutal UX—prioritizing raw economic utility, absolute transparency, zero-latency interactions, and stark visual scarcity over modern psychological comforts.



The Manifestos & Galleries
These resources define the philosophy and showcase it in action.

Motherfking Website (motherfuckingwebsite.com)

Why it fits: This is the foundational manifesto of web brutalism. It is a raw HTML page that screams at the user about the perfection of unstyled, zero-bloat web design. It perfectly encapsulates the "Scarcity Engine" concept—if a tag isn't strictly necessary for reading, it doesn't exist.

Brutalist Websites (brutalistwebsites.com)

Why it fits: A curated directory of websites built with a brutalist ethos. While some lean into the artistic "David Lynch" surrealism, many showcase the raw, heavy-bordered, un-aliased typography and slapstick interactivity that define UX Brutalism.

The Best Motherfking Website (bestmotherfuckingwebsite.com)

Why it fits: A slight, begrudging iteration on the first manifesto. It introduces the bare minimum CSS (contrast, line-height, and system fonts) to achieve perfect readability without sacrificing the zero-tariff, instant-load economic principles.

Pure Utility & The "Scarcity Engine"
These platforms operate entirely on data density and function, completely ignoring modern aesthetic trends.

Craigslist

Why it fits: The ultimate example of UX Brutalism succeeding in the free market. It is a pure transactional ledger. Zero gradients, zero micro-interactions, pure HTML links, and immediate cause-and-effect. It is the purest "Zero-Tariff Interface" on the web.

Pinboard (pinboard.in)

Why it fits: Billed as "Social Bookmarking for Introverts," Pinboard is a paid, stark, text-only bookmarking tool. It rejects ad-driven psychology completely. You pay a raw economic fee for raw, unadulterated server utility. It is fast, dense, and utterly unconcerned with looking pretty.

Hacker News (news.ycombinator.com)

Why it fits: A prime example of the "Counter-Culture Publishing Platform." It uses default system fonts, a stark orange utility color, and raw nested text. There are no avatars, no header images, and no engagement algorithms—just the pure utility of words and hyperlinks.

High-Density & Incident Command Interfaces
These examples show how Brutal UX functions in high-stakes or data-heavy environments.

Bloomberg Terminal UI (Reference / Concept)

Why it fits: While not a single website you can casually browse, looking up screenshots of the Bloomberg Terminal perfectly captures the "Incident Command" dashboard. Pure black backgrounds, stark high-contrast utility colors (neon yellow, green, red), and immense data density where every pixel costs money.

Text-Only NPR (text.npr.org)

Why it fits: NPR built a brutalist, text-only version of their news site specifically for emergencies, low-bandwidth areas, and raw reading. It strips away all Javascript, images, and formatting bloat. It is the exact execution of a "No-Bullsh*t" publishing platform.

Zero-Friction Corporate Brutalism
These sites prove that you do not need slick onboarding or psychological coddling to hold immense value.

Berkshire Hathaway (berkshirehathaway.com)

Why it fits: The corporate website of one of the most valuable companies on earth hasn't changed its design since the late 1990s. It is a stark white page with blue hyperlinks. It communicates absolute confidence through visual scarcity. It is honest, transparent, and entirely transactional.

Gov.uk

Why it fits: While highly refined, the UK Government’s design system is a masterclass in stripping away aesthetic fluff for raw utility. It uses heavy black borders, stark high-contrast buttons, system-safe typography, and brutally direct copy. It assumes the user wants to complete a transaction (like paying a tax or renewing a passport) and get out as fast as possible.
