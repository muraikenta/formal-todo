//! todo アプリの中核（状態の変え方と認可）。ここだけを Aeneas で Lean に翻訳し、
//! `../lean/Spec.lean`（人が先に書いた仕様）と一致することを `../lean/Proofs.lean` で証明する。
//! 画面・保存（`../cli`）は証明しない。
//!
//! 認可: どの操作も「誰が操作したか（user）」を受け取り、自分が持ち主の todo にしか効かない。

pub struct Todo {
    pub id: u32,
    pub owner: u32,
    pub title: String,
    pub done: bool,
}

pub struct Todos {
    pub items: Vec<Todo>,
    pub next_id: u32,
}

/// 空の todo リスト。
pub fn new() -> Todos {
    Todos { items: Vec::new(), next_id: 0 }
}

/// user が持ち主の未完了の todo を末尾に足し、振った id を返す。id を使い切ったら何もせず None。
pub fn add(t: &mut Todos, user: u32, title: String) -> Option<u32> {
    if t.next_id == u32::MAX {
        return None;
    }
    let id = t.next_id;
    t.items.push(Todo { id, owner: user, title, done: false });
    t.next_id = id + 1;
    Some(id)
}

/// id の todo の完了／未完了を切り替える。user が持ち主のときだけ効き、効いたら true。
pub fn toggle(t: &mut Todos, user: u32, id: u32) -> bool {
    let mut i = 0;
    while i < t.items.len() && t.items[i].id != id {
        i += 1;
    }
    if i < t.items.len() && t.items[i].owner == user {
        t.items[i].done = !t.items[i].done;
        true
    } else {
        false
    }
}

/// id の todo を消す。user が持ち主のときだけ効き、消えたら true。
pub fn remove(t: &mut Todos, user: u32, id: u32) -> bool {
    let old = std::mem::replace(&mut t.items, Vec::new());
    let n = old.len();
    let mut kept = Vec::new();
    for item in old {
        if !(item.id == id && item.owner == user) {
            kept.push(item);
        }
    }
    let removed = kept.len() < n;
    t.items = kept;
    removed
}

/// user の未完了の件数。
pub fn open_count(t: &Todos, user: u32) -> usize {
    let mut count = 0;
    let mut i = 0;
    while i < t.items.len() {
        if !t.items[i].done && t.items[i].owner == user {
            count += 1;
        }
        i += 1;
    }
    count
}

/// user に見せてよい todo の id（自分が持ち主のものだけ。並びは保存順）。
pub fn visible_ids(t: &Todos, user: u32) -> Vec<u32> {
    let mut ids = Vec::new();
    let mut i = 0;
    while i < t.items.len() {
        if t.items[i].owner == user {
            ids.push(t.items[i].id);
        }
        i += 1;
    }
    ids
}

#[cfg(test)]
mod tests {
    use super::*;
    const ALICE: u32 = 1;
    const BOB: u32 = 2;
    #[test]
    fn basic() {
        let mut t = new();
        assert_eq!(add(&mut t, ALICE, "牛乳".into()), Some(0));
        assert_eq!(add(&mut t, ALICE, "卵".into()), Some(1));
        assert_eq!(open_count(&t, ALICE), 2);
        assert!(toggle(&mut t, ALICE, 0));
        assert_eq!(open_count(&t, ALICE), 1);
        assert!(!toggle(&mut t, ALICE, 9));
        assert!(remove(&mut t, ALICE, 1));
        assert!(!remove(&mut t, ALICE, 1));
        assert_eq!(t.items.len(), 1);
    }
    #[test]
    fn others_cannot_touch() {
        let mut t = new();
        add(&mut t, ALICE, "a".into());
        add(&mut t, BOB, "b".into());
        assert!(!toggle(&mut t, BOB, 0));
        assert_eq!(visible_ids(&t, BOB), vec![1]);
        assert_eq!(open_count(&t, BOB), 1);
    }
}
