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

function Test-ExecutableInPath([string] $name) {
    return $null -ne (Get-Command -Name $name -CommandType Application -ErrorAction SilentlyContinue)
}

function Invoke-Scoop([string[]] $arguments) {
    & scoop @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "scoop $($arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
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
