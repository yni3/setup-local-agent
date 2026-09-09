# setup-local-agent
ローカルAIエージェントのツールコールに必要な各種プログラムの環境構築スクリプト

## Windows のセットアップ

PowerShell 7 (`pwsh.exe`) をインストール済みの、管理者権限ではない PowerShell またはコマンドプロンプトで、次を実行してください。

```bat
configure-windows.bat
```

このスクリプトは、現在のユーザーを対象に [Scoop](https://scoop.sh/) を導入し、Scoop で次のツールをインストールします。すでに PATH に存在するツールはスキップされます。

| ツール | Scoop パッケージ | 用途の概要 |
| --- | --- | --- |
| GitHub CLI (`gh`) | `gh` | GitHub の操作 |
| ripgrep (`rg`) | `ripgrep` | 高速な全文検索 |
| Node.js (`node`) | `nodejs` | JavaScript 実行環境 |
| .NET SDK (`dotnet`) | `dotnet-sdk` | .NET/C# の開発・フォーマット |
| fd (`fd`) | `fd` | ファイル検索 |
| jq (`jq`) | `jq` | JSON の処理 |
| yq (`yq`) | `yq` | YAML/XML 等の処理 |
| tar (`tar`) | `tar` | アーカイブ操作 |
| Git (`git`) | `git` | バージョン管理 |
| 7-Zip (`7z`) | `7zip` | 圧縮・展開 |
| fzf (`fzf`) | `fzf` | インタラクティブ検索 |
| bat (`bat`) | `bat` | 高機能なファイル表示 |
| delta (`delta`) | `delta` | Git diff の表示 |
| curl (`curl`) | `curl` | HTTP 通信 |
| actionlint (`actionlint`) | `actionlint` | GitHub Actions ワークフローの lint |
| MSYS2 (`bash`, `cat`, `ls`) | `msys2` | Bash と Unix 系コマンド |

さらに、PowerShell のユーザー領域に `PSScriptAnalyzer` モジュールを導入し、`Invoke-ScriptAnalyzer` が利用できることを確認します。.NET SDK の `dotnet format` と `actionlint` についても実行可能性を検証します。

MSYS2 は Scoop の `msys2` パッケージからユーザー領域へ導入し、MSYS2 の `usr\bin` を現在のユーザーの PATH に追加します。これにより、cmd では `bash`、`cat`、`ls` を直接実行できます。MSYS2 Bash は `bash` で起動できます。

PowerShell では `ls` と `cat` が標準エイリアス（`Get-ChildItem` と `Get-Content`）として予約されているため、MSYS2 版を使う場合は `ls.exe` / `cat.exe`、または `bash -lc "ls"` / `bash -lc "cat file"` を使用してください。PowerShell プロファイルは変更しません。

MSYS2 の `ucrt64\bin` などの環境別ディレクトリは Windows 全体の PATH には追加しません。UCRT64 などの開発環境を使う場合は、MSYS2 の環境を起動して利用してください。パッケージの更新は MSYS2 環境内で `pacman -Syu` を実行します。更新中に再起動を求められた場合は、指示に従って MSYS2 を再起動し、更新を完了してください。

### 注意事項

- Scoop と各ツールは管理者権限を使わず、現在のユーザー領域にインストールされます。
- `configure-windows.bat` は PowerShell 7 が PATH に存在しない場合、Scoop が管理者権限で実行されている場合、または必要なツールを利用できない場合にエラー終了します。
- インストールにはインターネット接続が必要です。
- PATH の変更は、セットアップを実行した既存のシェルには自動反映されない場合があります。完了後に新しい cmd / PowerShell を起動してください。GitHub Actions では `GITHUB_PATH` にも追加されるため、後続ステップから利用できます。
- Scoop、MSYS2、Git などで同名のコマンドがある場合、MSYS2 の `usr\bin` を優先する設定になります。PowerShell の `ls` / `cat` エイリアスだけは変更されません。

## GitHub Actions のコンポジットアクション

このリポジトリは、外部リポジトリのワークフローから呼び出せるコンポジットアクションとしても利用できます。`uses` にはこのリポジトリの所有者、リポジトリ名、タグまたはコミット SHA を指定してください。

```yaml
steps:
  - name: Configure runner tools
    uses: OWNER/setup-local-agent@v1
```

アクションは `runner.os` が `Windows` の場合だけ `configure-windows.bat` を実行します。Linux や macOS では Windows の設定を行わず、スキップメッセージを出力して成功します。Windows で失敗した場合はバッチファイルの終了コードをそのままアクションの失敗として返します。

外部リポジトリがこのアクションを利用するには、呼び出し元からこのリポジトリへのアクセス権が必要です。公開リポジトリのワークフローで利用する場合も、リリース済みタグまたはコミット SHA への固定を推奨します。
