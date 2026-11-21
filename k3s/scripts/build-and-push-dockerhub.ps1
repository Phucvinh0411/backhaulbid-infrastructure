<#
.SYNOPSIS
Build BackHaulBid Docker images tren Windows va push len Docker Hub.

.DESCRIPTION
Script doc cau hinh tu k3s\.env.k3s (hoac tham so truyen truc tiep),
build cac microservices voi --platform linux/amd64 va push len Docker Hub:
  <Registry>/<Prefix><service>:<Tag>
Mac dinh build 9 service chuan K3s (khong build eureka-server tru khi chi dinh rieng).

.EXAMPLE
.\k3s\scripts\build-and-push-dockerhub.ps1

.EXAMPLE
.\k3s\scripts\build-and-push-dockerhub.ps1 -Services web-portal,api-gateway -Tag v1.0.2

.EXAMPLE
.\k3s\scripts\build-and-push-dockerhub.ps1 -Registry hoangdev -Prefix backhaulbid- -PublicBaseUrl http://54.1.2.3
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string[]]$Services = @(),

    [string]$Tag = "",
    [string]$Registry = "",
    [string]$Prefix = "",
    [string]$Platform = "",
    [string]$PublicBaseUrl = "",
    [string]$EnvFile = "",

    [switch]$SkipBuild,
    [switch]$NoCache,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$K3sDir = Split-Path -Parent $ScriptDir
$InfraDir = Split-Path -Parent $K3sDir
$WorkspaceDir = Split-Path -Parent $InfraDir

if ([string]::IsNullOrWhiteSpace($EnvFile)) {
    $EnvFile = Join-Path $K3sDir ".env.k3s"
}

function Read-DotEnvMap {
    param([string]$Path)
    $map = @{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $map
    }
    foreach ($rawLine in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) {
            continue
        }
        $eqIdx = $line.IndexOf("=")
        if ($eqIdx -lt 1) {
            continue
        }
        $key = $line.Substring(0, $eqIdx).Trim()
        $val = $line.Substring($eqIdx + 1).Trim()
        if ($val.Length -ge 2) {
            $first = $val[0]
            $last = $val[$val.Length - 1]
            if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
                $val = $val.Substring(1, $val.Length - 2)
            }
        }
        $map[$key] = $val
    }
    return $map
}

function Resolve-ConfigValue {
    param(
        [string]$ParamValue,
        [string]$EnvVarName,
        [hashtable]$DotEnv,
        [string]$DefaultValue = ""
    )
    if (-not [string]::IsNullOrWhiteSpace($ParamValue)) {
        return $ParamValue
    }
    $procVal = [Environment]::GetEnvironmentVariable($EnvVarName)
    if (-not [string]::IsNullOrWhiteSpace($procVal)) {
        return $procVal
    }
    if ($DotEnv.ContainsKey($EnvVarName) -and -not [string]::IsNullOrWhiteSpace($DotEnv[$EnvVarName])) {
        return $DotEnv[$EnvVarName]
    }
    return $DefaultValue
}

$dotEnv = Read-DotEnvMap -Path $EnvFile

$resolvedRegistry = Resolve-ConfigValue -ParamValue $Registry -EnvVarName "IMAGE_REGISTRY" -DotEnv $dotEnv
$dockerHubUser = Resolve-ConfigValue -ParamValue "" -EnvVarName "DOCKERHUB_USERNAME" -DotEnv $dotEnv
$dockerHubToken = Resolve-ConfigValue -ParamValue "" -EnvVarName "DOCKERHUB_TOKEN" -DotEnv $dotEnv
$dockerHubServer = Resolve-ConfigValue -ParamValue "" -EnvVarName "DOCKERHUB_SERVER" -DotEnv $dotEnv -DefaultValue "https://index.docker.io/v1/"

if ([string]::IsNullOrWhiteSpace($resolvedRegistry) -or $resolvedRegistry -eq "backhaulbid") {
    if (-not [string]::IsNullOrWhiteSpace($dockerHubUser)) {
        $resolvedRegistry = $dockerHubUser
    } else {
        throw "Hay truyen -Registry <dockerhub_username> hoac dat IMAGE_REGISTRY=<dockerhub_username> trong '$EnvFile' (khong dung mac dinh 'backhaulbid')."
    }
}

# Giu nguyen Prefix rong neu user chu dinh de trong
if ($PSBoundParameters.ContainsKey("Prefix")) {
    $resolvedPrefix = $Prefix
} elseif (-not [string]::IsNullOrWhiteSpace($env:IMAGE_PREFIX)) {
    $resolvedPrefix = $env:IMAGE_PREFIX
} elseif ($dotEnv.ContainsKey("IMAGE_PREFIX")) {
    $resolvedPrefix = $dotEnv["IMAGE_PREFIX"]
} else {
    $resolvedPrefix = ""
}

$resolvedTag = Resolve-ConfigValue -ParamValue $Tag -EnvVarName "IMAGE_TAG" -DotEnv $dotEnv -DefaultValue "auto"
if ([string]::IsNullOrWhiteSpace($resolvedTag) -or $resolvedTag -eq "auto") {
    try {
        $sha = (git -C $InfraDir rev-parse --short HEAD 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($sha)) {
            $resolvedTag = $sha
        } else {
            $resolvedTag = Get-Date -Format "yyyyMMddHHmmss"
        }
    } catch {
        $resolvedTag = Get-Date -Format "yyyyMMddHHmmss"
    }
}

$resolvedPlatform = Resolve-ConfigValue -ParamValue $Platform -EnvVarName "IMAGE_PLATFORM" -DotEnv $dotEnv -DefaultValue "linux/amd64"
$resolvedPublicUrl = Resolve-ConfigValue -ParamValue $PublicBaseUrl -EnvVarName "PUBLIC_BASE_URL" -DotEnv $dotEnv
$socketPath = Resolve-ConfigValue -ParamValue "" -EnvVarName "NEXT_PUBLIC_BIDDING_SOCKET_PATH" -DotEnv $dotEnv -DefaultValue "/bidding-socket"
$googleClientId = Resolve-ConfigValue -ParamValue "" -EnvVarName "GOOGLE_CLIENT_ID" -DotEnv $dotEnv

$allK3sServices = @(
    "api-gateway",
    "identity-service",
    "fleet-service",
    "wallet-service",
    "contract-service",
    "media-service",
    "bidding-service",
    "notification-service",
    "web-portal"
)
$supportedServices = $allK3sServices + @("eureka-server")

$targets = if ($Services.Count -gt 0) { $Services } else { $allK3sServices }
foreach ($svc in $targets) {
    if ($supportedServices -notcontains $svc) {
        throw "Service khong hop le: '$svc'. Danh sach hop le: $($supportedServices -join ', ')"
    }
}

if ($targets -contains "web-portal" -and -not $SkipBuild) {
    if ([string]::IsNullOrWhiteSpace($resolvedPublicUrl) -or $resolvedPublicUrl -like "*<EC2_PUBLIC_IP>*") {
        throw "Can PUBLIC_BASE_URL (vd: http://<EC2_PUBLIC_IP> hoac https://domain.com) trong '$EnvFile' hoac -PublicBaseUrl de nhung vao web-portal."
    }
    $resolvedPublicUrl = $resolvedPublicUrl.TrimEnd("/")
}

$coreDir = Join-Path $WorkspaceDir "backhaulbid-core-services"
$nodeDir = Join-Path $WorkspaceDir "backhaulbid-node-services"
$webDir = Join-Path $WorkspaceDir "backhaulbid-web-portal"

function Invoke-DockerCommand {
    param([string[]]$DockerArgs)
    Write-Host ("    > docker " + ($DockerArgs -join " ")) -ForegroundColor DarkGray
    if ($DryRun) {
        return
    }
    & docker @DockerArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Lenh docker that bai voi exit code $LASTEXITCODE."
    }
}

function Assert-RepoDir {
    param([string]$DirPath)
    if (-not (Test-Path -LiteralPath $DirPath -PathType Container)) {
        throw "Khong tim thay thu muc repo: $DirPath"
    }
}

if (-not $DryRun -and -not [string]::IsNullOrWhiteSpace($dockerHubUser) -and -not [string]::IsNullOrWhiteSpace($dockerHubToken)) {
    Write-Host "==> Dang nhap Docker Registry ($dockerHubServer) voi user '$dockerHubUser'..." -ForegroundColor Cyan
    $dockerHubToken | & docker login $dockerHubServer -u $dockerHubUser --password-stdin | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Dang nhap Docker Hub that bai. Kiem tra lai DOCKERHUB_USERNAME / DOCKERHUB_TOKEN."
    }
}

Write-Host "==> Target images: ${resolvedRegistry}/${resolvedPrefix}<service>:${resolvedTag} (${resolvedPlatform})" -ForegroundColor Green

foreach ($svc in $targets) {
    $image = "${resolvedRegistry}/${resolvedPrefix}${svc}:${resolvedTag}"
    Write-Host ""
    Write-Host "==============================================================================" -ForegroundColor Yellow
    Write-Host "==> Processing ${svc} -> ${image}" -ForegroundColor Yellow
    Write-Host "==============================================================================" -ForegroundColor Yellow

    if (-not $SkipBuild) {
        $buildArgs = @("build", "--platform", $resolvedPlatform)
        if ($NoCache) {
            $buildArgs += "--no-cache"
        }

        switch ($svc) {
            "eureka-server" {
                $context = Join-Path $InfraDir "eureka-server"
                $buildArgs += @("-t", $image, $context)
            }
            "api-gateway" {
                $context = Join-Path $InfraDir "api-gateway"
                $buildArgs += @("-t", $image, $context)
            }
            { $_ -in @("identity-service", "fleet-service", "wallet-service", "contract-service", "media-service") } {
                Assert-RepoDir -DirPath $coreDir
                $buildArgs += @("--build-arg", "MODULE=$svc", "-t", $image, $coreDir)
            }
            "bidding-service" {
                Assert-RepoDir -DirPath $nodeDir
                $buildArgs += @("--build-arg", "APP=bidding", "--build-arg", "PORT=3001", "-t", $image, $nodeDir)
            }
            "notification-service" {
                Assert-RepoDir -DirPath $nodeDir
                $buildArgs += @("--build-arg", "APP=notification", "--build-arg", "PORT=3002", "-t", $image, $nodeDir)
            }
            "web-portal" {
                Assert-RepoDir -DirPath $webDir
                $buildArgs += @(
                    "--build-arg", "NEXT_PUBLIC_GATEWAY_URL=$resolvedPublicUrl",
                    "--build-arg", "NEXT_PUBLIC_BIDDING_SOCKET_PATH=$socketPath",
                    "--build-arg", "NEXT_PUBLIC_GOOGLE_CLIENT_ID=$googleClientId",
                    "-t", $image,
                    $webDir
                )
            }
        }

        Invoke-DockerCommand -DockerArgs $buildArgs
    }

    Invoke-DockerCommand -DockerArgs @("push", $image)
}

Write-Host ""
Write-Host "==> HOAN TAT! Da push $($targets.Count) image len Docker Hub:" -ForegroundColor Green
Write-Host "    ${resolvedRegistry}/${resolvedPrefix}*:${resolvedTag}" -ForegroundColor Green
Write-Host "    Tren EC2, chay de deploy dung tag nay:" -ForegroundColor Cyan
Write-Host "    IMAGE_REGISTRY=${resolvedRegistry} IMAGE_PREFIX=${resolvedPrefix} IMAGE_TAG=${resolvedTag} ./k3s/scripts/deploy.sh" -ForegroundColor White
