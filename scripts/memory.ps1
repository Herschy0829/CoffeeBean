#Requires -Version 5.1
<#
  CoffeeBean memory health check. Deterministic, offline, zero model tokens.

  Usage:
      powershell -File scripts/memory.ps1                  # check; exit 1 when compaction is needed
      powershell -File scripts/memory.ps1 -Action status   # same numbers, never exits 1

  Deliberate constraints (same as run-editmode-tests.ps1):
    - Windows PowerShell 5.1 compatible. `pwsh` is NOT installed on this machine,
      so `pwsh -File ...` fails here even though the docs use it (CI runners have it).
    - ASCII-only, no BOM. PS 5.1 reads BOM-less files as ANSI and mangles non-ASCII,
      which breaks parsing. Do NOT add non-ASCII characters to this file.

  Budgets are duplicated in .dsh/memory/README.md section 5.
  Change both, or the report will disagree with the spec.

  This script only READS. Compression itself is an agent task (see the spec).
#>
[CmdletBinding()]
param(
    [ValidateSet('check', 'status')]
    [string]$Action = 'check',
    [string]$Root
)

$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }

# ---------- budgets: keep in sync with .dsh/memory/README.md section 5 ----------
# Agents* applies to the SUM of the always-on files (AGENTS.md + AGENTS.local.md):
# both are injected into every session, so only the total is what costs tokens.
$AgentsWarnBytes = 4608
$AgentsMaxBytes  = 5120
$IndexWarnLines  = 50
$IndexMaxLines   = 60
$FactWarnLines   = 40
$FactMaxLines    = 60
$FactsMax        = 40
$ReadmeMaxLines  = 200
$StateMaxLines   = 60

# ---------- paths ----------
$memDir      = Join-Path $Root '.dsh/memory'
$factsDir    = Join-Path $memDir 'facts'
$agents      = Join-Path $Root 'AGENTS.md'
$agentsLocal = Join-Path $Root 'AGENTS.local.md'
$index       = Join-Path $memDir 'INDEX.md'
$readme      = Join-Path $memDir 'README.md'
$state       = Join-Path $memDir 'state/current.md'

# The memory store is deliberately local-only (.gitignore'd), so a fresh clone has
# none. That is not an error - it just means this checkout has not enabled it.
if (-not (Test-Path -LiteralPath $memDir)) {
    Write-Output 'no memory store at .dsh/memory (local-only, not in git) - nothing to check.'
    exit 0
}

$script:issues = @()
$script:warns  = @()

function Add-Issue { param([string]$Text) $script:issues += $Text }
function Add-Warn  { param([string]$Text) $script:warns  += $Text }

function Get-LineCount {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    return @(Get-Content -LiteralPath $Path -Encoding UTF8).Count
}

function Get-ByteSize {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    return (Get-Item -LiteralPath $Path).Length
}

function Format-Kb {
    param([long]$Bytes)
    return [string]::Format('{0:N0} B ({1:N1} KB)', $Bytes, ($Bytes / 1KB))
}

Write-Output '=== CoffeeBean memory check ==='
Write-Output ("root: {0}" -f $Root)
Write-Output ("date: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm'))
Write-Output ''

# ---------- 1. always-on instruction files ----------
Write-Output '[1] always-on instructions (injected into every session)'
$alwaysOn = @($agents, $agentsLocal)
$alwaysOnBytes = 0
foreach ($f in $alwaysOn) {
    $leaf = Split-Path -Leaf $f
    if (-not (Test-Path -LiteralPath $f)) {
        Write-Output ("    {0,-18} {1}" -f $leaf, 'absent (local overlay is optional)')
        continue
    }
    $b = Get-ByteSize $f
    $l = Get-LineCount $f
    $alwaysOnBytes += $b
    Write-Output ("    {0,-18} {1,7} B   {2,3} lines" -f $leaf, $b, $l)
}
if (-not (Test-Path -LiteralPath $agents)) {
    Add-Issue 'AGENTS.md is missing - the always-on project rules are gone'
}
Write-Output ("    {0,-18} {1,7} B   budget: warn {2} / max {3}" -f 'TOTAL', $alwaysOnBytes, $AgentsWarnBytes, $AgentsMaxBytes)
if ($alwaysOnBytes -gt $AgentsMaxBytes) {
    Add-Issue ("always-on instructions total {0} B, over the {1} B cap - push detail down into facts/" -f $alwaysOnBytes, $AgentsMaxBytes)
} elseif ($alwaysOnBytes -gt $AgentsWarnBytes) {
    Add-Warn ("always-on instructions total {0} B, near the {1} B cap" -f $alwaysOnBytes, $AgentsMaxBytes)
}

# ---------- 2. INDEX.md ----------
Write-Output ''
Write-Output '[2] INDEX.md (read at the start of every task)'
$indexRefs = @()
if (-not (Test-Path -LiteralPath $index)) {
    Add-Issue 'INDEX.md is missing'
    Write-Output '    MISSING'
} else {
    $il = Get-LineCount $index
    Write-Output ("    lines: {0}   bytes: {1}" -f $il, (Format-Kb (Get-ByteSize $index)))
    Write-Output ("    budget: warn {0} lines / max {1} lines" -f $IndexWarnLines, $IndexMaxLines)
    if ($il -gt $IndexMaxLines) {
        Add-Issue ("INDEX.md is {0} lines, over the {1}-line cap - merge or archive" -f $il, $IndexMaxLines)
    } elseif ($il -gt $IndexWarnLines) {
        Add-Warn ("INDEX.md is {0} lines, near the {1}-line cap" -f $il, $IndexMaxLines)
    }
    $indexText = Get-Content -LiteralPath $index -Raw -Encoding UTF8
    $indexRefs = @([regex]::Matches($indexText, '(?:facts/[A-Za-z0-9._-]+\.md|state/current\.md)') | ForEach-Object { $_.Value } | Sort-Object -Unique)
}

# ---------- 3. facts ----------
Write-Output ''
Write-Output '[3] facts/'
$factFiles = @()
if (-not (Test-Path -LiteralPath $factsDir)) {
    Add-Issue 'facts/ directory is missing'
    Write-Output '    MISSING'
} else {
    $factFiles = @(Get-ChildItem -LiteralPath $factsDir -Filter '*.md' -File | Sort-Object Name)
    $totalBytes = 0
    Write-Output ("    count: {0}   (cap {1})" -f $factFiles.Count, $FactsMax)
    if ($factFiles.Count -gt $FactsMax) {
        Add-Issue ("{0} fact files, over the {1}-file cap - consolidate" -f $factFiles.Count, $FactsMax)
    }
    Write-Output ''
    Write-Output '    id                              lines  bytes  updated     checks'
    foreach ($f in $factFiles) {
        $lines = Get-LineCount $f.FullName
        $bytes = Get-ByteSize $f.FullName
        $totalBytes += $bytes
        $text = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
        $notes = @()

        if ($lines -gt $FactMaxLines) {
            Add-Issue ("{0}: {1} lines, over the {2}-line cap" -f $f.Name, $lines, $FactMaxLines)
            $notes += 'OVER-CAP'
        } elseif ($lines -gt $FactWarnLines) {
            Add-Warn ("{0}: {1} lines, near the {2}-line cap" -f $f.Name, $lines, $FactMaxLines)
            $notes += 'near-cap'
        }

        if ($text -notmatch '(?m)^---\s*$') { $notes += 'no-frontmatter' }
        if ($text -notmatch '(?m)^id:\s*\S+') { $notes += 'no-id' }
        if ($text -notmatch '(?m)^type:\s*\S+') { $notes += 'no-type' }
        $updated = $null
        $m = [regex]::Match($text, '(?m)^updated:\s*(\S+)\s*$')
        if (-not $m.Success) { $notes += 'no-updated' } else { $updated = $m.Groups[1].Value }
        if ($updated -and $updated -notmatch '^\d{4}-\d{2}-\d{2}$') { $notes += 'bad-date' }

        $expectedId = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $im = [regex]::Match($text, '(?m)^id:\s*(\S+)\s*$')
        if ($im.Success -and $im.Groups[1].Value -ne $expectedId) { $notes += 'id!=filename' }

        $rel = 'facts/' + $f.Name
        if ($indexRefs -notcontains $rel) { $notes += 'ORPHAN(not-in-INDEX)' }
        if ($notes -match 'no-frontmatter|no-id|no-type|no-updated|bad-date|id!=filename|ORPHAN') {
            foreach ($n in $notes) {
                if ($n -like 'ORPHAN*') { Add-Issue ("{0}: not referenced by INDEX.md" -f $f.Name) }
                elseif ($n -eq 'OVER-CAP') { }
                elseif ($n -eq 'near-cap') { }
                else { Add-Issue ("{0}: {1}" -f $f.Name, $n) }
            }
        }
        if ($notes.Count -eq 0) { $notes = @('ok') }
        Write-Output ("    {0,-30} {1,5}  {2,5}  {3,-10}  {4}" -f $f.BaseName, $lines, $bytes, $updated, ($notes -join ','))
    }
    Write-Output ''
    Write-Output ("    total bytes: {0}" -f (Format-Kb $totalBytes))
}

# ---------- 4. dangling references ----------
Write-Output ''
Write-Output '[4] INDEX references'
$dangling = @()
foreach ($r in $indexRefs) {
    $p = Join-Path $memDir $r
    if (-not (Test-Path -LiteralPath $p)) { $dangling += $r }
}
if ($dangling.Count -gt 0) {
    foreach ($d in $dangling) { Add-Issue ("INDEX.md points at a missing file: {0}" -f $d) }
    Write-Output ("    DANGLING: {0}" -f ($dangling -join ', '))
} else {
    Write-Output ("    {0} reference(s), all resolve" -f $indexRefs.Count)
}

# ---------- 5. spec + state ----------
Write-Output ''
Write-Output '[5] spec and state'
$rl = Get-LineCount $readme
$sl = Get-LineCount $state
Write-Output ("    README.md (spec) : {0} lines (cap {1})" -f $rl, $ReadmeMaxLines)
if ($rl -gt $ReadmeMaxLines) { Add-Warn ("README.md spec is {0} lines" -f $rl) }
if (-not (Test-Path -LiteralPath $state)) {
    Add-Warn 'state/current.md is missing - no cross-session progress anchor'
    Write-Output '    state/current.md : MISSING'
} else {
    Write-Output ("    state/current.md : {0} lines (cap {1})" -f $sl, $StateMaxLines)
    if ($sl -gt $StateMaxLines) { Add-Issue ("state/current.md is {0} lines, over the {1}-line cap" -f $sl, $StateMaxLines) }
}

# ---------- summary ----------
Write-Output ''
Write-Output '=== summary ==='
if ($script:warns.Count -gt 0) {
    Write-Output ("warnings ({0}):" -f $script:warns.Count)
    foreach ($w in $script:warns) { Write-Output ("  ! {0}" -f $w) }
}
if ($script:issues.Count -gt 0) {
    Write-Output ("issues ({0}) - compaction required:" -f $script:issues.Count)
    foreach ($i in $script:issues) { Write-Output ("  x {0}" -f $i) }
    Write-Output ''
    Write-Output 'next: follow .dsh/memory/README.md section 4 (merge / distill / archive / report).'
    if ($Action -eq 'check') { exit 1 }
} else {
    Write-Output 'OK - within all budgets. No compaction needed.'
}
exit 0
