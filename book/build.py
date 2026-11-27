#!/usr/bin/env python3
"""chapters/ch-*.html（本編）と app-*.html（付録）を template.html に流し込み、book.html を作る。目次は各章の h2 / h3 から作る。"""
import html
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = "https://github.com/muraikenta/formal-todo"
CODE = {"ch-0": "sort-aeneas", "ch-1": "todo-aeneas", "ch-2": "todo-aeneas", "app-f": "quint-todo", "app-e": "h5i-todo", "app-d": "todo/verification", "app-b": "nyxis-todo"}

MERMAID_INIT = ('%%{init: {"theme": "base", "themeVariables": {'
                '"background": "#ffffff", "primaryColor": "#e3f1ec", "primaryTextColor": "#16201d", '
                '"primaryBorderColor": "#0f6b55", "secondaryColor": "#f6f8f7", "tertiaryColor": "#ffffff", '
                '"lineColor": "#4b5a55", "textColor": "#16201d", "edgeLabelBackground": "#ffffff", '
                '"clusterBkg": "#f6f8f7", "clusterBorder": "#d9e1de", "noteBkgColor": "#fbeee4", "noteTextColor": "#16201d", '
                '"actorBkg": "#e3f1ec", "actorBorder": "#0f6b55", "actorTextColor": "#16201d", "signalColor": "#16201d", '
                '"signalTextColor": "#16201d", "labelBoxBkgColor": "#e3f1ec", "labelTextColor": "#16201d", '
                '"fontFamily": "Noto Sans JP, sans-serif"}}}%%\n')

def link_caption(m):
    text = m.group(1)
    path = text.split("（")[0].strip()
    if path == "例":
        return f"<figcaption>{text}</figcaption>"
    if "Nyxis 本体" in text:
        return f'<figcaption><a href="https://github.com/NyxFoundation/nyxis/blob/df5c9ac/{path}">{text}</a></figcaption>'
    if path.startswith("lean-pq/"):
        return f'<figcaption><a href="https://github.com/typednotes/lean-pq">{text}</a></figcaption>'
    if path.startswith(("backend/", "frontend/")):
        path = "nyxis-todo/" + path
    return f'<figcaption><a href="{REPO}/blob/main/{path}">{text}</a></figcaption>'

chapters = ([p for p in [ROOT / "chapters" / "quick.html"] if p.exists()]
            + sorted((ROOT / "chapters").glob("ch-*.html"), key=lambda p: int(p.stem.split("-")[1]))
            + sorted((ROOT / "chapters").glob("app-*.html")))
tpl = (ROOT / "template.html").read_text(encoding="utf-8")

def strip_tags(s):
    return html.unescape(re.sub(r"<[^>]+>", "", s)).strip()

toc, path, bodies, cards = [], [], [], []
for i, p in enumerate(chapters):
    src = p.read_text(encoding="utf-8").strip()
    m = re.search(r'<section class="chapter" id="((?:ch|app)-[\w]+|quick)"', src)
    assert m, f"{p.name}: section.chapter が無い"
    cid = m.group(1)
    h2 = strip_tags(re.search(r"<h2[^>]*>(.*?)</h2>", src, re.S).group(1))
    no, _, name = h2.partition(" ")
    appendix = cid.startswith("app-")
    if cid == "quick":
        no, name, num = "", h2, "★"
    elif appendix and no.startswith("付録"):
        num = no.replace("付録", "")
    elif no.startswith("第"):
        num = re.sub(r"[^0-9]", "", no) or str(i)
    else:
        no, name, num = "", h2, str(i)
    # h3 に id を振る（goals / recap の中の h3 は目次に出さない）
    subs = []
    def add_id(mm, counter=[0]):
        attrs, text = mm.group(1), mm.group(2)
        if "id=" in attrs:
            return mm.group(0)
        counter[0] += 1
        hid = f"{cid}-s{counter[0]}"
        t = strip_tags(text)
        if t not in ("この章のゴール", "この付録のゴール", "まとめ"):
            subs.append((hid, t))
        return f'<h3{attrs} id="{hid}">{text}</h3>'
    src = re.sub(r"<h3([^>]*)>(.*?)</h3>", add_id, src, flags=re.S)
    src = re.sub(r"<figcaption>([^<]*)</figcaption>", link_caption, src)
    # mermaid の図は配色をライトに固定する（ビューアの配色に引きずられて文字が読めなくなるため）
    # ビューア任せにすると暗い配色で描かれるので、自前で描く（class を mermaid 以外にする）
    src = src.replace('<pre class="mermaid">', '<pre class="mm">')
    bodies.append((cid, src))
    sub_html = "".join(f'<li><a href="#{h}">{html.escape(t)}</a></li>' for h, t in subs)
    if appendix and not any("toc-group" in x for x in toc):
        toc.append('<li class="toc-group">付録</li>')
        cards.append('<li class="cards-group">付録（ほかの道具）</li>')
    toc.append(f'<li data-ch="{cid}"><a href="#{cid}"><span class="no">{num}</span><span>{html.escape(name)}</span></a>'
               + (f"<ol>{sub_html}</ol>" if sub_html else "") + "</li>")
    lead = re.search(r'<p class="lead">(.*?)</p>', src, re.S)
    cards.append(f'<li><a href="#{cid}"><span class="no">{"APPENDIX " + num if appendix else ("SUMMARY · 5分で読む" if cid == "quick" else "CHAPTER " + num)}</span><span class="t">{html.escape(name)}</span><span class="d">{html.escape(strip_tags(lead.group(1))) if lead else ""}</span></a></li>')

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
    n_main = sum(1 for x in ids if x.startswith("ch-"))
    pos = ("付録 " + cid[-1].upper()) if cid.startswith("app-") else ("要約" if cid == "quick" else f"{ids.index(cid) - ids.index('ch-0') + 1} / {n_main}")
    bar = f'<div class="chapter-bar"><a href="#home">← 表紙</a><span class="meter"><i style="width:{pct}%"></i></span><span>{pos}</span>' + (f'<a class="code-link" href="{REPO}/tree/main/{CODE[cid]}">コードを見る ↗</a>' if cid in CODE else "") + '</div>'
    src = re.sub(r'(<section class="chapter" id="(?:(?:ch|app)-\w+|quick)"[^>]*>)', lambda mm: mm.group(1) + bar, src, count=1)
    src = re.sub(r"</section>\s*$", nav + "\n</section>", src)
    out_chapters.append(src)

# 表は横スクロールの入れ物で包む
body = "\n".join(out_chapters)
body = re.sub(r'<div class="table-wrap">\s*(<table.*?</table>)\s*</div>', r"\1", body, flags=re.S)
body = re.sub(r"<table", '<div class="table-wrap"><table', body).replace("</table>", "</table></div>")

toc.insert(0, '<li data-ch="home"><a href="#home"><span class="no">◇</span><span>表紙・章の一覧</span></a></li>')
res = (tpl.replace("{{TOC}}", "<ol>" + "".join(toc) + "</ol>")
          .replace("{{CARDS}}", "".join(cards))
          .replace("{{CHAPTERS}}", body))
(ROOT / "book.html").write_text(res, encoding="utf-8")
print(f"book.html: {len(chapters)} 章, {len(res):,} bytes")
