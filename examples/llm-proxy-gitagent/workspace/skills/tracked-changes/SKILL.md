---
name: tracked-changes
description: >
  Apply tracked changes to Word documents (.docx) at the XML level. Produces real
  Word tracked changes attributed to the attorney's name, preserving all formatting.
  No need to open Microsoft Word or any other application.
license: MIT
allowed-tools: Read Edit Grep Glob Bash
metadata:
  author: claude-law-firm
  version: "1.0.0"
  category: legal
---

# Tracked Changes Skill

## Trigger
Activate when the user wants to apply edits, redlines, or markup to a Word document (.docx).

## Process

### 1. Understand the Edits
Before touching the document:
- Confirm which edits to apply (from a contract review, attorney instructions, or negotiation positions)
- Identify the attorney name to attribute changes to
- Identify the date for the tracked changes (default: today)

### 2. Extract and Parse the Document
- Unzip the .docx file (it's a ZIP archive of XML files)
- Parse `word/document.xml` for the document body
- Parse `word/styles.xml` for formatting
- Parse `word/numbering.xml` for paragraph numbering if present
- Note existing tracked changes in the document — never modify or remove them

### 3. Apply Tracked Changes
For each edit, insert the appropriate XML markup:

**Deletions:** Wrap deleted text in `<w:del>` elements with `w:author` and `w:date` attributes.

**Insertions:** Wrap new text in `<w:ins>` elements with `w:author` and `w:date` attributes.

**Formatting changes:** Use `<w:rPrChange>` within run properties.

Critical requirements:
- Preserve ALL existing formatting (bold, italic, fonts, sizes, colors, styles)
- Preserve ALL existing tracked changes from prior rounds of editing
- Preserve paragraph numbering and list formatting
- Preserve headers, footers, and section breaks
- Preserve cross-references and bookmarks
- Use the attorney's actual name in `w:author`, never a generic name
- Use ISO 8601 date format for `w:date`

### 4. Reassemble and Validate
- Repackage the modified XML files into a valid .docx
- Verify the file opens without errors
- Confirm tracked changes appear correctly attributed

### 5. Produce Output
- Save the modified .docx file
- Provide a summary of all changes made (insertion count, deletion count, sections affected)
- Flag any formatting issues encountered during the process

## Important Notes
- This skill manipulates the raw XML inside .docx files. The output must be valid Office Open XML.
- Always work on a copy of the original document, never modify the original
- If the document has complex formatting (tables, images, embedded objects), flag potential risks before proceeding
- Test the output by verifying XML well-formedness before saving
