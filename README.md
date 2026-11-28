# PDF export for Markdown documentation

**English** · [Italiano](README-it.md)

Turns a Markdown documentation project into a single PDF with a cover page, a table of contents with page numbers and a numbered footer, all in GitHub style. The package lives in a fixed folder, outside the projects, and asks which project folder to export.

## 1 Prerequisites

- Windows with PowerShell 5.1 or later
- [Pandoc](https://pandoc.org/installing.html) (from a shell: `winget install --source winget --exact --id JohnMacFarlane.Pandoc`)
- [Node.js](https://nodejs.org/en/download) 20 or later ([Download-v26.13.1-x64](https://nodejs.org/dist/v26.13.1/node-v26.13.1-x64.msi))
- Google Chrome or Microsoft Edge

On the first run the script installs the Node dependencies by itself (`npm install`) in the package folder.

## 2 Installation

Copy this folder to a fixed location, for example `C:\Tools\pdf-export\`.

## 3 Usage

- **Double-click `print.bat`**: a dialog opens to choose the project folder (it proposes the last one used).
- **Drag a folder onto `print.bat`**: skips the selection dialog.
- **From PowerShell**:

  ```powershell
  powershell -ExecutionPolicy Bypass -File build-pdf.ps1 -Project "C:\path\to\project" [-Output name.pdf] [-NoOpen] [-Keep]
  ```

The PDF is created in the project folder as `<Title>_<Version>.pdf` (`<Title>.pdf` only when there is no version; spaces and characters not valid in file names become `_`) and opens when finished. Title and version are the same as on the cover page.

To keep the intermediate HTML, which stays in `<project>\.build-pdf\<pdf-name>.html`, add `-Keep` to the PowerShell command or set `KeepBuild = $true` in `pdf-config.psd1` (the only option that also works with a double-click on `print.bat`).

Adding `.build-pdf/` and the generated PDF to the project's `.gitignore` is recommended.

## 4 Per-project settings

Optional: create `pdf-config.psd1` in the project root, starting from `pdf-config.example.psd1`.

| Key | Meaning | Default |
| --- | --- | --- |
| `Title` | Title on the cover page and of the PDF | first `# ...` heading of the README, otherwise the folder name |
| `Subtitle`, `Author` | Subtitle and author on the cover page | empty (not shown) |
| `Version` | Version label on the cover page | empty: latest Git tag |
| `VersionFromGit` | Use the latest Git tag when `Version` is empty | `$true` |
| `ShowDate` | Generation date on the cover page | `$true` |
| `TocTitle`, `Lang` | Table of contents title and language | `Table of Contents`, `en` |
| `Output` | PDF name (relative to the project) | `<Title>_<Version>.pdf` |
| `ExcludeStart`, `ExcludeStop` | Names of the markers delimiting zones left out of the PDF (empty = disabled) | `START_no_print_zone`, `STOP_no_print_zone` |
| `KeepBuild` | Keep `.build-pdf\` (intermediate HTML) after the run | `$false` |
| `Files` | Files to include, in order (accepts `*`, `.md` only) | `README.md`, `chapters/*.md`, `appendices/*.md` |

Everything not listed in `Files` (`LICENSE`, `assets/`, ...) stays out of the PDF.

## 5 What it does

- Each Markdown file starts on a new page; headings, lists, tables, code blocks and alerts are not split across pages, except those taller than 40% of the usable area (the threshold is in `print-pdf.mjs`), which may continue on the next page to avoid leaving gaps.
- A running header appears on every page except the cover: the document title on the left (same as the cover page) and the title of the current section, the top-level `#` heading of the file, on the right.
- A file with more than one top-level `#` heading is treated as several files: each `#` heading after the first starts a new page and a new section, listed at the same level in the table of contents and shown in the header.
- Relative links between files become internal references in the PDF; links to excluded files become plain text.
- The alerts `> [!NOTE]`, `TIP`, `IMPORTANT`, `WARNING` and `CAUTION` use the GitHub colors. The text after the marker on the same line becomes the block title: `> [!NOTE] Custom title` (not part of the GitHub standard, but very handy).
- The initial HTML image of the README becomes a plain image, without links.
- Text enclosed between `<!--START_no_print_zone-->` and `<!--STOP_no_print_zone-->` (each comment on its own line, also inside lists or quotes) is excluded from the PDF and stays visible on GitHub. A `START` without a `STOP` excludes up to the end of the block and reports a warning. Links pointing to an excluded heading lead nowhere.
- Code blocks use the GitHub colors (C/C++, JSON, YAML, CMake, properties, bash), based on the language given after the three backticks.

## 6 Package files

| File | Role |
| --- | --- |
| `print.bat` | Double-click launcher |
| `build-pdf.ps1` | Main script |
| `export.lua` | Pandoc filter (links, alerts, excluded zones, images) |
| `github-pdf.css` | Style and pagination rules |
| `code-colors.js` | Code colors as on GitHub |
| `print-pdf.mjs`, `package.json` | PDF printing with page numbers and table of contents |
| `stamp-headers.mjs` | Running header (document title and current section) |
| `pdf-config.example.psd1` | Template for per-project settings |

## 7 Common problems

- **Node.js or Pandoc not found**: install them and reopen the terminal; if the problem persists, check with `node --version` and `pandoc --version`.
- **Missing emoji**: system emoji fonts are required (on Windows it is `Segoe UI Emoji`).
