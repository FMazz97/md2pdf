# Template for pdf-config.psd1, to be placed in the project root.
# Every key is optional: missing keys use the defaults defined in build-pdf.ps1.
@{
  Title          = 'Document title'         # default: first "# ..." heading of README.md, otherwise the folder name
  Subtitle       = ''                       # empty = not shown
  Author         = ''                       # empty = not shown
  Version        = ''                       # empty = latest Git tag (when VersionFromGit is set)
  VersionFromGit = $true
  ShowDate       = $true
  TocTitle       = 'Table of Contents'
  Lang           = 'en'
  Output         = ''                       # empty = "<Title>_<Version>.pdf"; when set, relative to the project
  # Zones excluded from the PDF (still visible on GitHub): text enclosed between two HTML comments, each on its
  # own line, also inside lists or quotes:
  #   <!--START_no_print_zone-->  ...excluded text...  <!--STOP_no_print_zone-->
  # Only the name contained in the comment is set here. The names differ and neither contains the other; empty = disabled.
  ExcludeStart   = 'START_no_print_zone'
  ExcludeStop    = 'STOP_no_print_zone'
  KeepBuild      = $false                   # $true = keep .build-pdf\ (intermediate HTML) after the run
  # Files to include, in order; patterns containing * are sorted by name. Markdown (.md) files only.
  Files          = @('README.md', 'chapters/*.md', 'appendices/*.md')
}
