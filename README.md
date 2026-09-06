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

さらに、PowerShell のユーザー領域に `PSScriptAnalyzer` モジュールを導入し、`Invoke-ScriptAnalyzer` が利用できることを確認します。.NET SDK の `dotnet format` と `actionlint` についても実行可能性を検証します。

### 注意事項

- Scoop と各ツールは管理者権限を使わず、現在のユーザー領域にインストールされます。
- `configure-windows.bat` は PowerShell 7 が PATH に存在しない場合、Scoop が管理者権限で実行されている場合、または必要なツールを利用できない場合にエラー終了します。
- インストールにはインターネット接続が必要です。
