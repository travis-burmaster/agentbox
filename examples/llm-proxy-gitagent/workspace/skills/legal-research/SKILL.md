---
name: legal-research
description: >
  Structured legal research with parallel multi-angle analysis, primary authority
  prioritization, and mandatory anti-hallucination self-verification. Produces
  practice-ready research memos with confidence ratings.
license: MIT
allowed-tools: Read Edit Grep Glob Bash WebSearch WebFetch
metadata:
  author: claude-law-firm
  version: "1.0.0"
  category: legal
---

# Legal Research Skill

## Trigger
Activate when the user needs legal research on a question of law, regulatory analysis, or case law synthesis.

## Process

### 1. Frame the Research Question
Before beginning:
- Restate the research question precisely
- Identify the jurisdiction(s)
- Identify the relevant areas of law
- Break the question into sub-issues for parallel analysis

### 2. Conduct Research
For each sub-issue, research in parallel across all relevant angles:
- **Statutes and codes**: Primary statutory authority
- **Regulations**: Agency rules and regulatory guidance
- **Case law**: Controlling and persuasive authority
- **Agency guidance**: Interpretive letters, no-action letters, FAQs, policy statements
- **Secondary sources**: Treatises, law review articles, practice guides (lower priority)

Prioritization: Primary authority (statutes, regulations, binding case law) > agency guidance > persuasive authority > secondary commentary.

Run multiple searches per sub-topic. Do not rely on a single query.

### 3. Mandatory Self-Verification (CRITICAL)
Before delivering ANY output, complete this verification checklist:

- [ ] **Citation verification**: Every cited authority actually exists and actually says what the memo claims
- [ ] **Quotation accuracy**: Every quoted passage is accurate (if quoting)
- [ ] **Internal consistency**: No contradictions between sections of the memo
- [ ] **Confidence assessment**: Each conclusion rated as High / Moderate / Low confidence with explanation
- [ ] **Hallucination guard**: Specifically check for fabricated case names, fake statutes, invented regulatory provisions, or non-existent agency guidance
- [ ] **Currency check**: Flag any authority that may have been superseded, amended, or overruled
- [ ] **Jurisdiction match**: Confirm all cited authority is from the relevant jurisdiction

If ANY citation cannot be verified, either remove it or explicitly flag it as "[UNVERIFIED — attorney should confirm]".

### 4. Output Format

**Research Memo Structure:**

**BOTTOM LINE (3-5 sentences)**
State the answer to the research question. Be direct. If the answer is uncertain, say so and explain why.

**ANALYSIS**
For each sub-issue:
- **Issue**: One-sentence statement
- **Rule**: Applicable law with citations
- **Analysis**: Application to the client's facts
- **Conclusion**: Answer to the sub-issue with confidence level

**REGULATORY FRAMEWORK TABLE** (if applicable)
| Agency | Authority | Requirement | Risk Level |
|--------|-----------|-------------|------------|

**PRACTICAL RECOMMENDATIONS**
- What the client should do
- What to watch for
- What follow-up research may be needed

**LIMITATIONS AND CAVEATS**
- Jurisdictions not covered
- Areas of legal uncertainty
- Facts that could change the analysis

### 5. Anti-Hedging Rule
Be direct about conclusions. Do not write "it could be argued that" when you mean "the stronger argument is." State your conclusion, then note the counterargument separately. Attorneys need your best assessment, not a balanced presentation of every possible view.
