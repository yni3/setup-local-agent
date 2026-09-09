#!/usr/bin/env bash
# macOS の初期セットアップ用スクリプトです。管理者権限を使わず、
# mise と各ツールを現在のユーザー領域へインストールします。
set -Eeuo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    printf 'ERROR: This script only supports macOS.\n' >&2
    exit 1
fi

if [[ "${EUID}" -eq 0 ]]; then
    printf 'ERROR: Run this script as a normal user, not as root.\n' >&2
    exit 1
fi

readonly LOCAL_BIN="${HOME}/.local/bin"
readonly MISE_HOME="${HOME}/.local/share/mise"
readonly ZSHRC="${ZDOTDIR:-${HOME}}/.zshrc"
mkdir -p "${LOCAL_BIN}" "${MISE_HOME}"
export PATH="${LOCAL_BIN}:${PATH}"

append_github_path() {
    if [[ -n "${GITHUB_PATH:-}" ]]; then
        printf '%s\n' "$1" >>"${GITHUB_PATH}"
    fi
}

refresh_mise_path() {
    # mise activate は global tool の実体または shims をこのプロセスに追加します。
    eval "$(mise activate bash)"

    while IFS= read -r path; do
        [[ -n "${path}" && -d "${path}" ]] || continue
        case ":${PATH}:" in
            *":${path}:"*) ;;
            *) export PATH="${path}:${PATH}" ;;
        esac
        append_github_path "${path}"
    done < <(mise bin-paths)

    append_github_path "${LOCAL_BIN}"
}

install_mise() {
    if command -v mise >/dev/null 2>&1; then
        printf '[skip] mise is already available: %s\n' "$(command -v mise)"
        return
    fi

    printf '[install] mise in %s (no Homebrew, no sudo)...\n' "${LOCAL_BIN}"
    curl --fail --silent --show-error --location https://mise.run \
        | MISE_INSTALL_PATH="${LOCAL_BIN}/mise" sh
}

ensure_mise_tool() {
    local command_name="$1"
    local package_name="$2"

    refresh_mise_path
    if command -v "${command_name}" >/dev/null 2>&1; then
        printf '[skip] %s is already in PATH: %s\n' "${command_name}" "$(command -v "${command_name}")"
        return
    fi

    printf '[install] %s via mise...\n' "${package_name}"
    mise use --global "${package_name}@latest"
    refresh_mise_path

    if ! command -v "${command_name}" >/dev/null 2>&1; then
        printf "ERROR: Installed '%s', but '%s' is still unavailable in PATH.\n" \
            "${package_name}" "${command_name}" >&2
        exit 1
    fi
}

validate_command() {
    local command_name="$1"
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        printf "ERROR: Required command '%s' is not available in PATH.\n" "${command_name}" >&2
        exit 1
    fi
}

install_powershell_lint_if_available() {
    if ! command -v pwsh >/dev/null 2>&1; then
        printf '[skip] pwsh is not installed; skipping PSScriptAnalyzer.\n'
        return
    fi

    local pwsh_path
    pwsh_path="$(command -v pwsh)"

    printf '[install] PSScriptAnalyzer for the current user...\n'
    "${pwsh_path}" -NoLogo -NoProfile -NonInteractive -Command '
$ErrorActionPreference = "Stop"
$module = Get-Module -ListAvailable -Name PSScriptAnalyzer | Select-Object -First 1
if ($null -eq $module) {
    if ($null -ne (Get-Command -Name Install-PSResource -ErrorAction SilentlyContinue)) {
        Install-PSResource -Name PSScriptAnalyzer -Scope CurrentUser -TrustRepository
    } elseif ($null -ne (Get-Command -Name Install-Module -ErrorAction SilentlyContinue)) {
        Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Repository PSGallery -Force -AllowClobber
    } else {
        throw "Neither Install-PSResource nor Install-Module is available."
    }
}
Import-Module -Name PSScriptAnalyzer -Force
if ($null -eq (Get-Command -Name Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue)) {
    throw "PSScriptAnalyzer installation completed, but Invoke-ScriptAnalyzer is unavailable."
}
'
}

install_mise
refresh_mise_path

# macOS 標準の Git、curl、tar、bash、cat、ls はそのまま利用し、
# Windows バッチで導入していた追加ツールだけを mise のユーザー領域へ導入します。
ensure_mise_tool gh gh
ensure_mise_tool rg ripgrep
ensure_mise_tool node node
ensure_mise_tool python3 python
ensure_mise_tool ruby ruby
ensure_mise_tool dotnet dotnet
ensure_mise_tool fd fd
ensure_mise_tool jq jq
ensure_mise_tool yq yq
ensure_mise_tool fzf fzf
ensure_mise_tool bat bat
ensure_mise_tool delta delta
ensure_mise_tool actionlint actionlint
ensure_mise_tool 7zz aqua:ip7z/7zip

# Windows の 7z というコマンド名も利用できるように、ユーザー領域に互換リンクを作ります。
if [[ ! -e "${LOCAL_BIN}/7z" ]]; then
    ln -s "$(command -v 7zz)" "${LOCAL_BIN}/7z"
fi
refresh_mise_path

if ! grep -Fq '# setup-local-agent: mise' "${ZSHRC}" 2>/dev/null; then
    cat >>"${ZSHRC}" <<'EOF'

# setup-local-agent: mise
export PATH="$HOME/.local/bin:$PATH"
eval "$("$HOME/.local/bin/mise" activate zsh)"
EOF
    printf '[path] Added mise activation to %s\n' "${ZSHRC}"
fi

install_powershell_lint_if_available

for command_name in gh rg node python3 ruby dotnet fd jq yq fzf bat delta actionlint 7z 7zz git curl tar bash cat ls; do
    validate_command "${command_name}"
done

dotnet format --version >/dev/null
actionlint -version >/dev/null

printf '[ready] PSScriptAnalyzer, dotnet format, and actionlint are available.\n'
printf 'macOS configuration completed successfully. Open a new shell or run: source %s\n' "${ZSHRC}"
