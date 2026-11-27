//! todo アプリのカーネル: 組織の各ユーザーが自分の todo リストを持つ。
//!
//! 誰でも todo を追加でき、追加した人が持ち主になる。名前の変更・完了の切り替え・
//! 削除は持ち主だけができる。一覧は呼び出した本人の todo だけを返す。
//!
//! アプリの判断はすべてこのファイルの `transition` が下す。DB・時計・通信には触らない
//! 純粋な関数なので、h5i が Charon/Aeneas で Lean に翻訳して証明できる。
//! 翻訳できる書き方に寄せている（ループは添字の while、エラーは `?` でなく match、文字列は Vec<u8>）。

pub type Text = Vec<u8>;

/// タイトルの最大長（バイト）。
pub const MAX_TITLE: usize = 140;

/// 呼び出した人: 組織（テナント）と、その中のユーザー。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Principal {
    pub org: u64,
    pub user: u64,
}

h5i_app_schema::schema! {
    mapping todo_tables for todo_kernel, writes Write, lean "../proofs/generated/Schema.lean";

    /// 1つの組織の状態。`schema!` が構造体と DB のテーブル対応を両方作る。
    #[derive(Clone, Debug, Default, PartialEq, Eq)]
    pub struct Snapshot {
        counter: Counter,
        todos: Vec<Todo>,
    }

    #[derive(Clone, Debug, PartialEq, Eq)]
    pub struct Todo in "todos" {
        key { id: u64 }
        owner: u64,
        title: Text,
        completed: bool,
    }

    #[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
    pub struct Counter in "counters" {
        key {}
        next_id: u64,
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Command {
    Add { title: Text },
    Rename { id: u64, title: Text },
    SetDone { id: u64, completed: bool },
    Delete { id: u64 },
    List,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Write {
    PutTodo(Todo),
    DelTodo(u64),
    SetCounter(Counter),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Reply {
    Created(u64),
    Done,
    Todos(Vec<Todo>),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Error {
    NotFound,
    Forbidden,
    BadTitle,
    Overflow,
}

type Outcome = Result<(Vec<Write>, Reply), Error>;

fn one(w: Write) -> Vec<Write> {
    let mut ws = Vec::new();
    ws.push(w);
    ws
}

/// タイトルは空でなく、`MAX_TITLE` バイト以下。
pub fn title_ok(t: &Text) -> bool {
    t.len() > 0 && t.len() <= MAX_TITLE
}

pub fn find_todo(ts: &Vec<Todo>, id: u64) -> Option<Todo> {
    let mut i = 0;
    while i < ts.len() {
        if ts[i].id == id {
            return Some(ts[i].clone());
        }
        i += 1;
    }
    None
}

/// `user` が持っている todo を、保存順で返す。
pub fn todos_of(ts: &Vec<Todo>, user: u64) -> Vec<Todo> {
    let mut out = Vec::new();
    let mut i = 0;
    while i < ts.len() {
        if ts[i].owner == user {
            out.push(ts[i].clone());
        }
        i += 1;
    }
    out
}

fn add(user: u64, s: &Snapshot, title: &Text) -> Outcome {
    if !title_ok(title) {
        return Err(Error::BadTitle);
    }
    let id = s.counter.next_id;
    if id == u64::MAX {
        return Err(Error::Overflow);
    }
    let mut ws = Vec::new();
    ws.push(Write::PutTodo(Todo { id, owner: user, title: title.clone(), completed: false }));
    ws.push(Write::SetCounter(Counter { next_id: id + 1 }));
    Ok((ws, Reply::Created(id)))
}

fn rename(user: u64, s: &Snapshot, id: u64, title: &Text) -> Outcome {
    match find_todo(&s.todos, id) {
        None => Err(Error::NotFound),
        Some(t) => {
            if t.owner != user {
                Err(Error::Forbidden)
            } else if !title_ok(title) {
                Err(Error::BadTitle)
            } else {
                Ok((one(Write::PutTodo(Todo { id, owner: t.owner, title: title.clone(), completed: t.completed })), Reply::Done))
            }
        }
    }
}

fn set_done(user: u64, s: &Snapshot, id: u64, completed: bool) -> Outcome {
    match find_todo(&s.todos, id) {
        None => Err(Error::NotFound),
        Some(t) => {
            if t.owner != user {
                Err(Error::Forbidden)
            } else {
                Ok((one(Write::PutTodo(Todo { id, owner: t.owner, title: t.title, completed })), Reply::Done))
            }
        }
    }
}

fn delete(user: u64, s: &Snapshot, id: u64) -> Outcome {
    match find_todo(&s.todos, id) {
        None => Err(Error::NotFound),
        Some(t) => {
            if t.owner == user {
                Ok((one(Write::DelTodo(id)), Reply::Done))
            } else {
                Err(Error::Forbidden)
            }
        }
    }
}

/// アプリの判断のすべて: コマンドに対する「書き込みの一覧と返事」か、
/// 何も書かない「拒否」を返す。
pub fn transition(actor: &Principal, s: &Snapshot, cmd: &Command) -> Outcome {
    match cmd { // どの枝も、操作した人 actor.user で判断する
        Command::Add { title } => add(actor.user, s, title),
        Command::Rename { id, title } => rename(actor.user, s, *id, title),
        Command::SetDone { id, completed } => set_done(actor.user, s, *id, *completed),
        Command::Delete { id } => delete(actor.user, s, *id),
        Command::List => Ok((Vec::new(), Reply::Todos(todos_of(&s.todos, actor.user)))), // 何も書かず本人の分だけ返す
    }
}

/// 書き込み1つが状態をどう変えるか。`schema!` がこれから `apply` を作る。
fn apply_write(s: &mut Snapshot, w: Write) {
    match w {
        Write::PutTodo(t) => Todo::put(&mut s.todos, t),
        Write::DelTodo(id) => s.todos = Todo::del(&s.todos, id),
        Write::SetCounter(c) => s.counter = c,
    }
}

/// 書き込み1つが DB に出す SQL。`Storage.lean` が、これで保存したものと
/// `apply` の結果が一致することを証明している。
fn sql_write(w: &Write, out: &mut Vec<h5i_app_sql::Write>) {
    match w {
        Write::PutTodo(t) => out.push(t.sql_put()),
        Write::DelTodo(id) => out.push(Todo::sql_del(*id)),
        Write::SetCounter(c) => out.push(c.sql_put()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(s: &Snapshot, user: u64, c: Command) -> (Snapshot, Result<Reply, Error>) {
        match transition(&Principal { org: 1, user }, s, &c) {
            Ok((ws, r)) => (apply(s, &ws), Ok(r)),
            Err(e) => (s.clone(), Err(e)),
        }
    }

    #[test]
    fn owners_only() {
        let s = Snapshot::default();
        let (s, r) = run(&s, 1, Command::Add { title: b"buy milk".to_vec() });
        assert_eq!(r, Ok(Reply::Created(0)));
        let (s, r) = run(&s, 2, Command::Add { title: b"write report".to_vec() });
        assert_eq!(r, Ok(Reply::Created(1)));
        assert_eq!(run(&s, 2, Command::SetDone { id: 0, completed: true }).1, Err(Error::Forbidden));
        assert_eq!(run(&s, 2, Command::Delete { id: 0 }).1, Err(Error::Forbidden));
        assert_eq!(run(&s, 1, Command::Add { title: Vec::new() }).1, Err(Error::BadTitle));
        let (s, r) = run(&s, 1, Command::SetDone { id: 0, completed: true });
        assert_eq!(r, Ok(Reply::Done));
        match run(&s, 1, Command::List).1 {
            Ok(Reply::Todos(ts)) => {
                assert_eq!(ts.len(), 1);
                assert!(ts[0].completed);
            }
            other => panic!("{other:?}"),
        }
        let (s, _) = run(&s, 1, Command::Delete { id: 0 });
        assert_eq!(s.todos.len(), 1);
        assert_eq!(s.todos[0].owner, 2);
    }
}
