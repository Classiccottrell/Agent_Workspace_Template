I hear you made the Rally CLI I got form Mark L, Nice work. 

I have put it into my Agentic workflow and also given the CLI a face lift with my UX skills. I was hoping to also extend the CLI to attach PRs in the Rally connection fields, but to do this I would need access to the source code and not the "GO" translation, any how heres the wrapper I put around the CLI to make the changes. Also inclued a link to my agentic workflow template. 

https://github.gwd.broadcom.net/dockcpdev/RALLY_CLI
https://github.gwd.broadcom.net/dockcpdev/Agent_Workspace_Template_0.1


------------------------------------------------------------------------------------------



Got it working thank you! once I have this workspace touched and sufficiently white labeled. I will share the internal repo, and give it a spin. @Adam Keller  any luck with the mineral theme?
You, Yesterday 12:55 PM
Hey wanted to thank you guys again for hooking me up with the Rally CLI

I have taken it a littler further and added some niceties like a title in ASCII, Also been working on the connector function a little bit as I want to tie rally to specific PRs, still a WIP. 

Any how I have hosted it all on github, not sure it you guys already has a repo but thought I would pass along my minor improvements. I have also created my self a Rally_Agent.md just let me know if you want that. 

https://github.gwd.broadcom.net/dockcpdev/RALLY_CLI
You, Yesterday 2:53 PM
I am now understanding I have only created a cosmetic and interception layer in front of what you guys created in "GO". so, guessing to get my request to get Connectors working on the CLI should be directed at you and not the claude 😆



------------------------------------------------------------------------------------------

Morning Idan, 

I think you might need to give the product copy a hard look and make sure its, presentation ready and human understandable.  

In, review I found I was not able to speak to things like, what each form field means and what would be in the info icons on each input. Specifically what sizes actually means in compute terms.  These points might need a little product explorations and additional supporting copy.
 
As I look at the workflow video again, how did you want me to use this in the prototype?  

When I watched the demo video I can see a few more screens that are not included in my simple prototype. How are we considering presenting this at the trade show?


------------------------------------------------------------------------------------------


I hear you made the Rally CLI I got form Mark L, Nice work. 

I have put it into my Agentic workflow and also given the CLI a face lift with my UX skills. I was hoping to also extend the CLI to attach PRs in the Rally connection fields, but to do this I would need access to the source code and not the "GO" translation, any how heres the wrapper I put around the CLI to make the changes. Also inclued a link to my agentic workflow template. 



------------------------------------------------------------------------------------------



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




