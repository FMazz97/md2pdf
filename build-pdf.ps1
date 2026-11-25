<#
 Exports a Markdown documentation project to PDF (Pandoc + Chrome/Edge + Node).
 The package can live anywhere: the project folder is passed with -Project or chosen in a dialog at start-up.
 Usage:
   powershell -ExecutionPolicy Bypass -File build-pdf.ps1 [-Project <folder>] [-Output <file.pdf>] [-NoOpen] [-Keep]
 Per-project settings (title, version, files to include, ...) are read from pdf-config.psd1 in the project
 folder (see pdf-config.example.psd1). -Keep, KeepBuild = $true in the configuration file, or $env:KEEP = '1'
 keeps <project>\.build-pdf\<pdf-name>.html after the run.
#>
param([string]$Project = '', [string]$Output = '', [switch]$NoOpen, [switch]$Keep)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot

# PATH is re-read from the registry, which covers Node or Pandoc installed after Explorer or the terminal
# started (typical with a double-clicked .bat); standard install folders are then searched as a fallback.
$env:Path = (@([Environment]::GetEnvironmentVariable('Path', 'Machine'),
               [Environment]::GetEnvironmentVariable('Path', 'User'), $env:Path) | Where-Object { $_ }) -join ';'
foreach ($tool in @(@('node', "$env:ProgramFiles\nodejs"),
                    @('pandoc', "$env:LOCALAPPDATA\Pandoc"),
                    @('pandoc', "$env:ProgramFiles\Pandoc"))) {
  if (-not (Get-Command $tool[0] -ErrorAction SilentlyContinue) -and (Test-Path (Join-Path $tool[1] "$($tool[0]).exe"))) {
    $env:Path += ';' + $tool[1]
  }
}

function Enc([string]$s) { [System.Net.WebUtility]::HtmlEncode($s) }
function Get-Rel([string]$p) { ($p.Substring($Root.Length).TrimStart('\', '/')) -replace '\\', '/' }
function Get-Id([string]$f) { ((($f -replace '\.md$', '') -replace '[/ ]', '-')).ToLowerInvariant() }  # must match id_of() in export.lua

function Get-GitTag {
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return '' }
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try {
    $t = & git describe --tags --abbrev=0 2>$null
    if ($LASTEXITCODE -eq 0 -and $t) { return ("$t").Trim() }
  } finally { $ErrorActionPreference = $old }
  return ''
}

function Select-Project {
  try {
    Add-Type -AssemblyName System.Windows.Forms
    $last = Join-Path $Here 'last-project.txt'
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Choose the project folder to export to PDF'
    if (Test-Path $last) { $dlg.SelectedPath = (Get-Content -LiteralPath $last -Raw).Trim() }
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return '' }
    return $dlg.SelectedPath
  } catch {
    return (Read-Host 'Project folder')
  }
}

# ---- Project folder ----
if (-not $Project) { $Project = Select-Project }
if (-not $Project) { Write-Host 'No folder selected.'; exit 1 }
if (-not (Test-Path -LiteralPath $Project -PathType Container)) { throw "Folder not found: $Project" }
$Root = (Resolve-Path -LiteralPath $Project).Path
Set-Location -LiteralPath $Root
Set-Content -LiteralPath (Join-Path $Here 'last-project.txt') -Value $Root

# ---- Settings: defaults, then pdf-config.psd1 from the project ----
$Cfg = @{
  Title          = ''     # empty = first "# ..." heading of README.md, otherwise the folder name
  Subtitle       = ''
  Author         = ''
  Version        = ''     # empty = latest Git tag (when VersionFromGit is set)
  VersionFromGit = $true
  ShowDate       = $true
  TocTitle       = 'Table of Contents'
  Lang           = 'en'
  Output         = ''     # empty = "<Title>_<Version>.pdf" ("<Title>.pdf" when there is no version)
  ExcludeStart   = 'START_no_print_zone'   # markers delimiting zones left out of the PDF: <!--START_no_print_zone--> ... <!--STOP_no_print_zone-->
  ExcludeStop    = 'STOP_no_print_zone'    # the two names differ and neither contains the other; empty = feature disabled
  KeepBuild      = $false # $true = keep the .build-pdf folder (intermediate HTML) after the run
  Files          = @('README.md', 'chapters/*.md', 'appendices/*.md')   # in order; wildcard matches are sorted by name
}
$cfgPath = Join-Path $Root 'pdf-config.psd1'
if (Test-Path -LiteralPath $cfgPath) {
  $user = Import-PowerShellDataFile -LiteralPath $cfgPath
  foreach ($k in $user.Keys) { $Cfg[$k] = $user[$k] }
}

$Title = $Cfg.Title
if (-not $Title) {
  $readme = Join-Path $Root 'README.md'
  if (Test-Path -LiteralPath $readme) {
    foreach ($line in (Get-Content -LiteralPath $readme -Encoding UTF8)) {
      if ($line -match '^#\s+(.+?)\s*#*\s*$') { $Title = $Matches[1]; break }
    }
  }
  if (-not $Title) { $Title = Split-Path $Root -Leaf }
}
# Version: same rule for the cover page and the PDF file name
$Version = $Cfg.Version
if (-not $Version -and $Cfg.VersionFromGit) { $Version = Get-GitTag }

if (-not $Output) { $Output = $Cfg.Output }
if (-not $Output) {
  $name = $Title
  if ($Version) { $name += '_' + $Version }
  $name = ($name -replace '[\x00-\x1f\\/:*?"<>|\s]+', '_').Trim('_', '.')   # whitespace and invalid file-name characters -> _
  $Output = "$name.pdf"
}
if (-not [IO.Path]::IsPathRooted($Output)) { $Output = Join-Path $Root $Output }

$Build = Join-Path $Root '.build-pdf'
$Utf8 = New-Object System.Text.UTF8Encoding($false)

# ---- Tools ----
$candidates = @(
  "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
  "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
  "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
)
$Browser = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $Browser) { throw 'Chrome or Edge not found.' }
if (-not (Get-Command pandoc -ErrorAction SilentlyContinue)) { throw 'pandoc not found in PATH.' }
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  throw 'Node.js not found: install it from https://nodejs.org and reopen the terminal (required for page numbers).'
}

# ---- Files to include (anything not listed, such as LICENSE or assets/, stays out) ----
$files = @()
foreach ($pat in $Cfg.Files) {
  Get-ChildItem -Path (Join-Path $Root $pat) -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -eq '.md' } | Sort-Object Name |
    ForEach-Object { $r = Get-Rel $_.FullName; if ($files -notcontains $r) { $files += $r } }
}
if ($files.Count -eq 0) { throw "No Markdown files found in $Root (check 'Files' in pdf-config.psd1)." }

# Variables read by export.lua (root as /C:/path, used to build file:///C:/... URLs)
$rootUrl = $Root -replace '\\', '/'
if (-not $rootUrl.StartsWith('/')) { $rootUrl = '/' + $rootUrl }
$env:EXPORT_ROOT  = $rootUrl
$env:EXPORT_FILES = ($files -join "`n")
$env:EXPORT_EXCLUDE_START = [string]$Cfg.ExcludeStart
$env:EXPORT_EXCLUDE_STOP  = [string]$Cfg.ExcludeStop

Write-Host 'Printing...'
Write-Host "Project: $Root"

if (Test-Path $Build) { Remove-Item $Build -Recurse -Force }
$Parts = Join-Path $Build 'parts'
New-Item -ItemType Directory -Path $Parts | Out-Null
$KeepBuild = $Keep.IsPresent -or [bool]$Cfg.KeepBuild -or [bool]$env:KEEP

try {
  # Alerts (> [!NOTE]) are handled by export.lua to support custom titles; when this Pandoc version converts
  # them natively, the built-in conversion is switched off.
  $gfm = 'gfm'
  if (@(& pandoc --list-extensions=gfm | Where-Object { $_ -match 'alerts$' }).Count -gt 0) { $gfm = 'gfm-alerts' }

  # 1) One HTML fragment per file (written to disk to avoid PowerShell re-encoding emoji and accented text)
  foreach ($f in $files) {
    $id   = Get-Id $f
    $frag = Join-Path $Parts "$id.html"
    # --id-prefix avoids id collisions; a high --columns value avoids relative column widths in tables
    & pandoc $f -f $gfm -t html5 --wrap=none --columns=10000 `
      "--id-prefix=${id}--" "--lua-filter=$Here\export.lua" -M "filepath=$f" -o $frag
    if ($LASTEXITCODE -ne 0) { throw "pandoc failed on $f" }
  }

  # 2) Final HTML: cover page, table of contents, documents
  $sb = New-Object System.Text.StringBuilder
  $css = [IO.File]::ReadAllText((Join-Path $Here 'github-pdf.css'), $Utf8)
  [void]$sb.AppendLine('<!DOCTYPE html>')
  [void]$sb.AppendLine("<html lang=`"$($Cfg.Lang)`"><head><meta charset=`"utf-8`"><title>$(Enc $Title)</title><style>")
  [void]$sb.AppendLine($css)
  [void]$sb.AppendLine('</style></head><body><main class="markdown-body">')

  # Cover page
  [void]$sb.AppendLine('<section class="titlepage">')
  [void]$sb.AppendLine("<p class=`"tp-title`">$(Enc $Title)</p>")
  if ($Cfg.Subtitle) { [void]$sb.AppendLine("<p class=`"tp-subtitle`">$(Enc $Cfg.Subtitle)</p>") }
  if ($Version) { [void]$sb.AppendLine("<p class=`"tp-version`"><span>$(Enc $Version)</span></p>") }
  $meta = @()
  if ($Cfg.Author)  { $meta += (Enc $Cfg.Author) }
  if ($Cfg.ShowDate) { $meta += (Get-Date -Format 'yyyy-MM-dd') }
  if ($meta.Count -gt 0) { [void]$sb.AppendLine("<p class=`"tp-meta`">$($meta -join ' &middot; ')</p>") }
  [void]$sb.AppendLine('</section>')

  # Table of contents (filled in by the script at the end of the page)
  [void]$sb.AppendLine("<nav class=`"toc`"><p class=`"toc-title`">$(Enc $Cfg.TocTitle)</p><div id=`"toc-list`"></div></nav>")

  foreach ($f in $files) {
    $id = Get-Id $f
    [void]$sb.AppendLine("<section class=`"doc`" id=`"$id`">")
    [void]$sb.AppendLine([IO.File]::ReadAllText((Join-Path $Parts "$id.html"), $Utf8))
    [void]$sb.AppendLine('</section>')
  }

  # Table of contents built from the h1-h3 headings (entries link to the sections)
  [void]$sb.AppendLine(@'
<script>
(function () {
  function esc(s) { return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;'); }
  var html = '';
  document.querySelectorAll('section.doc h1, section.doc h2, section.doc h3').forEach(function (h) {
    if (!h.id) return;
    html += '<li class="toc-' + h.tagName.charAt(1) + '"><a href="#' + h.id + '"><span class="t">' + esc(h.textContent) +
      '</span><span class="dots"></span><span class="pn" data-id="' + esc(h.id) + '">00</span></a></li>';
  });
  document.getElementById('toc-list').innerHTML = '<ul>' + html + '</ul>';
})();
</script>
'@)
  [void]$sb.AppendLine('</main></body></html>')

  $html = Join-Path $Build ([IO.Path]::GetFileNameWithoutExtension($Output) + '.html')
  [IO.File]::WriteAllText($html, $sb.ToString(), $Utf8)

  # 3) PDF printing through Node + puppeteer-core (page-number footer)
  $url = (New-Object System.Uri($html)).AbsoluteUri
  if (Test-Path $Output) { Remove-Item $Output -Force }
  if (-not (Test-Path (Join-Path $Here 'node_modules\pdfjs-dist'))) {
    Push-Location $Here
    try {
      & npm.cmd install --no-audit --no-fund
      if ($LASTEXITCODE -ne 0) { throw 'npm install failed' }
    } finally { Pop-Location }
  }
  & node (Join-Path $Here 'print-pdf.mjs') $url $Output $Browser
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $Output)) { throw 'PDF generation failed.' }
  Write-Host "Created: $Output"
  if (-not $NoOpen) { Start-Process -FilePath $Output }
}
finally {
  if (-not $KeepBuild) { Remove-Item $Build -Recurse -Force -ErrorAction SilentlyContinue }
}
