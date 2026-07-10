ASCII art for a CLI  
  
  
You are an expert CLI (Command Line Interface) developer and UX/UI designer specializing in terminal aesthetics. I want to upgrade my existing CLI tool to make it look professional, modern, and engaging by adding ASCII art banners and colorized terminal output.  
  
Here are the details of my project:  
- Language/Runtime: [e.g., Python 3.11, Node.js, Go, Bash]  
- Current primary libraries used (if any): [e.g., Click, Inquirer, Commander.js]  
- Core functionality of the CLI: [Briefly describe what your CLI does, e.g., a local file organizer, a git helper, a crypto ticker]  
- Preferred color scheme/vibe: [e.g., Cyberpunk (Neon pink/cyan), Matrix (Green/Black), Minimalist Corporate (Blue/Gray/White)]  
  
Please provide a refactored version of my CLI entry point (or a robust boilerplate example) that implements the following enhancements:  
  
1. ASCII Art Splash Screen:  
- Generate or include a clean ASCII art banner for the app name: "[Your App Name]"  
- Display this banner when the tool starts, along with a subtle version number and description.  
  
2. Visual Hierarchy & Colorization:  
- Use standard terminal styling libraries appropriate for my language (e.g., Rich/Colorama for Python, Chalk/Ora for Node, etc.) or standard ANSI escape codes.  
- Implement clear color-coding for different log levels: Success (Green), Info (Blue/Cyan), Warnings (Yellow), and Errors (Red).  
- Format sections using dividers (e.g., lines of hyphens or blocks) to prevent walls of text.  
  
3. Interactive/Dynamic Elements (Optional but preferred):  
- Include examples of styled loading spinners, progress bars, or stylized interactive menus if applicable to my language stack.  
  
4. Code Quality:  
- Keep the styling logic modular (e.g., a helper utility or separate UI functions) so it doesn't clutter the core business logic.  
- Ensure the colors degrade gracefully if the user's terminal doesn't support true color (fallback to basic ANSI).