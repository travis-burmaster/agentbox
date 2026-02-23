# DOCX Tools Skill

Create, read, and convert Microsoft Word (.docx) documents using Python.

## Libraries

- **python-docx** — create and read `.docx` files
- **mammoth** — convert `.docx` to clean Markdown / HTML

## Creating a DOCX Document

```python
from docx import Document
from docx.shared import Inches, Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# Title
doc.add_heading("Quarterly Report", level=0)

# Paragraph with formatting
p = doc.add_paragraph()
run = p.add_run("Executive Summary: ")
run.bold = True
p.add_run("Revenue grew 12% quarter-over-quarter.")

# Bullet list
doc.add_paragraph("Increased customer acquisition", style="List Bullet")
doc.add_paragraph("Reduced churn by 3%", style="List Bullet")

# Table
table = doc.add_table(rows=1, cols=3)
table.style = "Light Grid Accent 1"
hdr = table.rows[0].cells
hdr[0].text, hdr[1].text, hdr[2].text = "Region", "Revenue", "Growth"
for region, rev, growth in [("NA", "$2.1M", "15%"), ("EMEA", "$1.4M", "8%")]:
    row = table.add_row().cells
    row[0].text, row[1].text, row[2].text = region, rev, growth

# Save
doc.save("/tmp/report.docx")
```

## Reading a DOCX Document

```python
from docx import Document

doc = Document("/tmp/report.docx")
for para in doc.paragraphs:
    print(para.style.name, ":", para.text)

for table in doc.tables:
    for row in table.rows:
        print([cell.text for cell in row.cells])
```

## Converting DOCX to Markdown

```python
import mammoth

with open("/tmp/report.docx", "rb") as f:
    result = mammoth.convert_to_markdown(f)
    markdown = result.value       # Markdown string
    messages = result.messages    # Any conversion warnings
print(markdown)
```

## Tips

- Save files to `/tmp/` — the workspace directory is for persistent data only.
- To email the document, use himalaya with MML attachment syntax:
  ```
  himalaya send --account default <<MML
  From: AgentBox <bot@yourdomain.com>
  To: user@example.com
  Subject: Your report
  Mime-Version: 1.0
  Content-Type: multipart/mixed; boundary="BOUNDARY"

  --BOUNDARY
  Content-Type: text/plain

  Please find the report attached.

  --BOUNDARY
  Content-Type: application/vnd.openxmlformats-officedocument.wordprocessingml.document
  Content-Disposition: attachment; filename="report.docx"
  Content-Transfer-Encoding: base64

  <base64-encoded content>

  --BOUNDARY--
  MML
  ```
- For large documents, stream content section by section rather than loading everything into memory.
