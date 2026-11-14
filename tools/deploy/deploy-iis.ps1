#Requires -Version 5.1
<#
.SYNOPSIS
    把发布包部署到 IIS 站点目录，保留 web.config 与运行期数据。

.DESCRIPTION
    由 GitHub Actions 调用（release.yml / deploy-api.yml），也可以在服务器上手动执行。
    构建产物由 runner 直接给出，不再经过 SCP；-ZipPath 保留给手动部署。
    按 -Profile 选择站点：

      api  C:\wwwroot\RailLog.API   ASP.NET Core，部署时停应用池
      web  C:\wwwroot\RailLog       纯静态站点，不停应用池

    流程：解压/定位产物 → （按需停止应用池）→ robocopy 覆盖 → （按需启动应用池）
          → 校验 web.config 未被改动 → 健康探测。

    不做镜像同步（不使用 /MIR 或 /PURGE），站点目录里其它文件保持原样。

.PARAMETER ZipPath
    发布包路径。与 -SourceDirectory 二选一。

.PARAMETER SourceDirectory
    已经解开的发布包目录（CI 里就是 download-artifact 落地的目录）。
    与 -ZipPath 二选一，省掉一次压缩再解压。

.PARAMETER Profile
    站点配置：api 或 web。

.PARAMETER DryRun
    只列出将要复制的文件，不停止应用池，也不写入任何文件。

.EXAMPLE
    .\deploy-iis.ps1 -SourceDirectory C:\actions-runner\_work\RailLog\RailLog\dist\api -Profile api

.EXAMPLE
    .\deploy-iis.ps1 -ZipPath C:\Users\Administrator\raillog-api.zip -Profile api -DryRun
#>
[CmdletBinding(DefaultParameterSetName = 'Zip')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Zip')]
    [string]$ZipPath,

    [Parameter(Mandatory = $true, ParameterSetName = 'Directory')]
    [string]$SourceDirectory,

    [Parameter(Mandatory = $true)]
    [ValidateSet('api', 'web')]
    [string]$Profile,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 由 CI 或 SSH 调用时没有交互式控制台，进度条会抛 Win32 内部错误。
$ProgressPreference = 'SilentlyContinue'

# GitHub Actions 的日志按 UTF-8 显示，服务器控制台默认是 GBK，不转码的话日志会乱码。
try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
}
catch {
}

$fromZip = $PSCmdlet.ParameterSetName -eq 'Zip'

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
if ($fromZip) {
    Write-Step "发布包：$ZipPath"
}
else {
    Write-Step "发布源：$SourceDirectory"
}
if ($AppPool) {
    Write-Step "应用池：$AppPool"
}

if ($fromZip) {
    if (-not (Test-Path -LiteralPath $ZipPath)) {
        throw "找不到发布包：$ZipPath"
    }
}
else {
    if (-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)) {
        throw "找不到发布目录：$SourceDirectory"
    }
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

# 只有从 zip 部署时才自己准备临时目录；目录模式的发布源归调用方（CI 的工作区）所有
$ownStaging = $false
if ($fromZip) {
    $staging = Join-Path ([System.IO.Path]::GetTempPath()) "raillog-deploy-$Profile"
    $ownStaging = $true
    if (Test-Path -LiteralPath $staging) {
        Remove-Item -LiteralPath $staging -Recurse -Force
    }
}
else {
    $staging = (Resolve-Path -LiteralPath $SourceDirectory).ProviderPath
}

# 只有真的停过应用池，结束时才需要把它拉起来
$poolStopped = $false

try {
    if ($fromZip) {
        Write-Step '解压发布包'
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $staging)
    }
    else {
        Write-Step '使用现成的发布目录，跳过解压'
    }

    $entry = Join-Path $staging $site.RequiredEntry
    if (-not (Test-Path -LiteralPath $entry)) {
        throw "发布内容里没有 $($site.RequiredEntry)，疑似打包错误：$staging"
    }

    # 双保险：CI 已经删掉了发布包里的 web.config，这里再兜一次底
    $stagedWebConfig = Join-Path $staging 'web.config'
    if (Test-Path -LiteralPath $stagedWebConfig) {
        Remove-Item -LiteralPath $stagedWebConfig -Force
    }

    if (-not $DryRun -and $AppPool) {
        # 应用池可能因为上一次部署失败已经处于 Stopped；此时再调
        # Stop-WebAppPool 会抛「目标路径上的对象已停止」，整个部署直接中断。
        if ((Get-WebAppPoolState -Name $AppPool).Value -ne 'Stopped') {
            Write-Step "停止应用池 $AppPool"
            Stop-WebAppPool -Name $AppPool
        }
        else {
            Write-Step "应用池 $AppPool 已经是停止状态"
        }
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
    if ($ownStaging -and (Test-Path -LiteralPath $staging)) {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
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
