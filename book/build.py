#!/usr/bin/env python3
"""chapters/ch-*.html を template.html に流し込み、book.html を作る。目次は各章の h2 / h3 から作る。"""
import html
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = "https://github.com/muraikenta/formal-todo"
CODE = {"ch-0": "lean-aeneas", "ch-1": "quint-todo", "ch-2": "todo-aeneas", "ch-3": "h5i-todo", "ch-4": "todo/verification"}

def link_caption(m):
    text = m.group(1)
    path = text.split("（")[0].strip()
    if path.startswith(("backend/", "frontend/")):
        path = "nyxis-todo/" + path
    return f'<figcaption><a href="{REPO}/blob/main/{path}">{text}</a></figcaption>'

chapters = sorted((ROOT / "chapters").glob("ch-*.html"), key=lambda p: int(p.stem.split("-")[1]))
tpl = (ROOT / "template.html").read_text(encoding="utf-8")

def strip_tags(s):
    return html.unescape(re.sub(r"<[^>]+>", "", s)).strip()

toc, path, bodies, cards = [], [], [], []
for i, p in enumerate(chapters):
    src = p.read_text(encoding="utf-8").strip()
    m = re.search(r'<section class="chapter" id="(ch-\d+)"', src)
    assert m, f"{p.name}: section.chapter が無い"
    cid = m.group(1)
    h2 = strip_tags(re.search(r"<h2[^>]*>(.*?)</h2>", src, re.S).group(1))
    no, _, name = h2.partition(" ")
    if not no.startswith("第"):
        no, name = "", h2
    # h3 に id を振る（goals / recap の中の h3 は目次に出さない）
    subs = []
    def add_id(mm, counter=[0]):
        attrs, text = mm.group(1), mm.group(2)
        if "id=" in attrs:
            return mm.group(0)
        counter[0] += 1
        hid = f"{cid}-s{counter[0]}"
        t = strip_tags(text)
        if t not in ("この章のゴール", "まとめ"):
            subs.append((hid, t))
        return f'<h3{attrs} id="{hid}">{text}</h3>'
    src = re.sub(r"<h3([^>]*)>(.*?)</h3>", add_id, src, flags=re.S)
    src = re.sub(r"<figcaption>([^<]*)</figcaption>", link_caption, src)
    bodies.append((cid, src))
    sub_html = "".join(f'<li><a href="#{h}">{html.escape(t)}</a></li>' for h, t in subs)
    num = re.sub(r"[^0-9]", "", no) or str(i)
    toc.append(f'<li data-ch="{cid}"><a href="#{cid}"><span class="no">{num}</span><span>{html.escape(name)}</span></a>'
               + (f"<ol>{sub_html}</ol>" if sub_html else "") + "</li>")
    lead = re.search(r'<p class="lead">(.*?)</p>', src, re.S)
    cards.append(f'<li><a href="#{cid}"><span class="no">CHAPTER {num}</span><span class="t">{html.escape(name)}</span><span class="d">{html.escape(strip_tags(lead.group(1))) if lead else ""}</span></a></li>')
    short = ["はじめに", "Quint", "Lean と Rust", "認可", "TLA+ で同期", "まとめ"]
    path.append(f'<a href="#{cid}">{num}. {short[i] if i < len(short) else html.escape(name)}</a>')

ids = [c for c, _ in bodies]
out_chapters = []
for i, (cid, src) in enumerate(bodies):
    def title_of(j):
        return strip_tags(re.search(r"<h2[^>]*>(.*?)</h2>", bodies[j][1], re.S).group(1))
    nav = '<nav class="pager">'
    if i > 0:
        nav += f'<a class="prev" href="#{ids[i-1]}"><small>← 前の章</small>{html.escape(title_of(i-1))}</a>'
    else:
        nav += '<a class="prev" href="#home"><small>← 表紙</small>章の一覧</a>'
    if i < len(ids) - 1:
        nav += f'<a class="next" href="#{ids[i+1]}"><small>次の章 →</small>{html.escape(title_of(i+1))}</a>'
    nav += "</nav>"
    pct = round((i + 1) / len(ids) * 100)
    bar = f'<div class="chapter-bar"><a href="#home">← 表紙</a><span class="meter"><i style="width:{pct}%"></i></span><span>{i+1} / {len(ids)}</span>' + (f'<a class="code-link" href="{REPO}/tree/main/{CODE[cid]}">コードを見る ↗</a>' if cid in CODE else "") + '</div>'
    src = re.sub(r'(<section class="chapter" id="ch-\d+"[^>]*>)', lambda mm: mm.group(1) + bar, src, count=1)
    src = re.sub(r"</section>\s*$", nav + "\n</section>", src)
    out_chapters.append(src)

# 表は横スクロールの入れ物で包む
body = "\n".join(out_chapters)
body = re.sub(r'<div class="table-wrap">\s*(<table.*?</table>)\s*</div>', r"\1", body, flags=re.S)
body = re.sub(r"<table", '<div class="table-wrap"><table', body).replace("</table>", "</table></div>")

res = (tpl.replace("{{TOC}}", "<ol>" + "".join(toc) + "</ol>")
          .replace("{{CARDS}}", "".join(cards))
          .replace("{{CHAPTERS}}", body))
(ROOT / "book.html").write_text(res, encoding="utf-8")
print(f"book.html: {len(chapters)} 章, {len(res):,} bytes")
