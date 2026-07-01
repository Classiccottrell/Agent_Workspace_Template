# How This Repo Works

This project is a personal assistant system built from AI "agents" that each have one job. You make a request, a central Orchestrator figures out who should handle it, and that specialist works only inside its own folder before reporting back. Think of it like a small office: one manager, five specialists, three filing cabinets.

```mermaid
graph TD
    U[You make a request] --> O[Orchestrator<br/>reads the request, picks a specialist]

    O --> ARCH[Architect<br/>designs structure and plans]
    O --> CODE[Coder<br/>builds and implements]
    O --> ENG[Eng Manager<br/>runs active projects]
    O --> ARCHIVE[Archivist<br/>files finished work]
    O --> CUR[Curator<br/>keeps the knowledge base]

    ENG --> PROJ[(Projects folder)]
    ARCHIVE --> FINAL[(Final Products folder)]
    CUR --> VAULT[(Vault Brain knowledge base)]

    PROJ --> DONE[Work reported back]
    FINAL --> DONE
    VAULT --> DONE
    ARCH --> DONE
    CODE --> DONE

    DONE --> O
    O --> RESULT[You get the result]
```

To view this diagram: it renders automatically when this file is viewed on GitHub, or paste the code block above into https://mermaid.live.
