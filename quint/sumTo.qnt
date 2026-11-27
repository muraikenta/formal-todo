// 第5章: rust/src/lib.rs の sum_to を Quint でモデル化する（状態遷移で書く）。
//
//   let mut total = 0; let mut i = 0;
//   while i < n { i += 1; total += i; }   // total があふれたら panic
//   total
//
// Lean（第4章）は「u32・すべての n」で証明した。ここでは整数の幅 MAX と入力 n の範囲を
// 小さくして、状態を実際に動かす（ランダム実行・全状態の網羅）。
module sumTo {
  const MAX: int      // 整数型の最大値（u8 なら 255、u32 なら 4294967295）
  const NMAX: int     // 試す入力 n の上限
  const SWAPPED: bool // true にすると「足す」と「i を進める」の順を入れ替えたバグ版

  var n: int
  var i: int
  var total: int
  var status: str     // "running" | "done" | "overflow"(= panic)

  pure def gauss(k: int): int = k * (k + 1) / 2

  action initWith(k: int): bool = all {
    n' = k, i' = 0, total' = 0, status' = "running",
  }

  // 入力 n は 0..NMAX のどれか（どれが来ても成り立つべき）
  action init = {
    nondet k = 0.to(NMAX).oneOf()
    initWith(k)
  }

  // while の本体を1回まわす
  action loopStep = {
    val newI = i + 1
    val newTotal = if (SWAPPED) total + i else total + newI
    all {
      status == "running",
      i < n,
      if (newTotal > MAX)
        all { status' = "overflow", n' = n, i' = i, total' = total }
      else
        all { status' = "running", n' = n, i' = newI, total' = newTotal },
    }
  }

  // while を抜けて total を返す
  action finish = all {
    status == "running",
    i >= n,
    status' = "done", n' = n, i' = i, total' = total,
  }

  // 終わった後は止まったまま（TLC がデッドロックと言わないように）
  action halted = all {
    status != "running",
    status' = status, n' = n, i' = i, total' = total,
  }

  action step = any { loopStep, finish, halted }

  // ---- 確かめたい性質（不変条件） ----
  // ループ不変条件（Lean の証明で使ったものと同じ）: 2×total = i×(i+1)
  val loopInv = 2 * total == i * (i + 1)
  // 正しく終わったら答えはガウスの公式（Lean の sum_to_correct に当たる）
  val doneIsGauss = status == "done" implies total == gauss(n)
  // panic するのは答えが型に収まらないときだけ（Lean の add_fails の逆向きも含む）
  val overflowOnlyIfTooBig = status == "overflow" implies gauss(n) > MAX
  val neverExceeds = total <= MAX
  val safety = loopInv and doneIsGauss and overflowOnlyIfTooBig and neverExceeds

  // ---- 見てみたい状態（「ここに到達できるか」） ----
  val reachedOverflow = status == "overflow"

  // ---- 具体的なテスト ----
  run sum10Test = initWith(10).then(11.reps(_ => step)).expect(status == "done" and total == 55)
  run sum0Test  = initWith(0).then(step).expect(status == "done" and total == 0)
}

// u8 相当（MAX = 255）: 22 までは収まり、23 で 276 になって panic する
module sumTo_u8 {
  import sumTo(MAX = 255, NMAX = 30, SWAPPED = false).*
}

// バグ版（Lean 第4章で試した「順番の入れ替え」と同じ）
module sumTo_u8_swapped {
  import sumTo(MAX = 255, NMAX = 30, SWAPPED = true).*
}

// 境界版: 255 だと gauss(n) がちょうど MAX になる n が無く、「> を >= に」の書き間違いを
// 見逃す（実測）。gauss(22) = 253 なので MAX = 253 にすると「ちょうど収まる」を通る。
module sumTo_253 {
  import sumTo(MAX = 253, NMAX = 30, SWAPPED = false).*
}
