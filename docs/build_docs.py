"""docs/build_docs.py

簡易ビルドスクリプト。
- docs/src/*.md が存在する場合、pandoc があれば各 Markdown を PDF に変換して docs/ に出力する。
- pandoc がない場合は変換方法を表示するだけ。

用途: リポジトリ内で PDF の再生成フローを示し、README の記述（docs/src/, docs/build_docs.py）との整合性を取るための補助スクリプト。
"""

from __future__ import annotations
import shutil
import subprocess
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent
SRC_DIR = ROOT / "src"
OUT_DIR = ROOT

MD_FILES = sorted(SRC_DIR.glob("*.md"))

if not MD_FILES:
    print("docs/src に Markdown ファイルが見つかりません。既存の docs/*.pdf が正である場合、追加作業は不要です。")
    print("もしソースから PDF を再生成したい場合は、docs/src に Markdown ファイルを追加してください。")
    sys.exit(0)

# prefer pandoc if available
PANDOC = shutil.which("pandoc")
if not PANDOC:
    print("pandoc が見つかりません。以下のいずれかでインストールしてください:")
    print("  - https://pandoc.org/installing.html")
    print("もしくは reportlab 等を用いた独自スクリプトでの変換を用意してください。")
    sys.exit(2)

print(f"pandoc を使って {len(MD_FILES)} 件の Markdown を PDF に変換します...")
for md in MD_FILES:
    out_pdf = OUT_DIR / (md.stem + ".pdf")
    cmd = [PANDOC, str(md), "-o", str(out_pdf)]
    print("-> ", md.name, "=>", out_pdf.name)
    try:
        subprocess.check_call(cmd)
    except subprocess.CalledProcessError as e:
        print("pandoc による変換でエラーが起きました:", e)
        sys.exit(3)

print("変換が完了しました。docs/ 以下の PDF を確認してください。")
