<#
.SYNOPSIS
    Run the CoffeeBean EditMode test suite locally, in Unity batch mode.

.DESCRIPTION
    Every module repo is only a UPM package, not a Unity project, so tests must run
    inside a consuming project. This script defaults to dev/, which references all
    modules via file: paths and lists every package under testables.

    Two deliberate choices, both learned the hard way:

    1. Start-Process + Wait-Process instead of `& Unity.exe`.
       Unity.exe is a GUI-subsystem binary: `&` returns immediately, so you get neither
       an exit code nor a results file.

    2. This file is intentionally ASCII-only, with no BOM.
       Windows PowerShell 5.1 reads BOM-less files as ANSI and mangles non-ASCII text,
       which breaks parsing. Keeping it ASCII removes the dependency on file encoding
       entirely -- do NOT reintroduce non-ASCII characters here.

.PARAMETER Assembly
    Only run the given test assembly (e.g. CoffeeBean.Build.Tests). Omit for all EditMode.

.PARAMETER UnityPath
    Path to Unity.exe. Auto-detected from common install locations when omitted.

.PARAMETER ProjectPath
    Consuming Unity project. Defaults to dev/.

.EXAMPLE
    pwsh -File scripts/run-editmode-tests.ps1
    pwsh -File scripts/run-editmode-tests.ps1 -Assembly CoffeeBean.Build.Tests
#>
[CmdletBinding()]
param(
    [string]$Assembly,
    [string]$UnityPath,
    [string]$ProjectPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $ProjectPath) { $ProjectPath = Join-Path $repoRoot 'dev' }

if (-not (Test-Path $ProjectPath)) {
    Write-Error "Consuming project not found: $ProjectPath (in CI this should be the checked-out dev/; if packages/ is empty, clone the module repos into it first)"
}

if (-not $UnityPath) {
    $candidates = @(
        'D:\DevTools\UnityVersion\Unity_6000.0.71f1\Editor\Unity.exe',
        'C:\Program Files\Unity\Hub\Editor\6000.0.71f1\Editor\Unity.exe'
    ) + (Get-ChildItem 'C:\Program Files\Unity\Hub\Editor', 'D:\Unity\Hub\Editor' -Directory -ErrorAction SilentlyContinue |
         ForEach-Object { Join-Path $_.FullName 'Editor\Unity.exe' })
    $UnityPath = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}
if (-not $UnityPath) { Write-Error 'Unity.exe not found; pass -UnityPath.' }

$resultDir = Join-Path $ProjectPath 'TestResults'
New-Item -ItemType Directory -Force -Path $resultDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$xml   = Join-Path $resultDir "editmode-$stamp.xml"
$log   = Join-Path $resultDir "editmode-$stamp.log"

$unityArgs = @('-batchmode', '-nographics', '-projectPath', $ProjectPath,
               '-runTests', '-testPlatform', 'EditMode',
               '-testResults', $xml, '-logFile', $log)
if ($Assembly) { $unityArgs += @('-assemblyNames', $Assembly) }

Write-Host "Unity   : $UnityPath"
Write-Host "Project : $ProjectPath"
Write-Host "Filter  : $(if ($Assembly) { $Assembly } else { '(all EditMode)' })"
Write-Host 'Running...'

$proc = Start-Process -FilePath $UnityPath -PassThru -ArgumentList $unityArgs
Wait-Process -Id $proc.Id -Timeout 2400
Start-Sleep -Seconds 2

if (-not (Test-Path $xml)) {
    Write-Host ''
    Write-Host 'No results file produced -- usually a script compilation failure:' -ForegroundColor Red
    Select-String -Path $log -Pattern 'error CS|Tundra build failed' -ErrorAction SilentlyContinue |
        Select-Object -First 20 | ForEach-Object { Write-Host ('  ' + $_.Line.Trim()) }
    exit 1
}

# Read the results file with an EXPLICIT UTF-8 decoder.
# Unity's NUnit result XML has no BOM, and Windows PowerShell 5.1 decodes BOM-less
# files as ANSI -- so Get-Content turns the Chinese text inside <message>/<output>
# CDATA into garbage and can even break the XML structure itself. That failure mode
# looks like a test-runner error ("start tag 'message' does not match end tag 'output'")
# while every test actually passed, so never go back to Get-Content here.
[xml]$doc = [System.IO.File]::ReadAllText($xml, [System.Text.Encoding]::UTF8)
$run = $doc.'test-run'
Write-Host ''
Write-Host ("TOTAL={0} PASSED={1} FAILED={2} SKIPPED={3} RESULT={4}" -f `
    $run.total, $run.passed, $run.failed, $run.skipped, $run.result)

# Only Failed/Error may fail the run.
# Skipped (Assert.Ignore) is an intentional outcome -- e.g. a test whose precondition
# only holds in a project that has NOT installed a given optional package. Treating it
# as a failure (the old `-ne 'Passed'` filter) made every run red once any skip existed,
# which trains people to ignore the exit code.
$failed = $doc.SelectNodes('//test-case') | Where-Object { $_.result -eq 'Failed' -or $_.result -eq 'Error' }
$skipped = $doc.SelectNodes('//test-case') | Where-Object { $_.result -eq 'Skipped' }

if ($skipped) {
    Write-Host ''
    $skipped | ForEach-Object { Write-Host ("SKIPPED: " + $_.fullname) -ForegroundColor Yellow }
}

if ($failed) {
    Write-Host ''
    $failed | ForEach-Object { Write-Host ("FAILED: " + $_.fullname) -ForegroundColor Red }
    Write-Host "Results: $xml"
    exit 1
}

Write-Host 'All green.' -ForegroundColor Green
Write-Host "Results: $xml"
exit 0
