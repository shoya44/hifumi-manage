# docs の現状と再現フロー

このディレクトリには配布用の PDF（00〜10）が収められています。

- 既存の PDF が正であり、Markdown 原稿を別管理（別リポジトリ）している場合は、ここに追加作業は不要です。
- README.md は "docs/src/ と build_docs.py" を参照する記述を含んでいます。整合性を取るため、簡易ビルドスクリプトと placeholder の Markdown を追加しました。

再生成手順（推奨: pandoc がインストールされている環境）

```bash
pip install reportlab    # reportlab を使うオプションがある場合の注記
# pandoc が使える場合
python docs/build_docs.py
```

注意: 現時点では placeholder の Markdown を配置しただけです。実際の PDF と同等の内容にするには、それぞれの Markdown を編集して完全な原稿を用意してください。
