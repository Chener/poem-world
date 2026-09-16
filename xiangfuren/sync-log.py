#!/usr/bin/env python3
"""把 log.jsonl 内联进 index.html 的 <script id="log-fallback">，
这样直接用 file:// 打开 index.html（fetch 被 CORS 挡掉）时，时间线依然有内容。"""
import re, pathlib, sys
d = pathlib.Path(__file__).parent
log = (d / "log.jsonl").read_text(encoding="utf-8").strip()
p = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else d / "index.html"
s = p.read_text(encoding="utf-8")
START, END = "<!--log-fallback-start-->", "<!--log-fallback-end-->"
i, j = s.index(START), s.index(END)
block = (START + '\n<script type="application/x-ndjson" id="log-fallback">\n'
         + log + "\n</script>\n")
p.write_text(s[:i] + block + s[j:], encoding="utf-8")
print("inlined %d rows -> %s" % (len(log.splitlines()), p))
