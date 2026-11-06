param(
    [string]$Task = "assembleHap",
    [string]$Module = "entry",
    [string]$Product = "default",
    [string]$HvigorPath = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

Write-Host "==> 项目目录: $Root" -ForegroundColor Cyan
Write-Host "==> 构建任务: $Task (module=$Module, product=$Product)" -ForegroundColor Cyan

$Hvigor = ""

# 1) 显式指定
if ($HvigorPath -ne "" -and (Test-Path $HvigorPath)) {
    $Hvigor = $HvigorPath
}

# 2) DevEco Studio 自带
if ($Hvigor -eq "") {
    $paths = @()
    if ($env:DEVECO_HOME) {
        $paths += ($env:DEVECO_HOME + "\tools\hvigor\bin\hvigorw.bat")
    }
    $paths += "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat"
    if ($env:LOCALAPPDATA) {
        $paths += ($env:LOCALAPPDATA + "\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat")
    }
    if ($env:USERPROFILE) {
        $paths += ($env:USERPROFILE + "\AppData\Local\Programs\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat")
    }
    foreach ($item in $paths) {
        if (Test-Path $item) {
            $Hvigor = $item
            break
        }
    }
}

# 3) 项目内 wrapper
if (($Hvigor -eq "") -and (Test-Path ($Root + "\hvigor\hvigor-wrapper.js"))) {
    Write-Host "==> 使用项目内 hvigor wrapper" -ForegroundColor Cyan
    & node ($Root + "\hvigor\hvigor-wrapper.js") $Task --mode module -p ("product=" + $Product) -p ("module=" + $Module + "@default") --no-daemon
    exit $LASTEXITCODE
}

# 4) PATH 中的 hvigorw 不做自动探测：本项目根目录的 hvigorw.bat 会被 PATH 命中，容易递归。

if ($Hvigor -eq "") {
    Write-Host ""
    Write-Host "未找到 hvigor 构建工具。" -ForegroundColor Red
    Write-Host ""
    Write-Host "本机没有检测到 DevEco Studio 自带的 hvigor，也没有项目内的 hvigor wrapper。"
    Write-Host "这通常意味着当前机器未安装 DevEco Studio，因此无法在本机实际编译 HAP。"
    Write-Host ""
    Write-Host "可选做法："
    Write-Host "  1. 安装 DevEco Studio 5.0（API 12）后，用 DevEco 打开 harmony 目录并等待 Sync 完成；"
    Write-Host "     本脚本会自动发现 DevEco 自带的 hvigor。"
    Write-Host "  2. 或显式传入路径："
    Write-Host "     powershell -ExecutionPolicy Bypass -File scripts\build.ps1 -HvigorPath C:\path\to\hvigorw.bat"
    Write-Host "  3. 或把 DevEco 生成的 hvigorw / hvigorw.bat / hvigor/hvigor-wrapper.js 放回项目根目录，"
    Write-Host "     再执行 hvigorw assembleHap。"
    Write-Host ""
    Write-Host "源码与工程结构已完整交付，缺少的只是本机的鸿蒙构建工具链。"
    Write-Host ""
    exit 1
}

Write-Host "==> 使用 hvigor: $Hvigor" -ForegroundColor Cyan
& $Hvigor $Task --mode module -p ("product=" + $Product) -p ("module=" + $Module + "@default") --no-daemon
$code = $LASTEXITCODE
if ($code -ne 0) {
    Write-Host ""
    Write-Host "构建失败（hvigor 退出码 $code）。请查看上方 hvigor 输出。" -ForegroundColor Red
    exit $code
}
Write-Host "==> 构建完成。HAP 通常位于 entry/build/default/outputs/default/" -ForegroundColor Cyan
