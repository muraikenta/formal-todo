// Todo アプリの中身（画面から切り離した状態遷移）。画面（index.html）とモデルベーステスト（../mbt.mjs）の両方がこれを読む。
// 仕様は ../todo.qnt。操作1つが Quint の action 1つに対応する。

/** @typedef {{ id: number, title: string, done: boolean }} Todo */
/** @typedef {{ todos: Todo[], nextId: number }} State */

/** @returns {State} */
export function initialState() {
  return { todos: [], nextId: 0 };
}

/**
 * @param {State} state
 * @param {{ type: string, id?: number, title?: string }} action
 * @returns {State}
 */
export function reduce(state, action) {
  // 操作の種類ごとに次の状態を返す（元の state は書き換えない）
  switch (action.type) {
    case "add": {
      const title = (action.title ?? "").trim();
      if (title === "") return state; // 空欄は弾く
      // 末尾に未完了で1件足し、次に振る id を1進める
      return {
        todos: [...state.todos, { id: state.nextId, title, done: false }],
        nextId: state.nextId + 1,
      };
    }
    case "toggle":
      return {
        ...state,
        todos: state.todos.map((t) => (t.id === action.id ? { ...t, done: !t.done } : t)),
      };
    case "remove":
      return { ...state, todos: state.todos.filter((t) => t.id !== action.id) };
    case "edit": {
      const title = (action.title ?? "").trim();
      if (title === "") return reduce(state, { type: "remove", id: action.id }); // 空欄にしたら削除
      return {
        ...state,
        todos: state.todos.map((t) => (t.id === action.id ? { ...t, title } : t)),
      };
    }
    case "toggleAll": {
      const target = !state.todos.every((t) => t.done);
      return { ...state, todos: state.todos.map((t) => ({ ...t, done: target })) };
    }
    case "clearCompleted":
      return { ...state, todos: state.todos.filter((t) => !t.done) };
    default:
      throw new Error(`unknown action: ${action.type}`);
  }
}

/** 未完了の件数（画面の「残り N 件」） */
export function remaining(state) {
  return state.todos.filter((t) => !t.done).length;
}
