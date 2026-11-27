//! The todo app's shell: moves data between the kernel, PostgreSQL and JSON.
//! It decides nothing.

use axum::http::StatusCode;
use h5i_app_core::{Kernel, TenantId};
use h5i_app_json::Value as Out;
use h5i_app_pg::{DbError, ReplyCodec, Store, Tx};
use serde::{Deserialize, Serialize};
use todo_kernel as k;

/// Marker type the framework's traits hang off.
pub struct Todos;

impl Kernel for Todos {
    type Principal = k::Principal;
    type Snapshot = k::Snapshot;
    type Command = k::Command;
    type WriteSet = Vec<k::Write>;
    type Reply = k::Reply;
    type Error = k::Error;

    fn tenant(actor: &k::Principal) -> TenantId {
        TenantId(actor.org)
    }

    fn transition(actor: &k::Principal, snap: &k::Snapshot, cmd: &k::Command) -> Result<(Vec<k::Write>, k::Reply), k::Error> {
        k::transition(actor, snap, cmd)
    }

    fn apply(snap: &k::Snapshot, ws: &Vec<k::Write>) -> k::Snapshot {
        k::apply(snap, ws)
    }
}

pub fn principal(org: u64, user: u64) -> k::Principal {
    k::Principal { org, user }
}

// The `todos` and `counters` tables, from the kernel's `schema!`.
todo_kernel::todo_tables!(Todos);

pub struct TodoStore;

impl Store<Todos> for TodoStore {
    fn ddl() -> Vec<String> {
        schema_ddl()
    }

    fn tables() -> Vec<&'static str> {
        schema_tables()
    }

    // Rows decode with the kernel's `decode`; writes go through `sql_writes`.
    // `Storage.lean` proves the store holds what `apply` computes.
    async fn load(tx: &Tx<'_>, t: TenantId) -> Result<k::Snapshot, DbError> {
        schema_load(tx, t).await
    }

    async fn write(tx: &Tx<'_>, t: TenantId, ws: &Vec<k::Write>) -> Result<(), DbError> {
        schema_store(tx, t, ws).await
    }
}

/// The JSON a client sends, e.g. `{"cmd":"add","title":"buy milk"}`.
#[derive(Deserialize)]
#[serde(tag = "cmd", rename_all = "snake_case", deny_unknown_fields)]
enum CommandJson {
    Add { title: String },
    Rename { id: u64, title: String },
    SetDone { id: u64, done: bool },
    Delete { id: u64 },
    List,
}

impl From<CommandJson> for k::Command {
    fn from(c: CommandJson) -> Self {
        match c {
            CommandJson::Add { title } => k::Command::Add { title: title.into_bytes() },
            CommandJson::Rename { id, title } => k::Command::Rename { id, title: title.into_bytes() },
            CommandJson::SetDone { id, done } => k::Command::SetDone { id, completed: done },
            CommandJson::Delete { id } => k::Command::Delete { id },
            CommandJson::List => k::Command::List,
        }
    }
}

fn todo_json(t: &k::Todo) -> Out {
    Out::obj([
        ("id", t.id.into()),
        ("owner", t.owner.into()),
        ("title", Out::Str(t.title.clone())),
        ("done", t.completed.into()),
    ])
}

impl h5i_app_http::Api<Todos> for TodoStore {
    fn decode_command(body: serde_json::Value) -> Result<k::Command, String> {
        serde_json::from_value::<CommandJson>(body).map(Into::into).map_err(|e| e.to_string())
    }

    fn encode_reply(r: &k::Reply) -> Out {
        match r {
            k::Reply::Created(id) => Out::obj([("id", (*id).into())]),
            k::Reply::Done => Out::obj([("ok", true.into())]),
            k::Reply::Todos(ts) => Out::Arr(ts.iter().map(todo_json).collect()),
        }
    }

    fn encode_error(e: &k::Error) -> (StatusCode, Out) {
        let (status, code) = match e {
            k::Error::NotFound => (StatusCode::NOT_FOUND, "not_found"),
            k::Error::Forbidden => (StatusCode::FORBIDDEN, "forbidden"),
            k::Error::BadTitle => (StatusCode::UNPROCESSABLE_ENTITY, "bad_title"),
            k::Error::Overflow => (StatusCode::INTERNAL_SERVER_ERROR, "overflow"),
        };
        (status, h5i_app_http::error_body(code))
    }
}

/// Stored replies for idempotent retries.
#[derive(Serialize, Deserialize)]
enum StoredReply {
    Created(u64),
    Done,
    Todos(Vec<(u64, u64, Vec<u8>, bool)>),
}

impl ReplyCodec<Todos> for TodoStore {
    fn fingerprint(cmd: &k::Command) -> Vec<u8> {
        format!("{cmd:?}").into_bytes()
    }

    fn scope(actor: &k::Principal) -> String {
        format!("u{}", actor.user)
    }

    fn encode(r: &k::Reply) -> Vec<u8> {
        let stored = match r {
            k::Reply::Created(id) => StoredReply::Created(*id),
            k::Reply::Done => StoredReply::Done,
            k::Reply::Todos(ts) => StoredReply::Todos(ts.iter().map(|t| (t.id, t.owner, t.title.clone(), t.completed)).collect()),
        };
        serde_json::to_vec(&stored).expect("stored replies serialize")
    }

    fn decode(b: &[u8]) -> Result<k::Reply, String> {
        Ok(match serde_json::from_slice(b).map_err(|e| e.to_string())? {
            StoredReply::Created(id) => k::Reply::Created(id),
            StoredReply::Done => k::Reply::Done,
            StoredReply::Todos(ts) => k::Reply::Todos(
                ts.into_iter().map(|(id, owner, title, completed)| k::Todo { id, owner, title, completed }).collect(),
            ),
        })
    }
}
