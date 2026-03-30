---
name: contract-review
description: >
  Multi-mode contract review with severity ratings, cross-reference analysis,
  missing-provisions checklist, and market-term benchmarking. Supports four modes:
  full review, counterparty markup evaluation, issue-specific deep dive, and quick scan.
license: MIT
allowed-tools: Read Edit Grep Glob Bash
metadata:
  author: claude-law-firm
  version: "1.0.0"
  category: legal
---

# Contract Review Skill

## Trigger
Activate when the user uploads or references a contract, agreement, or legal document and asks for review, analysis, or evaluation.

## Modes

Determine the appropriate mode from context:

### 1. Full Review
Default when the user says "review this contract" without further specifics.

Steps:
1. Identify the document type (SaaS agreement, stock purchase agreement, NDA, services agreement, etc.)
2. Identify which party the user represents
3. Review every substantive provision and produce a severity-rated table:

| # | Provision | Section | Severity | Issue | Recommended Response |
|---|-----------|---------|----------|-------|---------------------|

Severity levels:
- **Critical** — Unacceptable risk; must be changed or deal should not proceed
- **High** — Significant risk shift; strong pushback recommended
- **Medium** — Below market or unfavorable but negotiable
- **Low** — Minor issue; concede if needed for goodwill
- **Informational** — Observation only; no action required

4. Run the **Missing Provisions Checklist** for the document type:
   - Limitation of liability (cap, exclusions, carve-outs)
   - Indemnification (scope, baskets, caps, survival)
   - IP ownership and licensing
   - Data handling and privacy
   - Termination for convenience
   - Force majeure
   - Dispute resolution (forum, governing law, arbitration)
   - Assignment restrictions
   - Confidentiality (if not a standalone NDA)
   - Insurance requirements (if applicable)

5. Run **Market-Term Benchmarking**: flag provisions that deviate significantly from market norms for the deal type and size.

6. Produce a **Cross-Reference Map**: identify where provisions interact, conflict, or create unintended consequences across sections.

### 2. Counterparty Markup Evaluation
When the user has received a redlined or marked-up version back from the other side.

Steps:
1. Map every change the counterparty made
2. Categorize each change by severity
3. Identify patterns in the markup (e.g., systematic risk-shifting, expanded carve-outs)
4. Flag changes that contradict the counterparty's own representations or other provisions
5. For each High or Critical change, provide specific counter-language
6. Recommend which changes to accept, which to counter, and which to reject
7. Offer a clean handoff to the **tracked-changes** skill when the attorney is ready to mark up a response

### 3. Issue-Specific Deep Dive
When the user asks about a specific provision or legal issue within a contract.

Steps:
1. Locate and quote the relevant provisions
2. Analyze the provision in context of the full agreement
3. Cross-reference related definitions, representations, and other interacting clauses
4. Provide market comparison
5. Draft alternative language if the provision is problematic

### 4. Quick Scan
When the user wants a fast read on key risks without a full review.

Steps:
1. Read the full document
2. Identify the top 5-7 issues by severity
3. Produce a brief summary (1 page max) with the most important risks and recommended actions

## Output Format
- Always use the severity-rated table for issues
- Always include specific section references
- Always include recommended counter-language for High and Critical issues
- End with a "Next Steps" section suggesting what the attorney should focus on
