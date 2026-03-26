# Knowledge Base

This directory holds **static reference documentation** that is committed to the workspace repo and available to the agent at all times.

## What Goes Here

- Domain-specific reference material
- API documentation snippets
- Architecture diagrams (as markdown/text)
- Runbooks and SOPs
- Anything the agent needs to consult repeatedly

## What Does NOT Go Here

- Dynamic/changing state → use `memory/runtime/` instead
- Secrets or credentials → use encrypted secrets
- Large binary files → link to external storage

## Structure

Organize by topic:

```
knowledge/
├── README.md              # This file
├── apis/                  # API references
├── architecture/          # System design docs
├── runbooks/              # Operational procedures
└── domain/                # Domain-specific knowledge
```

## Updating

Knowledge files can be committed by the agent or maintained by humans. Since they're in the git repo, they're versioned and auditable.
