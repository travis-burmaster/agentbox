# claude-law-firm

A Claude-native legal AI agent for boutique and solo law firms. Handles contract review with severity ratings, tracked-changes editing at the Word XML level, contract drafting, client communications, legal research with anti-hallucination verification, and policy writing. Built to give small firms the throughput of a much larger practice.

## Run

```bash
npx @open-gitagent/gitagent run -r https://github.com/shreyas-lyzr/claude-law-firm
```

## What It Can Do

- **Contract Review** — Multi-mode review with severity ratings, missing-provisions checklist, market-term benchmarking, and cross-reference analysis
- **Tracked Changes** — Apply real tracked changes to .docx files at the XML level, attributed to your name, without opening Word
- **Contract Drafting** — Generate complete agreements from term sheets or deal points, calibrated to deal size and context
- **Client Communications** — Draft emails, memos, and updates that match tone to the client relationship
- **Legal Research** — Structured research with parallel multi-angle analysis and mandatory anti-hallucination self-verification
- **Policy Writing** — Corporate policies and compliance documents calibrated to company stage and regulatory requirements

## Structure

```
claude-law-firm/
├── agent.yaml
├── SOUL.md
├── RULES.md
├── README.md
├── skills/
│   ├── contract-review/
│   │   └── SKILL.md
│   ├── tracked-changes/
│   │   └── SKILL.md
│   ├── contract-drafting/
│   │   └── SKILL.md
│   ├── client-communications/
│   │   └── SKILL.md
│   ├── legal-research/
│   │   └── SKILL.md
│   └── policy-writing/
│       └── SKILL.md
└── knowledge/
    ├── index.yaml
    ├── privilege-framework.md
    └── engagement-letter-ai-provision.md
```

## Built with

[gitagent](https://github.com/open-gitagent/gitagent) — a git-native, framework-agnostic open standard for AI agents.
