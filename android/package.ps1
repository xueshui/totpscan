# 一键构建脚本（Windows / PowerShell）
#
#   .\package.ps1                 # 构建 SDK（AAR + POM）和 App（APK）
#   .\package.ps1 -Target sdk     # 只构建 SDK
#   .\package.ps1 -Target app     # 只构建 App
#
# 产物统一复制到 android\dist\。
param(
    [ValidateSet("all", "sdk", "app")]
    [string]$Target = "all",
    [switch]$Offline
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$dist = Join-Path $root "dist"

function Resolve-JavaHome {
    if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME "bin\java.exe"))) {
        return $env:JAVA_HOME
    }
    $candidates = @(
        "C:\Program Files\Android\openjdk\jdk-21.0.8",
        "C:\Program Files\Android\Android Studio\jbr"
    )
    foreach ($path in $candidates) {
        if (Test-Path (Join-Path $path "bin\java.exe")) { return $path }
    }
    throw "未找到 JDK 17+。请设置 JAVA_HOME 环境变量后重试。"
}

function Resolve-Gradle {
    if ($env:GRADLE_CMD -and (Test-Path $env:GRADLE_CMD)) { return $env:GRADLE_CMD }
    $cmd = Get-Command gradle -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        (Join-Path $env:USERPROFILE "gradle-dist\gradle-8.11.1\bin\gradle.bat"),
        "C:\Gradle\gradle-8.11.1\bin\gradle.bat"
    )
    foreach ($path in $candidates) {
        if (Test-Path $path) { return $path }
    }
    throw "未找到 Gradle。请把 gradle 加入 PATH，或设置 GRADLE_CMD 指向 gradle.bat。"
}

$env:JAVA_HOME = Resolve-JavaHome
$gradle = Resolve-Gradle

$tasks = @()
if ($Target -eq "all" -or $Target -eq "sdk") {
    $tasks += ":sdk:assembleRelease"
    $tasks += ":sdk:publishReleasePublicationToMavenLocal"
}
if ($Target -eq "all" -or $Target -eq "app") {
    $tasks += ":app:assembleRelease"
    $tasks += ":app:assembleDebug"
}

$gradleArgs = @("-p", $root, "--console=plain") + $tasks
if ($Offline) { $gradleArgs += "--offline" }

Write-Host "JAVA_HOME = $env:JAVA_HOME"
Write-Host "Gradle    = $gradle"
Write-Host "任务      = $($tasks -join ', ')"
& $gradle @gradleArgs
if ($LASTEXITCODE -ne 0) { throw "Gradle 构建失败（exit=$LASTEXITCODE）" }

New-Item -ItemType Directory -Force -Path $dist | Out-Null

# 读取发布坐标
$group = "com.scanauth"
$artifact = "scan-totp-sdk"
$version = "1.0.0"
$props = Get-Content (Join-Path $root "gradle.properties")
foreach ($line in $props) {
    if ($line -match "^scanTotp\.group=(.+)$") { $group = $Matches[1].Trim() }
    if ($line -match "^scanTotp\.artifact=(.+)$") { $artifact = $Matches[1].Trim() }
    if ($line -match "^scanTotp\.version=(.+)$") { $version = $Matches[1].Trim() }
}

# APK 文件名跟随 App 版本号（与 SDK 版本相互独立）
$appVersion = $version
$appBuildFile = Join-Path $root "app\build.gradle.kts"
if (Test-Path $appBuildFile) {
    foreach ($line in (Get-Content $appBuildFile)) {
        if ($line -match 'versionName\s*=\s*"([^"]+)"') { $appVersion = $Matches[1]; break }
    }
}

if ($Target -eq "all" -or $Target -eq "sdk") {
    $aar = Join-Path $root "sdk\build\outputs\aar\sdk-release.aar"
    if (Test-Path $aar) {
        Copy-Item $aar (Join-Path $dist "$artifact-$version.aar") -Force
        Write-Host "AAR  -> $(Join-Path $dist "$artifact-$version.aar")"
    }
    $m2 = Join-Path $env:USERPROFILE ".m2\repository\$($group -replace '\.','\')\$artifact\$version"
    foreach ($name in @("$artifact-$version.pom", "$artifact-$version-sources.jar", "$artifact-$version.module")) {
        $file = Join-Path $m2 $name
        if (Test-Path $file) {
            Copy-Item $file (Join-Path $dist $name) -Force
            Write-Host "Maven-> $(Join-Path $dist $name)"
        }
    }
}

if ($Target -eq "all" -or $Target -eq "app") {
    $releaseDir = Join-Path $root "app\build\outputs\apk\release"

    # 只分发已签名的 Release 包；缺少签名直接失败，不退回未签名或 debug 签名
    $signed = Join-Path $releaseDir "app-release.apk"
    if (-not ((Test-Path $signed) -and ((Get-Item $signed).Length -gt 0))) {
        throw "未找到已签名的 Release APK。请先通过环境变量或 android\keystore.local.properties 配置签名材料，再执行 :app:assembleRelease。"
    }
    $out = Join-Path $dist "scan-totp-app-$appVersion-signed.apk"
    Copy-Item $signed $out -Force
    Write-Host "APK(signed) -> $out"

    # 输出校验值，便于确认传输/复制过程未损坏
    Get-ChildItem (Join-Path $dist "scan-totp-app-$appVersion-*.apk") | ForEach-Object {
        $hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()
        Write-Host ("SHA256 {0}  {1}" -f $hash, $_.Name)
    }
}

Write-Host "完成。产物目录：$dist"
