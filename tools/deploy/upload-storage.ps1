#Requires -Version 5.1
<#
.SYNOPSIS
    把发布产物上传到 RainS3。

.DESCRIPTION
    由 release.yml 的 upload-storage 作业调用，也可以在服务器上手动执行。
    该作业跑在服务器上注册的自建 runner 里，产物由 download-artifact 直接落到本机，
    不再经过 SCP；也可以手动用 -ZipPath 指定一个压缩包。

    流程：定位产物（解压或直接用目录）→ 复用 AWS CLI → 读取凭据
          → 逐文件上传（已存在且大小一致的跳过）→ 清理自己创建的临时目录。

.PARAMETER ZipPath
    产物包路径。与 -SourceDirectory 二选一。

.PARAMETER SourceDirectory
    已经解开的产物目录。与 -ZipPath 二选一。

.PARAMETER Tag
    发布标签，例如 v2.7.2。

.PARAMETER InstallerPath
    AWS CLI 安装包路径；服务器上已有 aws.exe 时忽略。

.PARAMETER CredentialsPath
    包含 AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY 的凭据文件。
    CI 里直接通过环境变量注入，不需要这个文件。

.PARAMETER EndpointUrl
    RainS3 的 S3 端点。

.PARAMETER Bucket
    目标桶。

.EXAMPLE
    .\upload-storage.ps1 -SourceDirectory C:\actions-runner\_work\RailLog\RailLog\dist -Tag v2.7.3

.EXAMPLE
    .\upload-storage.ps1 -ZipPath C:\Users\Administrator\raillog-assets.zip -Tag v2.7.2
#>
[CmdletBinding(DefaultParameterSetName = 'Zip')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Zip')]
    [string]$ZipPath,

    [Parameter(Mandatory = $true, ParameterSetName = 'Directory')]
    [string]$SourceDirectory,

    [Parameter(Mandatory = $true)]
    [string]$Tag,

    [string]$InstallerPath = '',

    [string]$CredentialsPath = '',

    [string]$EndpointUrl = 'https://cn-nb2.rains3.com',

    [string]$Bucket = 'raillog'
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
    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw '找不到 aws.exe；请先安装 AWS CLI，或用 -InstallerPath 指定 AWSCLIV2.msi'
    }
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

# 优先用环境变量（CI 从 secret 注入，不落盘），其次才是凭据文件。
function Read-Credentials {
    param([string]$Path)

    $values = @{}
    if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path)) {
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
    }

    if (-not $values['AWS_ACCESS_KEY_ID'] -and $env:AWS_ACCESS_KEY_ID) {
        $values['AWS_ACCESS_KEY_ID'] = $env:AWS_ACCESS_KEY_ID
    }
    if (-not $values['AWS_SECRET_ACCESS_KEY'] -and $env:AWS_SECRET_ACCESS_KEY) {
        $values['AWS_SECRET_ACCESS_KEY'] = $env:AWS_SECRET_ACCESS_KEY
    }

    if (-not $values['AWS_ACCESS_KEY_ID'] -or -not $values['AWS_SECRET_ACCESS_KEY']) {
        throw '缺少 AWS 凭据：设置 AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY 环境变量，或用 -CredentialsPath 指定凭据文件'
    }
    return $values
}

# 返回已存在对象的大小；不存在或查询失败时返回 $null。
# 用来让失败重跑跳过已经传完的文件，不必整轮重传。
function Get-RemoteObjectSize {
    param([string]$Key)

    # aws 查不到对象时会往 stderr 写日志并以非零退出；Stop 模式下那会被当成终止错误
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $size = & $aws s3api head-object `
            --bucket $Bucket `
            --key $Key `
            --endpoint-url $EndpointUrl `
            --query ContentLength `
            --output text 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($size)) {
            return $null
        }
        return [int64]$size
    }
    finally {
        $ErrorActionPreference = $previous
    }
}

# msiexec 不接受正斜杠路径，会报 1619「安装包打不开」；统一转成 Windows 分隔符。
if ($fromZip) {
    $ZipPath = [System.IO.Path]::GetFullPath($ZipPath)
}
if (-not [string]::IsNullOrWhiteSpace($InstallerPath)) {
    $InstallerPath = [System.IO.Path]::GetFullPath($InstallerPath)
}
if (-not [string]::IsNullOrWhiteSpace($CredentialsPath)) {
    $CredentialsPath = [System.IO.Path]::GetFullPath($CredentialsPath)
}

$work = $null
$ownWork = $false

try {
    if ($Tag -notmatch '^[A-Za-z0-9._-]+$') {
        throw "标签包含不允许的字符：$Tag"
    }

    if ($fromZip) {
        if (-not (Test-Path -LiteralPath $ZipPath)) {
            throw "产物包不存在：$ZipPath"
        }
        Write-Step "产物包：$ZipPath"
        $work = Join-Path $env:TEMP "raillog-upload-$Tag"
        $ownWork = $true
        if (Test-Path -LiteralPath $work) {
            Remove-Item -LiteralPath $work -Recurse -Force
        }
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        Expand-Archive -LiteralPath $ZipPath -DestinationPath $work -Force
    }
    else {
        if (-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)) {
            throw "产物目录不存在：$SourceDirectory"
        }
        $work = (Resolve-Path -LiteralPath $SourceDirectory).ProviderPath
        Write-Step "产物目录：$work"
    }

    Write-Step "目标：s3://$Bucket/$Tag/"

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
        throw "产物里没有文件：$work"
    }

    $uploaded = 0
    $skipped = 0
    foreach ($file in $files) {
        $key = $file.FullName.Substring($work.Length).TrimStart('\', '/').Replace('\', '/')
        $remoteKey = "$Tag/$key"

        $remoteSize = Get-RemoteObjectSize -Key $remoteKey
        if ($null -ne $remoteSize -and $remoteSize -eq $file.Length) {
            Write-Step "跳过 $key（已存在，$($file.Length) 字节）"
            $skipped++
            continue
        }

        $destination = "s3://$Bucket/$remoteKey"
        Write-Step "上传 $key（$([math]::Round($file.Length / 1MB, 1)) MB）"
        & $aws s3 cp $file.FullName $destination `
            --endpoint-url $EndpointUrl `
            --cache-control 'public, max-age=31536000, immutable' `
            --no-progress
        if ($LASTEXITCODE -ne 0) {
            throw "上传失败：$key（aws 退出码 $LASTEXITCODE）"
        }
        $uploaded++
    }

    Write-Step "上传完成：新传 $uploaded 个，跳过 $skipped 个，共 $($files.Count) 个"
}
finally {
    if ($ownWork -and $work -and (Test-Path -LiteralPath $work)) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
