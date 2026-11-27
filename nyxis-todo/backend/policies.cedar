// Todo アプリの Cedar ポリシー。ここに書いていない操作はすべて拒否（Cedar の既定は deny）。
// 主体は JWT から、対象は DB の今の行（insert / update では提案された値）から Nyxis が決める。

// Todo の読み取り・一覧・名前変更・完了切り替え・削除は、持ち主だけ。
@id("own-todo")
permit (
  principal is User,
  action in [Action::"listTodos", Action::"readTodo", Action::"renameTodo", Action::"setDone", Action::"deleteTodo"],
  resource is Todo
) when { resource.owner == principal };

// Todo は自分を持ち主にしてしか作れない。
@id("create-own-todo")
permit (
  principal is User,
  action == Action::"createTodo",
  resource is Todo
) when { resource.owner == principal };

// User 行は自分の分しか作れない・読めない。
@id("self-user")
permit (
  principal is User,
  action in [Action::"registerUser", Action::"readUser"],
  resource is User
) when { resource == principal };
