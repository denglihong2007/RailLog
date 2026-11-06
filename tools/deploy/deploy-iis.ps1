#Requires -Version 5.1
<#
.SYNOPSIS
    把发布包部署到 IIS 站点目录，保留 web.config 与运行期数据。

.DESCRIPTION
    由 GitHub Actions 的 release.yml 调用，也可以在服务器上手动执行。
    按 -Profile 选择站点：

      api  C:\wwwroot\RailLog.API   ASP.NET Core，部署时停应用池
      web  C:\wwwroot\RailLog       纯静态站点，不停应用池

    流程：解压 → （按需停止应用池）→ robocopy 覆盖 → （按需启动应用池）
          → 校验 web.config 未被改动 → 健康探测。

    不做镜像同步（不使用 /MIR 或 /PURGE），站点目录里其它文件保持原样。

.PARAMETER ZipPath
    发布包路径。

.PARAMETER Profile
    站点配置：api 或 web。

.PARAMETER DryRun
    只列出将要复制的文件，不停止应用池，也不写入任何文件。

.EXAMPLE
    .\deploy-iis.ps1 -ZipPath C:\Users\Administrator\raillog-api.zip -Profile api -DryRun

.EXAMPLE
    .\deploy-iis.ps1 -ZipPath C:\Users\Administrator\raillog-web.zip -Profile web
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ZipPath,

    [Parameter(Mandatory = $true)]
    [ValidateSet('api', 'web')]
    [string]$Profile,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 通过 SSH 调用时没有交互式控制台，进度条会抛 Win32 内部错误。
$ProgressPreference = 'SilentlyContinue'

# GitHub Actions 的日志按 UTF-8 显示，服务器控制台默认是 GBK，不转码的话日志会乱码。
try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
}
catch {
}

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message"
}

# 应用池刚停止后立刻启动，偶尔会撞上 W3SVC 的状态切换，报
# 0x80070425「服务无法接受控制消息」；等一两秒重试即可。
function Start-AppPoolWithRetry {
    param(
        [string]$Name,
        [int]$TimeoutSeconds = 60
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ($true) {
        try {
            Start-WebAppPool -Name $Name
            return
        }
        catch {
            if ((Get-Date) -gt $deadline) {
                throw
            }
            Start-Sleep -Seconds 2
        }
    }
}

# 每个站点的部署参数。
#   ProtectedFiles/ProtectedDirectories  服务器上手工维护或运行期生成，发布包不得覆盖
#   RequireWebConfig                    站点根目录必须有 web.config 才允许部署
$Profiles = @{
    api = @{
        TargetPath           = 'C:\wwwroot\RailLog.API'
        RequiredEntry        = 'RailLog.API.dll'
        AppPool              = 'RailLog.API'
        HealthUrl            = 'https://api.raillog.top/'
        RequireWebConfig     = $true
        ProtectedFiles       = @(
            'web.config'          # 环境变量与机密都在这里
            'raillog.db'
            'raillog.db-shm'
            'raillog.db-wal'
            'train_timetables.db'
        )
        ProtectedDirectories = @(
            'backups'
            'timetables'
            'logs'
        )
    }
    web = @{
        TargetPath           = 'C:\wwwroot\RailLog'
        RequiredEntry        = 'index.html'
        AppPool              = ''
        HealthUrl            = 'https://www.raillog.top/'
        RequireWebConfig     = $false
        ProtectedFiles       = @('web.config')
        ProtectedDirectories = @()
    }
}

$site = $Profiles[$Profile]
$TargetPath = $site.TargetPath
$AppPool = $site.AppPool
$HealthUrl = $site.HealthUrl
$ProtectedFiles = @($site.ProtectedFiles)
$ProtectedDirectories = @($site.ProtectedDirectories)

Write-Step "站点配置：$Profile（$TargetPath）"
Write-Step "发布包：$ZipPath"
if ($AppPool) {
    Write-Step "应用池：$AppPool"
}

if (-not (Test-Path -LiteralPath $ZipPath)) {
    throw "找不到发布包：$ZipPath"
}

if (-not (Test-Path -LiteralPath $TargetPath)) {
    throw "找不到站点目录：$TargetPath"
}

$liveWebConfig = Join-Path $TargetPath 'web.config'
$hasWebConfig = Test-Path -LiteralPath $liveWebConfig
if ($site.RequireWebConfig -and -not $hasWebConfig) {
    throw "站点目录里没有 web.config，拒绝部署：$liveWebConfig"
}

$webConfigHashBefore = $null
if ($hasWebConfig) {
    $webConfigHashBefore = (Get-FileHash -LiteralPath $liveWebConfig -Algorithm SHA256).Hash
}

$staging = Join-Path ([System.IO.Path]::GetTempPath()) "raillog-deploy-$Profile"
if (Test-Path -LiteralPath $staging) {
    Remove-Item -LiteralPath $staging -Recurse -Force
}

# 只有真的停过应用池，结束时才需要把它拉起来
$poolStopped = $false

try {
    Write-Step '解压发布包'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $staging)

    $entry = Join-Path $staging $site.RequiredEntry
    if (-not (Test-Path -LiteralPath $entry)) {
        throw "发布包里没有 $($site.RequiredEntry)，疑似打包错误：$ZipPath"
    }

    # 双保险：CI 已经删掉了发布包里的 web.config，这里再兜一次底
    $stagedWebConfig = Join-Path $staging 'web.config'
    if (Test-Path -LiteralPath $stagedWebConfig) {
        Remove-Item -LiteralPath $stagedWebConfig -Force
    }

    if (-not $DryRun -and $AppPool) {
        Write-Step "停止应用池 $AppPool"
        Stop-WebAppPool -Name $AppPool
        $poolStopped = $true

        $deadline = (Get-Date).AddSeconds(30)
        while ((Get-WebAppPoolState -Name $AppPool).Value -ne 'Stopped') {
            if ((Get-Date) -gt $deadline) {
                throw "应用池 $AppPool 在 30 秒内没有停止，放弃部署"
            }
            Start-Sleep -Milliseconds 500
        }
    }

    Write-Step '复制文件'
    $robocopyArgs = @(
        $staging
        $TargetPath
        '/E'
        '/R:2'
        '/W:2'
        '/NP'
    )
    if ($ProtectedFiles.Count -gt 0) {
        $robocopyArgs += '/XF'
        $robocopyArgs += $ProtectedFiles
    }
    if ($ProtectedDirectories.Count -gt 0) {
        $robocopyArgs += '/XD'
        $robocopyArgs += $ProtectedDirectories
    }
    if ($DryRun) {
        $robocopyArgs += '/L'
    }

    & robocopy @robocopyArgs
    $robocopyExitCode = $LASTEXITCODE
    Write-Step "robocopy 退出码 $robocopyExitCode（0-7 表示成功）"
    if ($robocopyExitCode -ge 8) {
        throw "robocopy 复制失败，退出码 $robocopyExitCode"
    }
}
finally {
    if ($poolStopped) {
        Write-Step "启动应用池 $AppPool"
        Start-AppPoolWithRetry -Name $AppPool
    }
}

if ($DryRun) {
    Write-Step 'DryRun 结束，未修改任何文件'
    return
}

if ($hasWebConfig) {
    $webConfigHashAfter = (Get-FileHash -LiteralPath $liveWebConfig -Algorithm SHA256).Hash
    if ($webConfigHashAfter -ne $webConfigHashBefore) {
        throw "web.config 在部署过程中被修改了（$webConfigHashBefore -> $webConfigHashAfter）"
    }
    Write-Step 'web.config 未被改动'
}
else {
    Write-Step '站点没有 web.config，跳过校验'
}

if ($AppPool) {
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-WebAppPoolState -Name $AppPool).Value -ne 'Started') {
        if ((Get-Date) -gt $deadline) {
            throw "应用池 $AppPool 在 30 秒内没有启动"
        }
        Start-Sleep -Milliseconds 500
    }
}

if ([string]::IsNullOrWhiteSpace($HealthUrl)) {
    Write-Step '跳过健康探测'
    return
}

Write-Step "健康探测 $HealthUrl"
Start-Sleep -Seconds 3

$statusCode = $null
try {
    $response = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
    $statusCode = [int]$response.StatusCode
}
catch {
    if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) {
        # 404 之类的正常业务响应也会让 Invoke-WebRequest 抛异常
        $statusCode = [int]$_.Exception.Response.StatusCode
    }
    else {
        throw "健康探测请求失败：$($_.Exception.Message)"
    }
}

Write-Step "健康探测返回 $statusCode"
if ($statusCode -ge 500) {
    throw "健康探测返回 $statusCode，应用可能没有正常启动"
}

Write-Step '部署完成'
