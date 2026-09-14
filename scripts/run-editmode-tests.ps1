<#
.SYNOPSIS
    在本地以批处理模式跑 CoffeeBean 的 EditMode 测试（等价于 CI 里要做的事）。

.DESCRIPTION
    框架的每个模块仓库都只是"包"，本身不是 Unity 工程，所以测试必须在一个
    消费工程里跑 —— 本脚本默认用 dev/（它通过 file: 引用 packages/ 下全部模块，
    且 manifest 的 testables 已登记所有包）。

    之所以做成脚本：这套参数（-batchmode -runTests -testPlatform EditMode -testResults）
    在开发中被反复手敲，容易记错；而且 Unity.exe 是 GUI 子系统程序，
    PowerShell 里 `& Unity.exe` 会**立即返回**、不等待，必须用 Start-Process + Wait-Process。

.PARAMETER Assembly
    只跑指定测试程序集（如 CoffeeBean.Build.Tests）。省略则跑全部 EditMode 测试。

.PARAMETER UnityPath
    Unity.exe 路径。省略则按常见安装位置自动探测。

.PARAMETER ProjectPath
    消费工程路径。默认 dev/。

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
    Write-Error "消费工程不存在：$ProjectPath（dev/ 是本地联调工程，未入库；请先按 README 准备）"
}

if (-not $UnityPath) {
    $candidates = @(
        'D:\DevTools\UnityVersion\Unity_6000.0.71f1\Editor\Unity.exe',
        'C:\Program Files\Unity\Hub\Editor\6000.0.71f1\Editor\Unity.exe'
    ) + (Get-ChildItem 'C:\Program Files\Unity\Hub\Editor', 'D:\Unity\Hub\Editor' -Directory -ErrorAction SilentlyContinue |
         ForEach-Object { Join-Path $_.FullName 'Editor\Unity.exe' })
    $UnityPath = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}
if (-not $UnityPath) { Write-Error '未找到 Unity.exe，请用 -UnityPath 指定。' }

$resultDir = Join-Path $ProjectPath 'TestResults'
New-Item -ItemType Directory -Force -Path $resultDir | Out-Null
$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$xml    = Join-Path $resultDir "editmode-$stamp.xml"
$log    = Join-Path $resultDir "editmode-$stamp.log"

$args = @('-batchmode', '-nographics', '-projectPath', $ProjectPath,
          '-runTests', '-testPlatform', 'EditMode',
          '-testResults', $xml, '-logFile', $log)
if ($Assembly) { $args += @('-assemblyNames', $Assembly) }

Write-Host "Unity   : $UnityPath"
Write-Host "Project : $ProjectPath"
Write-Host "Filter  : $(if ($Assembly) { $Assembly } else { '(all EditMode)' })"
Write-Host 'Running...'

# 必须 Start-Process + Wait-Process：Unity.exe 是 GUI 子系统程序，
# 用 & 调用会立即返回，拿不到退出码也等不到测试结果。
$proc = Start-Process -FilePath $UnityPath -PassThru -ArgumentList $args
Wait-Process -Id $proc.Id -Timeout 2400
Start-Sleep -Seconds 2

if (-not (Test-Path $xml)) {
    Write-Host ''
    Write-Host '没有产出测试结果文件 —— 通常是脚本编译失败：' -ForegroundColor Red
    Select-String -Path $log -Pattern 'error CS|Tundra build failed' -ErrorAction SilentlyContinue |
        Select-Object -First 20 | ForEach-Object { Write-Host ('  ' + $_.Line.Trim()) }
    exit 1
}

[xml]$doc = Get-Content $xml -Raw
$run = $doc.'test-run'
Write-Host ''
Write-Host ("TOTAL={0} PASSED={1} FAILED={2} SKIPPED={3} RESULT={4}" -f `
    $run.total, $run.passed, $run.failed, $run.skipped, $run.result)

$failed = $doc.SelectNodes('//test-case') | Where-Object { $_.result -ne 'Passed' }
if ($failed) {
    Write-Host ''
    $failed | ForEach-Object { Write-Host ("FAILED: " + $_.fullname) -ForegroundColor Red }
    Write-Host "结果文件: $xml"
    exit 1
}

Write-Host 'All green.' -ForegroundColor Green
Write-Host "结果文件: $xml"
exit 0
