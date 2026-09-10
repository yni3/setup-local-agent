@echo off
rem Windows の初期セットアップ用バッチです。すべて現在のユーザー権限でインストールします。
setlocal EnableExtensions DisableDelayedExpansion

where pwsh.exe >nul 2>&1
if errorlevel 1 (
    echo ERROR: PowerShell 7 ^(pwsh.exe^) is not installed or is not in PATH.
    echo Install PowerShell 7, then run this batch file again.
    pause
    exit /b 1
)

set "CONFIGURE_WINDOWS_BATCH=%~f0"
pwsh.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$content = [System.IO.File]::ReadAllText($env:CONFIGURE_WINDOWS_BATCH); $marker = ':PS_SCRIPT:'; $start = $content.LastIndexOf($marker); if ($start -lt 0) { throw 'PowerShell script marker was not found.' }; & ([scriptblock]::Create($content.Substring($start + $marker.Length)))"
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
    echo.
    echo ERROR: Windows configuration failed with exit code %EXIT_CODE%.
    if /i not "%GITHUB_ACTIONS%"=="true" pause
)

endlocal & exit /b %EXIT_CODE%
exit /b

:PS_SCRIPT:
$ErrorActionPreference = 'Stop'

function Refresh-ProcessPath {
    $processPath = $env:Path
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')

    $pathEntries = @($processPath, $userPath, $machinePath) |
        Where-Object { $_ } |
        ForEach-Object { $_ -split ';' } |
        Where-Object { $_ } |
        Select-Object -Unique
    $env:Path = $pathEntries -join ';'

    # Scoop is installed per-user and its shims directory may not be visible
    # in this process until a new shell is started.
    $scoopShims = Join-Path $env:USERPROFILE 'scoop\shims'
    if ((Test-Path -LiteralPath $scoopShims) -and
        (($env:Path -split ';') -notcontains $scoopShims)) {
        $env:Path = "$scoopShims;$env:Path"
    }
}

function Add-UserPathEntry([string] $path) {
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Container)) {
        throw "Cannot add a missing directory to PATH: $path"
    }

    $normalizedPath = $path.TrimEnd('\', '/')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = @($userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $alreadyPresent = $entries | Where-Object {
        $_.TrimEnd('\', '/') -ieq $normalizedPath
    } | Select-Object -First 1

    if ($null -eq $alreadyPresent) {
        # Put MSYS2 ahead of other Unix compatibility layers in new shells.
        $newUserPath = (@($normalizedPath) + $entries) -join ';'
        [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
        Write-Host "[path] Added to the current user's PATH: $normalizedPath"
    } else {
        Write-Host "[skip] The current user's PATH already contains: $normalizedPath"
    }

    # Also make the directory available to this PowerShell process immediately.
    $processEntries = @($env:Path -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $processAlreadyPresent = $processEntries | Where-Object {
        $_.TrimEnd('\', '/') -ieq $normalizedPath
    } | Select-Object -First 1
    if ($null -eq $processAlreadyPresent) {
        $env:Path = (@($normalizedPath) + $processEntries) -join ';'
    }
}

function Add-GitHubPathEntry([string] $path) {
    if ([string]::IsNullOrWhiteSpace($env:GITHUB_PATH)) {
        return
    }

    $normalizedPath = $path.TrimEnd('\', '/')
    $existingEntries = @()
    if (Test-Path -LiteralPath $env:GITHUB_PATH -PathType Leaf) {
        $existingEntries = @(Get-Content -LiteralPath $env:GITHUB_PATH -ErrorAction SilentlyContinue)
    }

    $alreadyPresent = $existingEntries | Where-Object {
        $_.TrimEnd('\', '/') -ieq $normalizedPath
    } | Select-Object -First 1
    if ($null -eq $alreadyPresent) {
        Add-Content -LiteralPath $env:GITHUB_PATH -Value $normalizedPath -Encoding utf8
        Write-Host "[path] Added to GitHub Actions PATH: $normalizedPath"
    }
}

function Test-ExecutableInPath([string] $name) {
    return $null -ne (Get-Command -Name $name -CommandType Application -ErrorAction SilentlyContinue)
}

function Invoke-Scoop([string[]] $arguments) {
    & scoop @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "scoop $($arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

function Get-ScoopAppPath([string] $package) {
    $output = @(& scoop prefix $package 2>$null)
    if ($LASTEXITCODE -ne 0 -or $output.Count -eq 0) {
        return $null
    }

    $candidate = ([string]($output | Select-Object -Last 1)).Trim()
    if ([string]::IsNullOrWhiteSpace($candidate) -or
        -not (Test-Path -LiteralPath $candidate -PathType Container)) {
        return $null
    }
    return (Resolve-Path -LiteralPath $candidate).Path
}

function Install-Portable7Zip {
    # Scoop does not use the 7z command from PATH to extract packages. Its
    # helper lookup specifically checks apps\7zip\current\7z.exe. Therefore
    # putting 7z on PATH alone does not solve MSI extraction failures.
    # Create the helper at Scoop's expected path before installing any package.
    $scoopRoot = Join-Path $env:USERPROFILE 'scoop'
    if (-not (Test-Path -LiteralPath (Join-Path $scoopRoot 'apps') -PathType Container)) {
        $scoopRoot = [Environment]::GetEnvironmentVariable('SCOOP', 'User')
    }
    if ([string]::IsNullOrWhiteSpace($scoopRoot) -or
        -not (Test-Path -LiteralPath (Join-Path $scoopRoot 'apps') -PathType Container)) {
        throw "Scoop's root directory could not be resolved for the current user: $scoopRoot"
    }
    $portableRoot = Join-Path $scoopRoot 'apps\7zip\current'
    $portable7z = Join-Path $portableRoot '7z.exe'

    if (Test-Path -LiteralPath $portable7z -PathType Leaf) {
        & $portable7z -h *> $null
        if ($LASTEXITCODE -eq 0) {
            Add-UserPathEntry $portableRoot
            Add-GitHubPathEntry $portableRoot
            Refresh-ProcessPath
            Write-Host "[skip] A working Scoop 7-Zip helper is already available: $portable7z"
            return
        }
    }

    $downloadUrl = 'https://github.com/ip7z/7zip/releases/download/26.03/7z2603.exe'
    $expectedHash = '0f6ec2eda1f8c5dc4c267ee761c0dad8a9d5e8863e0c84b7ac026bc9625a1560'
    $downloadPath = [System.IO.Path]::GetTempFileName()

    try {
        New-Item -ItemType Directory -Path $portableRoot -Force | Out-Null
        Write-Host '[install] standalone 7z bootstrap binary...'
        Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadPath
        $actualHash = (Get-FileHash -LiteralPath $downloadPath -Algorithm SHA256).Hash
        if ($actualHash -ine $expectedHash) {
            throw "The downloaded 7z bootstrap binary failed SHA256 verification: $actualHash"
        }
        Copy-Item -LiteralPath $downloadPath -Destination $portable7z -Force
        Unblock-File -LiteralPath $portable7z -ErrorAction SilentlyContinue
    } finally {
        Remove-Item -LiteralPath $downloadPath -Force -ErrorAction SilentlyContinue
    }

    Add-UserPathEntry $portableRoot
    Add-GitHubPathEntry $portableRoot
    Refresh-ProcessPath
    & $portable7z -h *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "The standalone 7z bootstrap binary could not be executed at Scoop's helper path: $portable7z"
    }
    Write-Host "[ready] Standalone 7z is available to Scoop at its helper path: $portable7z"
}

function Install-ScoopMsiExtractor {
    $lessMsiRoot = Get-ScoopAppPath 'lessmsi'
    if ($null -eq $lessMsiRoot) {
        Write-Host '[install] lessmsi via Scoop for MSI extraction...'
        Invoke-Scoop @('install', 'lessmsi')
        $lessMsiRoot = Get-ScoopAppPath 'lessmsi'
    } else {
        Write-Host "[skip] lessmsi is already installed via Scoop: $lessMsiRoot"
    }

    if ($null -eq $lessMsiRoot) {
        throw 'lessmsi installation completed, but its Scoop app path could not be resolved.'
    }

    $lessMsiPath = Join-Path $lessMsiRoot 'lessmsi.exe'
    if (-not (Test-Path -LiteralPath $lessMsiPath -PathType Leaf)) {
        throw "Scoop lessmsi installation is missing the expected executable: $lessMsiPath"
    }

    # Windows Installer is unavailable for some service accounts. Scoop's
    # use_lessmsi option makes Expand-MsiArchive use lessmsi instead of
    # msiexec.exe for all subsequent MSI packages.
    Invoke-Scoop @('config', 'use_lessmsi', 'true')
    Write-Host "[ready] Scoop will extract MSI packages with lessmsi: $lessMsiPath"
}

function Install-Msys2 {
    $msys2Root = Get-ScoopAppPath 'msys2'
    if ($null -eq $msys2Root) {
        Write-Host '[install] msys2 via Scoop...'
        Invoke-Scoop @('install', 'msys2')
        $msys2Root = Get-ScoopAppPath 'msys2'
    } else {
        Write-Host "[skip] msys2 is already installed via Scoop: $msys2Root"
    }

    if ($null -eq $msys2Root) {
        throw 'MSYS2 installation completed, but its Scoop app path could not be resolved.'
    }

    $msys2UsrBin = Join-Path $msys2Root 'usr\bin'
    foreach ($command in @('bash.exe', 'cat.exe', 'ls.exe')) {
        $commandPath = Join-Path $msys2UsrBin $command
        if (-not (Test-Path -LiteralPath $commandPath -PathType Leaf)) {
            throw "MSYS2 is missing the expected command: $commandPath"
        }
    }

    Add-UserPathEntry $msys2UsrBin
    Add-GitHubPathEntry $msys2UsrBin
    Refresh-ProcessPath

    foreach ($command in @('bash', 'cat', 'ls')) {
        if (-not (Test-ExecutableInPath $command)) {
            throw "MSYS2 '$command' is not available in PATH after installation."
        }
        $resolved = (Get-Command -Name $command -CommandType Application | Select-Object -First 1).Source
        if ($resolved -ine (Join-Path $msys2UsrBin "$command.exe")) {
            throw "The '$command' command does not resolve to MSYS2: $resolved"
        }
        & $resolved --version *> $null
        if ($LASTEXITCODE -ne 0) {
            throw "The MSYS2 '$command' command could not be executed."
        }
    }

    Write-Host '[ready] MSYS2 Bash, cat, and ls are available from the Windows PATH.'
}

function Install-PowerShellLint {
    $userModulePath = Join-Path $env:USERPROFILE 'Documents\PowerShell\Modules\PSScriptAnalyzer'
    $userModule = Get-Module -ListAvailable -Name PSScriptAnalyzer |
        Where-Object { $_.ModuleBase -like "$userModulePath\*" } |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if ($null -eq $userModule) {
        Write-Host '[install] PSScriptAnalyzer for the current user...'

        if ($null -ne (Get-Command -Name Install-PSResource -ErrorAction SilentlyContinue)) {
            Install-PSResource -Name PSScriptAnalyzer -Scope CurrentUser -TrustRepository
        } elseif ($null -ne (Get-Command -Name Install-Module -ErrorAction SilentlyContinue)) {
            Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Repository PSGallery -Force -AllowClobber
        } else {
            throw 'Neither Install-PSResource nor Install-Module is available.'
        }
    } else {
        Write-Host "[skip] PSScriptAnalyzer is already installed for the current user: $($userModule.ModuleBase)"
    }

    Import-Module -Name PSScriptAnalyzer -Force
    if ($null -eq (Get-Command -Name Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue)) {
        throw 'PSScriptAnalyzer installation completed, but Invoke-ScriptAnalyzer is not available.'
    }
}

function Test-DotnetFormat {
    Refresh-ProcessPath

    if (-not (Test-ExecutableInPath 'dotnet')) {
        throw 'The .NET SDK is not available in PATH, so C# linting via dotnet format cannot be used.'
    }

    & dotnet format --version *> $null
    if ($LASTEXITCODE -ne 0) {
        throw 'The .NET SDK is available, but dotnet format could not be executed.'
    }

    Write-Host '[ready] C# linting is available via dotnet format.'
}

try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this batch file from a non-administrator shell. Scoop is intentionally installed per-user.'
    }

    Refresh-ProcessPath

    if ($null -eq (Get-Command -Name scoop -ErrorAction SilentlyContinue)) {
        Write-Host 'Scoop was not found in PATH. Installing Scoop for the current user...'
        $scoopInstaller = Invoke-RestMethod -Uri 'https://get.scoop.sh'
        Invoke-Expression $scoopInstaller
        Refresh-ProcessPath
    } else {
        Write-Host 'Scoop is already available in PATH.'
    }

    if ($null -eq (Get-Command -Name scoop -ErrorAction SilentlyContinue)) {
        throw 'Scoop installation completed, but the scoop command is still not available in PATH.'
    }

    Install-Portable7Zip
    Install-ScoopMsiExtractor
    Install-Msys2

    $tools = @(
        @{ Command = 'gh';       Package = 'gh' },
        @{ Command = 'rg';       Package = 'ripgrep' },
        @{ Command = 'node';     Package = 'nodejs' },
        @{ Command = 'python3';  Package = 'python' },
        @{ Command = 'ruby';     Package = 'ruby' },
        @{ Command = 'dotnet';   Package = 'dotnet-sdk' },
        @{ Command = 'fd';       Package = 'fd' },
        @{ Command = 'jq';       Package = 'jq' },
        @{ Command = 'yq';       Package = 'yq' },
        @{ Command = 'tar';      Package = 'tar' },
        @{ Command = 'git';      Package = 'git' },
        @{ Command = '7z';       Package = '7zip' },
        @{ Command = 'fzf';      Package = 'fzf' },
        @{ Command = 'bat';      Package = 'bat' },
        @{ Command = 'delta';    Package = 'delta' },
        @{ Command = 'curl';     Package = 'curl' },
        @{ Command = 'actionlint'; Package = 'actionlint' }
    )

    foreach ($tool in $tools) {
        Refresh-ProcessPath

        if (Test-ExecutableInPath $tool.Command) {
            $resolved = (Get-Command -Name $tool.Command -CommandType Application).Source
            Write-Host "[skip] $($tool.Command) is already in PATH: $resolved"
            continue
        }

        Write-Host "[install] $($tool.Package) via Scoop..."
        Invoke-Scoop @('install', $tool.Package)
        Refresh-ProcessPath

        if (-not (Test-ExecutableInPath $tool.Command)) {
            throw "Installed Scoop package '$($tool.Package)', but '$($tool.Command)' is still not available in PATH."
        }
    }

    Install-PowerShellLint
    Test-DotnetFormat

    if (-not (Test-ExecutableInPath 'actionlint')) {
        throw 'actionlint installation completed, but the actionlint command is still not available in PATH.'
    }
    Write-Host '[ready] GitHub Actions linting is available via actionlint.'

    Write-Host 'Windows configuration completed successfully.'
    exit 0
} catch {
    Write-Error $_
    exit 1
}
