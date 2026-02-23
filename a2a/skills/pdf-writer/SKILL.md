# PDF Writer Skill

Generate PDF documents with text, tables, images, headers, and footers using Python.

## Library

- **fpdf2** (imported as `fpdf`) — lightweight pure-Python PDF generation

## Creating a Basic PDF

```python
from fpdf import FPDF

pdf = FPDF()
pdf.set_auto_page_break(auto=True, margin=15)
pdf.add_page()

# Title
pdf.set_font("Helvetica", "B", 20)
pdf.cell(0, 12, "Quarterly Report", new_x="LMARGIN", new_y="NEXT", align="C")
pdf.ln(4)

# Body text
pdf.set_font("Helvetica", "", 12)
pdf.multi_cell(0, 7, "Revenue grew 12% quarter-over-quarter driven by increased customer acquisition and reduced churn.")
pdf.ln(4)

# Section heading
pdf.set_font("Helvetica", "B", 14)
pdf.cell(0, 10, "Key Highlights", new_x="LMARGIN", new_y="NEXT")
pdf.set_font("Helvetica", "", 12)
pdf.multi_cell(0, 7, "• Increased customer acquisition by 20%\n• Reduced churn by 3%\n• Expanded into 2 new markets")

pdf.output("/tmp/report.pdf")
```

## Adding a Table

```python
from fpdf import FPDF

pdf = FPDF()
pdf.add_page()
pdf.set_font("Helvetica", "", 12)

headers = ["Region", "Revenue", "Growth"]
data = [
    ["North America", "$2.1M", "15%"],
    ["EMEA", "$1.4M", "8%"],
    ["APAC", "$900K", "22%"],
]

col_widths = [60, 50, 40]

# Header row
pdf.set_font("Helvetica", "B", 12)
pdf.set_fill_color(68, 114, 196)
pdf.set_text_color(255, 255, 255)
for header, w in zip(headers, col_widths):
    pdf.cell(w, 10, header, border=1, fill=True, align="C")
pdf.ln()

# Data rows
pdf.set_font("Helvetica", "", 12)
pdf.set_text_color(0, 0, 0)
for row in data:
    for val, w in zip(row, col_widths):
        pdf.cell(w, 10, val, border=1, align="C")
    pdf.ln()

pdf.output("/tmp/table_report.pdf")
```

## Multi-Page Document with Headers and Footers

```python
from fpdf import FPDF

class ReportPDF(FPDF):
    def header(self):
        self.set_font("Helvetica", "B", 10)
        self.cell(0, 10, "Company Inc. — Confidential", align="C")
        self.ln(12)

    def footer(self):
        self.set_y(-15)
        self.set_font("Helvetica", "I", 8)
        self.cell(0, 10, f"Page {self.page_no()}/{{nb}}", align="C")

pdf = ReportPDF()
pdf.alias_nb_pages()

for section in range(1, 4):
    pdf.add_page()
    pdf.set_font("Helvetica", "B", 16)
    pdf.cell(0, 12, f"Section {section}", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", 12)
    pdf.multi_cell(0, 7, "Lorem ipsum dolor sit amet. " * 30)

pdf.output("/tmp/multi_page_report.pdf")
```

## Adding an Image

```python
from fpdf import FPDF

pdf = FPDF()
pdf.add_page()

# Image from file path (supports PNG, JPEG, GIF)
pdf.image("/tmp/chart.png", x=10, y=30, w=100)

# Image with caption
pdf.set_y(140)
pdf.set_font("Helvetica", "I", 10)
pdf.cell(0, 10, "Figure 1: Revenue by quarter", align="C")

pdf.output("/tmp/report_with_image.pdf")
```

## Page Layout and Margins

```python
from fpdf import FPDF

# Landscape orientation with custom margins
pdf = FPDF(orientation="L", unit="mm", format="A4")
pdf.set_margins(left=20, top=20, right=20)
pdf.set_auto_page_break(auto=True, margin=20)
pdf.add_page()

# Letter size (default is A4)
pdf_letter = FPDF(format="Letter")
```

## Tips

- Save files to `/tmp/` — the workspace directory is for persistent data only.
- Use `multi_cell()` for text that wraps across lines; use `cell()` for single-line content.
- For large reports, use the `ReportPDF` subclass pattern above to get consistent headers/footers.
- To email the PDF, use himalaya with MML attachment syntax:
  ```
  Content-Type: application/pdf
  Content-Disposition: attachment; filename="report.pdf"
  Content-Transfer-Encoding: base64
  ```
- fpdf2 includes built-in fonts (Helvetica, Times, Courier). For custom fonts, use `pdf.add_font()`.
