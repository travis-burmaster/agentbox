# PDF Reader Skill

Read and extract content from PDF files using Python.

## Library

- **PyMuPDF** (imported as `fitz`) — fast PDF text extraction, metadata, and rendering

## Extracting Text from a PDF

```python
import fitz  # PyMuPDF

doc = fitz.open("/tmp/document.pdf")

# Full text extraction
for page_num, page in enumerate(doc):
    text = page.get_text()
    print(f"--- Page {page_num + 1} ---")
    print(text)

doc.close()
```

## Extracting Text as Markdown

```python
import fitz

doc = fitz.open("/tmp/document.pdf")
md_pages = []
for page in doc:
    md_pages.append(page.get_text("text"))
doc.close()

# Join with page separators
markdown = "\n\n---\n\n".join(md_pages)
print(markdown)
```

## Reading PDF Metadata

```python
import fitz

doc = fitz.open("/tmp/document.pdf")
meta = doc.metadata
print(f"Title:    {meta.get('title', 'N/A')}")
print(f"Author:   {meta.get('author', 'N/A')}")
print(f"Subject:  {meta.get('subject', 'N/A')}")
print(f"Pages:    {doc.page_count}")
print(f"Created:  {meta.get('creationDate', 'N/A')}")
doc.close()
```

## Extracting Tables from a PDF

```python
import fitz

doc = fitz.open("/tmp/document.pdf")
for page in doc:
    tables = page.find_tables()
    for table in tables:
        # table.extract() returns a list of rows, each row is a list of cell strings
        for row in table.extract():
            print(row)
doc.close()
```

## Extracting Specific Pages

```python
import fitz

doc = fitz.open("/tmp/document.pdf")

# Single page
page = doc[0]  # First page (0-indexed)
print(page.get_text())

# Page range
for page in doc.pages(start=2, stop=5):  # Pages 3-5 (0-indexed start, exclusive stop)
    print(page.get_text())

doc.close()
```

## Searching within a PDF

```python
import fitz

doc = fitz.open("/tmp/document.pdf")
for page_num, page in enumerate(doc):
    results = page.search_for("search term")
    if results:
        print(f"Found {len(results)} match(es) on page {page_num + 1}")
doc.close()
```

## Tips

- Save files to `/tmp/` — the workspace directory is for persistent data only.
- PyMuPDF is read-only for this skill's purposes. To create PDFs, generate content in DOCX first then note that conversion requires external tools.
- For large PDFs, process page-by-page to avoid memory issues.
- `page.get_text("dict")` returns structured blocks with font info, useful for detecting headings.
- To email extracted content, use himalaya to send the Markdown output as the email body, or attach the original PDF:
  ```
  Content-Type: application/pdf
  Content-Disposition: attachment; filename="document.pdf"
  Content-Transfer-Encoding: base64
  ```
