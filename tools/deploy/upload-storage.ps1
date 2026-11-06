#Requires -Version 5.1
<#
.SYNOPSIS
    把发布产物从 IIS 服务器上传到 RainS3。

.DESCRIPTION
    GitHub 的 runner 直连 RainS3 跨境只有约 100 B/s，构建产物传不完。
    改由 runner 先 SCP 到服务器，再由服务器执行本脚本上传；runner 到服务器的
    链路是通的（API / 官网部署一直走 SCP）。

    由 release.yml 的 upload-storage 作业调用，也可以在服务器上手动执行。

    流程：解压 → 复用或安装 AWS CLI → 读取凭据 → 逐文件上传
          → 无论成功失败，删除临时目录、安装包、产物包与凭据文件。

.PARAMETER ZipPath
    产物包路径。

.PARAMETER Tag
    发布标签，例如 v2.7.2。

.PARAMETER InstallerPath
    AWS CLI 安装包路径；服务器上已有 aws.exe 时忽略。

.PARAMETER CredentialsPath
    包含 AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY 的凭据文件。

.PARAMETER EndpointUrl
    RainS3 的 S3 端点。

.PARAMETER Bucket
    目标桶。

.EXAMPLE
    .\upload-storage.ps1 -ZipPath C:\Users\Administrator\raillog-assets.zip -Tag v2.7.2
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ZipPath,

    [Parameter(Mandatory = $true)]
    [string]$Tag,

    [string]$InstallerPath = 'C:\Users\Administrator\AWSCLIV2.msi',

    [string]$CredentialsPath = 'C:\Users\Administrator\s3-upload.env',

    [string]$EndpointUrl = 'https://cn-nb2.rains3.com',

    [string]$Bucket = 'raillog'
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

function Find-AwsCli {
    $command = Get-Command aws.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }
    $default = Join-Path $env:ProgramFiles 'Amazon\AWSCLIV2\aws.exe'
    if (Test-Path -LiteralPath $default) {
        return $default
    }
    return $null
}

function Install-AwsCli {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "AWS CLI 安装包不存在：$Path"
    }

    Write-Step '安装 AWS CLI'
    $process = Start-Process -FilePath msiexec.exe `
        -ArgumentList @('/i', "`"$Path`"", '/qn', '/norestart') `
        -Wait -PassThru
    if ($process.ExitCode -notin @(0, 3010)) {
        throw "AWS CLI 安装失败，退出码 $($process.ExitCode)"
    }

    $aws = Find-AwsCli
    if (-not $aws) {
        throw 'AWS CLI 安装后仍找不到 aws.exe'
    }
    return $aws
}

function Read-Credentials {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "凭据文件不存在：$Path"
    }

    $values = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) {
            continue
        }
        $index = $trimmed.IndexOf('=')
        if ($index -le 0) {
            continue
        }
        $values[$trimmed.Substring(0, $index).Trim()] = $trimmed.Substring($index + 1)
    }

    if (-not $values['AWS_ACCESS_KEY_ID'] -or -not $values['AWS_SECRET_ACCESS_KEY']) {
        throw "凭据文件缺少 AWS_ACCESS_KEY_ID 或 AWS_SECRET_ACCESS_KEY：$Path"
    }
    return $values
}

$work = Join-Path $env:TEMP "raillog-upload-$Tag"

try {
    if ($Tag -notmatch '^[A-Za-z0-9._-]+$') {
        throw "标签包含不允许的字符：$Tag"
    }
    if (-not (Test-Path -LiteralPath $ZipPath)) {
        throw "产物包不存在：$ZipPath"
    }

    Write-Step "产物包：$ZipPath"
    Write-Step "目标：s3://$Bucket/$Tag/"

    if (Test-Path -LiteralPath $work) {
        Remove-Item -LiteralPath $work -Recurse -Force
    }
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $work -Force

    $aws = Find-AwsCli
    if (-not $aws) {
        $aws = Install-AwsCli -Path $InstallerPath
    }
    Write-Step "AWS CLI：$aws"

    $credentials = Read-Credentials -Path $CredentialsPath
    $env:AWS_ACCESS_KEY_ID = $credentials['AWS_ACCESS_KEY_ID']
    $env:AWS_SECRET_ACCESS_KEY = $credentials['AWS_SECRET_ACCESS_KEY']
    $env:AWS_DEFAULT_REGION = 'cn-nb2'
    $env:AWS_EC2_METADATA_DISABLED = 'true'

    $files = @(Get-ChildItem -LiteralPath $work -Recurse -File)
    if ($files.Count -eq 0) {
        throw "产物包里没有文件：$ZipPath"
    }

    foreach ($file in $files) {
        $key = $file.FullName.Substring($work.Length).TrimStart('\', '/').Replace('\', '/')
        $destination = "s3://$Bucket/$Tag/$key"
        Write-Step "上传 $key（$([math]::Round($file.Length / 1MB, 1)) MB）"
        & $aws s3 cp $file.FullName $destination `
            --endpoint-url $EndpointUrl `
            --cache-control 'public, max-age=31536000, immutable' `
            --no-progress
        if ($LASTEXITCODE -ne 0) {
            throw "上传失败：$key（aws 退出码 $LASTEXITCODE）"
        }
    }

    Write-Step "上传完成：$($files.Count) 个文件"
}
finally {
    if (Test-Path -LiteralPath $work) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
    foreach ($path in @($ZipPath, $InstallerPath, $CredentialsPath)) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
}
