

Use this as the main index file (polira_dual_app_workspace.html) 

Organize and reconcile discrepancies. 


Build out the site keeping the design system page but do the following pages under the AI Dashboard


Layout & Navigation
Main Shell: Create a two-column layout with a fixed left sidebar and a flexible main content area.

Sidebar:

New Chat: A prominent Button at the top to start a new session.

Chat History: A scrollable list of recent conversations. Each item should have a hover state and an active state.

User Profile: At the bottom of the sidebar, include a DropdownMenu for account access and logout.

2. Main Chat Interface
Message Feed: A scrollable central area.

User Messages: Right-aligned with a distinct background color.

AI Messages: Left-aligned with a muted background.

Input Area: A fixed-bottom input bar that includes:

A Textarea that auto-expands as the user types.

Icons for file attachments and a "Send" action.

3. Admin & Settings (Modal)
Implement a shadcn Dialog triggered from the Sidebar's user menu.

Use Tabs inside the dialog to organize:

Account: Form fields for user information.

Configuration: A Select component for AI Model Selection and toggle switches for app settings.

Plan & Billing: Display the current plan and a "Cancelation" or "Upgrade" action.

