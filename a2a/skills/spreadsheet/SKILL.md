# Spreadsheet Skill

Create and read Microsoft Excel (.xlsx) spreadsheets using Python.

## Library

- **openpyxl** — full-featured XLSX read/write

## Creating a Spreadsheet

```python
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter

wb = Workbook()
ws = wb.active
ws.title = "Sales Data"

# Header row with styling
headers = ["Product", "Q1", "Q2", "Q3", "Q4", "Total"]
header_font = Font(bold=True, color="FFFFFF")
header_fill = PatternFill(start_color="4472C4", end_color="4472C4", fill_type="solid")

for col, header in enumerate(headers, 1):
    cell = ws.cell(row=1, column=col, value=header)
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal="center")

# Data rows
data = [
    ("Widget A", 1200, 1350, 1500, 1800),
    ("Widget B", 800, 900, 950, 1100),
    ("Widget C", 2000, 2100, 2300, 2500),
]
for row_idx, (product, *quarters) in enumerate(data, 2):
    ws.cell(row=row_idx, column=1, value=product)
    for col_idx, val in enumerate(quarters, 2):
        ws.cell(row=row_idx, column=col_idx, value=val)
    # Total formula
    ws.cell(row=row_idx, column=6, value=f"=SUM(B{row_idx}:E{row_idx})")

# Auto-fit column widths (approximate)
for col in range(1, len(headers) + 1):
    ws.column_dimensions[get_column_letter(col)].width = 14

# Add a second sheet
ws2 = wb.create_sheet("Summary")
ws2["A1"] = "Grand Total"
ws2["B1"] = "=SUM('Sales Data'!F2:F100)"

wb.save("/tmp/sales_report.xlsx")
```

## Reading a Spreadsheet

```python
from openpyxl import load_workbook

wb = load_workbook("/tmp/sales_report.xlsx", data_only=True)
ws = wb.active

# Read all rows
for row in ws.iter_rows(min_row=1, values_only=True):
    print(row)

# Read specific cell
print(ws["A1"].value)

# Iterate sheets
for sheet_name in wb.sheetnames:
    ws = wb[sheet_name]
    print(f"\n--- {sheet_name} ---")
    for row in ws.iter_rows(values_only=True):
        print(row)
```

## Number Formatting

```python
from openpyxl.styles import numbers

cell = ws.cell(row=2, column=2, value=1200)
cell.number_format = "$#,##0"       # Currency
# cell.number_format = "0.00%"      # Percentage
# cell.number_format = "#,##0.00"   # Thousands with decimals
```

## Tips

- Save files to `/tmp/` — the workspace directory is for persistent data only.
- Use `data_only=True` when reading to get calculated values instead of formulas (only works if the file was last saved by Excel).
- To email the spreadsheet, use himalaya with MML attachment syntax:
  ```
  Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
  Content-Disposition: attachment; filename="report.xlsx"
  Content-Transfer-Encoding: base64
  ```
- For CSV export, read with openpyxl and write with Python's built-in `csv` module.
