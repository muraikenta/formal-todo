//! todo の CLI（画面と保存）。状態の変え方はすべて証明済みの `todo_kernel` に任せる。
//! この層は証明していないので、ファイルから読んだ状態が kernel の前提（不変条件）を満たすかをここで検査する。
//!
//! 使い方: TODO_USER=<ユーザー番号> todo add <題名> | list | toggle <id>（完了⇔未完了） | rm <id>
//! 保存先: 環境変数 TODO_FILE（無ければ ./todos.tsv）
//!
//! 認可（自分の todo にしか効かない・見えない）は kernel が受け持ち、Lean で証明してある。
//! この CLI は「いま誰か」を TODO_USER から読むだけで、本人確認（ログイン）はしない。

use std::collections::HashSet;
use std::{env, fs, io, process};
use todo_kernel::{Todo, Todos};

fn path() -> String {
    env::var("TODO_FILE").unwrap_or_else(|_| "todos.tsv".into())
}

/// 操作しているユーザー。指定が無ければ止める（勝手に誰かとして動かない）。
fn user() -> u32 {
    env::var("TODO_USER").ok().and_then(|s| s.parse().ok())
        .unwrap_or_else(|| die("TODO_USER にユーザー番号を入れて（例: TODO_USER=1）"))
}

/// 1行目に next_id、2行目から `id<TAB>持ち主<TAB>0|1<TAB>題名`。
fn load() -> Todos {
    // ファイルが無いときだけ空から始める。読めないファイルを空とみなすと、最後の保存で全件を消してしまう
    let text = match fs::read_to_string(path()) {
        Ok(t) => t,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return todo_kernel::new(),
        Err(e) => die(&format!("{} を読めない: {e}", path())),
    };
    parse(&text).unwrap_or_else(|m| die(&format!("{} が壊れている: {m}", path())))
}

fn parse(text: &str) -> Result<Todos, String> {
    let mut lines = text.lines();
    let next_id: u32 = lines.next().and_then(|l| l.parse().ok()).ok_or("1行目が next_id ではない")?;
    let mut items = Vec::new();
    for l in lines {
        let mut f = l.splitn(4, '\t');
        let (Some(id), Some(owner), Some(done), Some(title)) = (f.next(), f.next(), f.next(), f.next()) else { return Err("行の形が違う".into()) };
        let id = id.parse().map_err(|_| "id が数でない")?;
        let owner = owner.parse().map_err(|_| "持ち主が数でない")?;
        let done = match done { "0" => false, "1" => true, _ => return Err("完了の列が 0/1 でない".into()) };
        items.push(Todo { id, owner, title: title.to_string(), done });
    }
    let t = Todos { items, next_id };
    check_inv(&t)?;
    Ok(t)
}

/// 証明の前提（Spec.Inv）: id が重複しない・どの id も next_id より小さい。
/// toggle の証明はこれを仮定しているので、外から来た状態は必ずここを通す。
/// （③ next_id ≤ u32 の最大値 は型で成り立つ）
fn check_inv(t: &Todos) -> Result<(), String> {
    let mut seen = HashSet::new();
    for x in &t.items {
        // ① insert は初めての id なら true を返す。false なら重複
        if !seen.insert(x.id) { return Err(format!("id {} が重複している", x.id)) }
        // ② どの id も next_id より小さい
        if x.id >= t.next_id { return Err(format!("id {} が next_id 以上", x.id)) }
    }
    Ok(())
}

/// 保存形式で表せない題名（改行・タブ）。入れると次に読んだとき別の todo に化ける
fn valid_title(s: &str) -> bool {
    !s.is_empty() && !s.contains(['\n', '\r', '\t'])
}

fn save(t: &Todos) {
    let mut s = format!("{}\n", t.next_id);
    for x in &t.items {
        s += &format!("{}\t{}\t{}\t{}\n", x.id, x.owner, if x.done { 1 } else { 0 }, x.title);
    }
    // 書く前に、読み戻すと同じ状態になること（往復）を確かめる。証明の外にある保存層の保険
    let back = parse(&s).unwrap_or_else(|m| die(&format!("保存形式に変換できない: {m}")));
    let same = back.next_id == t.next_id
        && back.items.len() == t.items.len()
        && back.items.iter().zip(&t.items).all(|(a, b)| a.id == b.id && a.owner == b.owner && a.done == b.done && a.title == b.title);
    if !same { die("保存して読み戻すと内容が変わるので保存しない") }
    fs::write(path(), s).unwrap_or_else(|e| die(&e.to_string()));
}

fn die(msg: &str) -> ! {
    eprintln!("エラー: {msg}");
    process::exit(1)
}

fn arg_id(a: Option<String>) -> u32 {
    a.and_then(|s| s.parse().ok()).unwrap_or_else(|| die("id を数で指定して"))
}

fn main() {
    let mut args = env::args().skip(1);
    let me = user();
    let mut t = load();
    match args.next().as_deref() {
        Some("add") => {
            let title = args.collect::<Vec<String>>().join(" ");
            if !valid_title(&title) { die("題名は1文字以上で、改行・タブを含めない") }
            match todo_kernel::add(&mut t, me, title) {
                Some(id) => println!("追加しました: {id}"),
                None => die("id を使い切りました"),
            }
        }
        Some("toggle") => {
            let id = arg_id(args.next());
            if !todo_kernel::toggle(&mut t, me, id) { die(&format!("id {id} はありません")) }
        }
        Some("rm") => {
            let id = arg_id(args.next());
            if !todo_kernel::remove(&mut t, me, id) { die(&format!("id {id} はありません")) }
        }
        Some("list") | None => {}
        Some(c) => die(&format!("知らないコマンド: {c}（add / list / toggle / rm）")),
    }
    save(&t);
    // 見せるのは kernel が「見せてよい」と返した id だけ（visible_ids_only_own で証明済み）
    for id in todo_kernel::visible_ids(&t, me) {
        if let Some(x) = t.items.iter().find(|x| x.id == id) {
            println!("{} [{}] {}", x.id, if x.done { "x" } else { " " }, x.title);
        }
    }
    println!("未完了 {} 件", todo_kernel::open_count(&t, me));
}
