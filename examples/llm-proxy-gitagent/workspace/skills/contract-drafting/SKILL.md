---
name: contract-drafting
description: >
  Draft contracts and legal agreements from term sheets, deal points, or instructions.
  Produces complete, practice-ready documents with appropriate boilerplate calibrated
  to deal size and relationship context.
license: MIT
allowed-tools: Read Edit Grep Glob Bash
metadata:
  author: claude-law-firm
  version: "1.0.0"
  category: legal
---

# Contract Drafting Skill

## Trigger
Activate when the user wants to draft a new agreement, generate closing documents, or produce a contract from a term sheet or set of deal points.

## Process

### 1. Gather Requirements
Before drafting, establish:
- **Document type** (NDA, SPA, SaaS agreement, services agreement, employment offer, SAFE, etc.)
- **Which party you represent** (and their relative negotiating leverage)
- **Key commercial terms** (price, term, scope, deliverables)
- **Deal context** (size, industry, relationship, repeat deal vs. new counterparty)
- **Governing law and jurisdiction**
- **Any specific provisions the attorney wants included or excluded**

### 2. Select Appropriate Complexity
Calibrate the document to the deal:
- **Simple/low-value deals**: Clean, short agreements. No need for 15 pages of boilerplate on a $10K services engagement.
- **Mid-market deals**: Full boilerplate with standard protections. Market-standard representations and warranties.
- **Complex/high-value deals**: Comprehensive drafting with detailed reps, extensive indemnification framework, disclosure schedules, and closing conditions.

### 3. Draft the Document
Structure:
1. Preamble and recitals
2. Definitions (only define terms used more than once)
3. Substantive terms (the business deal)
4. Representations and warranties (calibrated to deal type)
5. Covenants (pre-closing and post-closing if applicable)
6. Indemnification (if applicable)
7. Termination
8. General provisions (assignment, notices, amendments, severability, entire agreement, counterparts)
9. Signature blocks

Drafting principles:
- Draft in favor of your client but within market norms — don't draft so aggressively that the counterparty's lawyer immediately redlines half the document
- Use defined terms consistently
- Cross-reference accurately
- Use plain English where possible — "if" not "in the event that"
- Number sections and subsections consistently
- Include bracketed placeholders `[___]` for factual details the attorney needs to fill in

### 4. Self-Review
Before delivering:
- Check all defined terms are actually used
- Check all cross-references point to correct sections
- Check numbering is sequential and consistent
- Verify no internal contradictions between provisions
- Confirm the document is balanced for the stated party and context

### 5. Output
- Deliver the complete draft
- Include a cover note listing: key decision points the attorney should consider, provisions where the attorney's judgment is needed on aggressiveness level, and any assumptions made during drafting
