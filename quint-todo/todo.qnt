// 第6章: Todo アプリの仕様を Quint で書く。
//
// 画面の操作（追加・完了の切り替え・削除・編集・全部切り替え・完了済みを消す）を
// 「状態（todos, nextId）と遷移」で書き、壊れてはいけない性質を不変条件にする。
// 同じ仕様から作った実行列（ITF トレース）を、本物のアプリの中身（app/todo-core.mjs）に
// 1歩ずつ流して突き合わせる（mbt.mjs）。
//
// 不変条件は2種類:
//   形の性質   … 1つの状態だけで言えること（id がかぶらない・題名が空でない 等）
//   前後の性質 … 直前の状態と比べて言えること（toggle は対象の1件の done だけを変え、他には触らない 等）
// 形の性質だけだと「全部消す」「何もしない」のような誤りを通してしまう（独立レビューで 17本中16本を見逃した）。
module todo {
  const MAX_ID: int                // 試す範囲の上限: 追加できるのは id が MAX_ID 未満の間だけ（アプリ側に上限は無い）
  const INPUTS: str -> str         // 入力欄に打たれる生の文字列 → 前後の空白を取った題名（Quint に trim が無いので表で渡す）
  const BUG: str                   // "none" | "idFromLength"（id を「いまの件数」で振る、よくある書き間違い）

  // 1件の todo: 番号・題名・完了したか
  type Todo = { id: int, title: str, done: bool }

  var todos: List[Todo]    // 画面に並ぶ順
  var nextId: int          // 次に振る id
  // 以下は「前後の性質」を書くための記録（アプリには無い）
  var lastAction: str      // 直前の操作の名前（"add" など）
  var lastId: int          // 直前の操作の対象 id
  var lastTitle: str       // 直前の操作の題名（空白を取った後）
  var prevTodos: List[Todo]  // 直前の操作をする前の todos
  var prevNextId: int        // 直前の操作をする前の nextId

  // ---- 補助 ----
  pure def idsOf(ts: List[Todo]): Set[int] = ts.indices().map(i => ts[i].id)
  pure def mapTodos(ts: List[Todo], f: Todo => Todo): List[Todo] =
    ts.foldl(List(), (acc, t) => acc.append(f(t)))
  pure def allDone(ts: List[Todo]): bool = ts.indices().forall(i => ts[i].done)
  pure def noneDone(ts: List[Todo]): bool = ts.indices().forall(i => not(ts[i].done))
  pure def sameIds(a: List[Todo], b: List[Todo]): bool =
    a.length() == b.length() and a.indices().forall(i => a[i].id == b[i].id)
  // cur の各要素は、prev にある同じ id の要素とまったく同じ（並びの性質は idsAscending が見る）
  pure def eachUnchangedFrom(cur: List[Todo], prev: List[Todo]): bool =
    cur.indices().forall(i => prev.indices().exists(j => prev[j] == cur[i]))

  action record(name: str, id: int, title: str): bool = all {
    lastAction' = name, lastId' = id, lastTitle' = title,
    prevTodos' = todos, prevNextId' = nextId,
  }

  action initState = all {
    todos' = List(), nextId' = 0,
    lastAction' = "init", lastId' = -1, lastTitle' = "", prevTodos' = List(), prevNextId' = 0,
  }
  action init = initState

  // ---- 操作（引数 raw は入力欄の生の文字列） ----
  // 追加: 空白を取って空になるものは弾く（何も変わらない）
  action add(raw: str): bool = {
    // 生の入力を、空白を取った題名に変える（表で引く）
    val title = INPUTS.get(raw)
    all {
      // 試す範囲の上限: nextId が MAX_ID 未満の間だけ追加できる
      nextId < MAX_ID,
      // 検査用に「直前は add、題名は title」と記録する
      record("add", -1, title),
      // 空欄なら todos も nextId もそのまま
      if (title == "")
        all { todos' = todos, nextId' = nextId }
      else {
        // 普段は nextId を振る（BUG 版だけ「いまの件数」を振る）
        val newId = if (BUG == "idFromLength") todos.length() else nextId
        // 末尾に未完了で1件足し、nextId を1進める
        all {
          todos' = todos.append({ id: newId, title: title, done: false }),
          nextId' = nextId + 1,
        }
      },
    }
  }

  // 完了の切り替え（無い id なら何もしない）
  action toggle(id: int): bool = all {
    todos' = mapTodos(todos, t => if (t.id == id) { ...t, done: not(t.done) } else t),
    nextId' = nextId,
    record("toggle", id, ""),
  }

  // 削除（無い id なら何もしない）
  action remove(id: int): bool = all {
    todos' = todos.select(t => t.id != id),
    nextId' = nextId,
    record("remove", id, ""),
  }

  // 題名の編集: 空白を取って空になったら削除（TodoMVC と同じ決まり）
  action edit(id: int, raw: str): bool = {
    val title = INPUTS.get(raw)
    all {
      todos' = if (title == "") todos.select(t => t.id != id)
               else mapTodos(todos, t => if (t.id == id) { ...t, title: title } else t),
      nextId' = nextId,
      record("edit", id, title),
    }
  }

  // 全部切り替え: 全部完了なら全部未完了に、1つでも未完了があれば全部完了に
  action toggleAll: bool = {
    val target = not(allDone(todos))
    all {
      todos' = mapTodos(todos, t => { ...t, done: target }),
      nextId' = nextId,
      record("toggleAll", -1, ""),
    }
  }

  // 完了済みを消す
  action clearCompleted: bool = all {
    todos' = todos.select(t => not(t.done)),
    nextId' = nextId,
    record("clearCompleted", -1, ""),
  }

  // id は「いまある id」だけでなく範囲全体から選ぶ（無い id への操作が無害かも確かめる）
  action step = {
    nondet raw = INPUTS.keys().oneOf()      // 入力欄の文字列を候補から1つ選ぶ
    nondet id = 0.to(MAX_ID - 1).oneOf()    // 対象の id を 0〜MAX_ID-1 から1つ選ぶ
    // 次の6つのどれか1つが起きる
    any {
      add(raw),
      toggle(id),
      remove(id),
      edit(id, raw),
      toggleAll,
      clearCompleted,
    }
  }

  // ---- 形の性質（1つの状態で言えること） ----
  // id がかぶらない（id の種類の数 ＝ 件数）
  val idsUnique = idsOf(todos).size() == todos.length()
  // id は並び順に増えていく（追加は末尾・他の操作は順番を変えない）
  val idsAscending = todos.indices().forall(i => i == 0 or todos[i - 1].id < todos[i].id)
  // 振った id は nextId 未満（次に振る id がすでに使われていない）
  val idsFresh = todos.indices().forall(i => todos[i].id < nextId)
  // 題名が空の todo は無い
  val noEmptyTitles = todos.indices().forall(i => todos[i].title != "")
  // 保存される題名は必ず「空白を取った後」の形（生の入力のまま入っていない）
  val titlesNormalized = todos.indices().forall(i => INPUTS.keys().map(k => INPUTS.get(k)).contains(todos[i].title))
  // 形の性質を全部まとめたもの
  val shapeOk = idsUnique and idsAscending and idsFresh and noEmptyTitles and titlesNormalized

  // ---- 前後の性質（直前の状態と比べて言えること） ----
  // nextId は追加が通ったときだけ1進み、それ以外では変わらない（減らない＝id を使い回さない）
  val nextIdOk =
    if (lastAction == "add" and lastTitle != "") nextId == prevNextId + 1 else nextId == prevNextId
  val addOk = lastAction == "add" implies (
    if (lastTitle == "") todos == prevTodos
    else all {
      todos.length() == prevTodos.length() + 1,
      prevTodos.indices().forall(i => todos[i] == prevTodos[i]),         // 既存はそのまま
      todos[todos.length() - 1] == { id: prevNextId, title: lastTitle, done: false }, // 末尾に1件
    })
  // 直前の操作が toggle なら、次の3つが全部成り立つ
  val toggleOk = lastAction == "toggle" implies all {
    sameIds(todos, prevTodos),                                          // id の並びは前と同じ（増えも減りもしない）
    todos.indices().forall(i => todos[i].title == prevTodos[i].title),  // 題名はどれも変わらない
    // 対象 id の1件だけ done が反転し、他の done は前のまま
    todos.indices().forall(i =>
      todos[i].done == (if (prevTodos[i].id == lastId) not(prevTodos[i].done) else prevTodos[i].done)),
  }
  val removeOk = lastAction == "remove" implies all {
    idsOf(todos) == idsOf(prevTodos).exclude(Set(lastId)),
    eachUnchangedFrom(todos, prevTodos),
  }
  val editOk = lastAction == "edit" implies (
    if (lastTitle == "") all {
      idsOf(todos) == idsOf(prevTodos).exclude(Set(lastId)),
      eachUnchangedFrom(todos, prevTodos),
    } else all {
      sameIds(todos, prevTodos),
      todos.indices().forall(i => todos[i].done == prevTodos[i].done),
      todos.indices().forall(i =>
        todos[i].title == (if (prevTodos[i].id == lastId) lastTitle else prevTodos[i].title)),
    })
  val toggleAllOk = lastAction == "toggleAll" implies all {
    sameIds(todos, prevTodos),
    todos.indices().forall(i => todos[i].title == prevTodos[i].title),
    if (allDone(prevTodos)) noneDone(todos) else allDone(todos),
  }
  val clearOk = lastAction == "clearCompleted" implies all {
    idsOf(todos) == prevTodos.indices().filter(i => not(prevTodos[i].done)).map(i => prevTodos[i].id),
    eachUnchangedFrom(todos, prevTodos),
  }
  // 操作ごとの前後の性質をまとめたもの
  val stepOk = nextIdOk and addOk and toggleOk and removeOk and editOk and toggleAllOk and clearOk

  // 検査に渡す不変条件: 形の性質 ＋ 前後の性質
  val safety = shapeOk and stepOk

  // ---- 到達できるか見たい状態（not(...) を不変条件として渡すと実例が出る） ----
  val fullAndAllDone = todos.length() == MAX_ID and allDone(todos)

  // ---- 具体的なテスト ----
  // "milk" と " milk " を足して全部切り替え → 2件とも完了、2件目の題名も "milk"
  run addTwoThenToggleAllTest =
    initState.then(add("milk")).then(add(" milk ")).then(toggleAll)
      .expect(todos.length() == 2 and allDone(todos) and todos[1].title == "milk")
  // 空欄・半角空白・全角空白は弾かれ、件数も nextId も 0 のまま
  run emptyTitleRejectedTest =
    initState.then(add("")).then(add(" ")).then(add("　")).expect(todos.length() == 0 and nextId == 0)
  run editToEmptyDeletesTest =
    initState.then(add("milk")).then(edit(0, " ")).expect(todos.length() == 0)
  run toggleAllTwiceRestoresTest =
    initState.then(add("milk")).then(toggle(0)).then(add("Milk")).then(toggleAll).then(toggleAll)
      .expect(noneDone(todos))
}

// 入力の候補: 空欄・空白だけ・全角空白だけ・前後に空白・大文字・日本語（全角空白で囲む）・長い題名
module inputs {
  // 左が入力欄に打たれる文字列、右が空白を取った後の題名
  pure val INPUTS_STD = Map(
    "" -> "",
    " " -> "",     // 半角空白だけ → 空
    "　" -> "",    // 全角空白だけ → 空
    "milk" -> "milk",
    " milk " -> "milk",
    "Milk" -> "Milk",   // 大文字は変えない
    "　牛乳を買う　" -> "牛乳を買う",
    "a very long title that keeps going and going" -> "a very long title that keeps going and going",
  )
}

// TLC で全網羅する版: id は 0〜3 まで（4件まで追加できる）
module todo4 {
  import inputs.*
  // 定数を埋めて todo を取り込む（上限 4・標準の入力・バグなし）
  import todo(MAX_ID = 4, INPUTS = INPUTS_STD, BUG = "none").*
}

// MBT のトレースを作る版: 範囲を広げる（4 で区切ると「5件目で壊れる」実装を見逃した）
module todo7 {
  import inputs.*
  // 上限だけ 7 にした同じ仕様
  import todo(MAX_ID = 7, INPUTS = INPUTS_STD, BUG = "none").*
}

// バグ版: id を「いまの件数」で振る。削除の後に追加すると id がかぶる
module todo4_idFromLength {
  import inputs.*
  import todo(MAX_ID = 4, INPUTS = INPUTS_STD, BUG = "idFromLength").*
}

// 仕様の変異テスト（mutate-spec.mjs）で TLC を速く回すための小さい版
module todo3 {
  import inputs.*
  import todo(MAX_ID = 3, INPUTS = INPUTS_STD, BUG = "none").*
}
