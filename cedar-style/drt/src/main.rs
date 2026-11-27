//! 差分テスト（Differential Random Testing）— Cedar 方式
//!
//! 同じ入力を「Rust の本番実装」と「Lean の実行できるモデル」の両方に流し、答えを比べる。
//! Rust 側で panic（u32 のあふれ）したら `fail`、モデル側は答えが u32 に収まらなければ `fail`。
//!
//! 使い方: cargo run --release -- [件数] [seed]
//!   （--release でも Cargo.toml の overflow-checks で、あふれは panic のまま）

use std::io::Write;
use std::panic;
use std::process::{Command, Stdio};

/// 外部クレートを使わない小さな乱数（xorshift64）
struct Rng(u64);
impl Rng {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        self.0
    }
    fn below(&mut self, n: u64) -> u64 {
        self.next() % n
    }
    /// u32 を、境目（0・最大値・あふれる手前）に寄せつつ選ぶ
    fn u32_interesting(&mut self) -> u32 {
        match self.below(6) {
            0 => self.below(16) as u32,
            1 => u32::MAX - self.below(16) as u32,
            2 => (u32::MAX / 2).wrapping_add(self.below(16) as u32).wrapping_sub(8),
            _ => self.next() as u32,
        }
    }
}

#[derive(Clone)]
enum Case {
    Add(u32, u32),
    DoublePlusOne(u32),
    SumTo(u32),
}

impl Case {
    fn query(&self) -> String {
        match self {
            Case::Add(a, b) => format!("add {a} {b}"),
            Case::DoublePlusOne(x) => format!("double_plus_one {x}"),
            Case::SumTo(n) => format!("sum_to {n}"),
        }
    }
    /// Rust の本番実装を呼ぶ。panic したら "fail"
    fn run_rust(&self) -> String {
        let c = self.clone();
        match panic::catch_unwind(move || match c {
            Case::Add(a, b) => jiyuu::add(a, b),
            Case::DoublePlusOne(x) => jiyuu::double_plus_one(x),
            Case::SumTo(n) => jiyuu::sum_to(n),
        }) {
            Ok(v) => format!("ok {v}"),
            Err(_) => "fail".to_string(),
        }
    }
}

fn gen(rng: &mut Rng) -> Case {
    match rng.below(3) {
        0 => Case::Add(rng.u32_interesting(), rng.u32_interesting()),
        1 => Case::DoublePlusOne(rng.u32_interesting()),
        // sum_to はループ回数 = n なので、あふれる境目（n = 92681）の前後に絞る
        _ => Case::SumTo(match rng.below(3) {
            0 => rng.below(64) as u32,
            1 => 92_681 - 8 + rng.below(16) as u32,
            _ => rng.below(200_000) as u32,
        }),
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let n: usize = args.get(1).and_then(|s| s.parse().ok()).unwrap_or(10_000);
    let seed: u64 = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(20261127);
    let model = std::env::var("MODEL_BIN")
        .unwrap_or_else(|_| concat!(env!("CARGO_MANIFEST_DIR"), "/../model/.lake/build/bin/model").to_string());

    panic::set_hook(Box::new(|_| {})); // panic のメッセージを黙らせる（fail として数える）

    let mut rng = Rng(seed.wrapping_mul(2).wrapping_add(1)); // 奇数にする（0 だと xorshift が止まる）。seed | 1 だと 2 と 3 が同じ列になった
    let cases: Vec<Case> = (0..n).map(|_| gen(&mut rng)).collect();

    // モデルは1回だけ起動して、全件をまとめて流す
    let mut child = Command::new(&model)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap_or_else(|e| panic!("モデルを起動できない: {model}: {e}"));
    // 書き込みは別スレッドで（全部書き終えるまで読まないと、出力のパイプが詰まって止まる）
    let mut stdin = child.stdin.take().unwrap();
    let queries: Vec<String> = cases.iter().map(Case::query).collect();
    let writer = std::thread::spawn(move || {
        for q in queries {
            writeln!(stdin, "{q}").unwrap();
        }
    });
    let out = child.wait_with_output().unwrap();
    writer.join().unwrap();
    let model_answers: Vec<String> = String::from_utf8(out.stdout).unwrap().lines().map(str::to_string).collect();
    assert_eq!(model_answers.len(), cases.len(), "モデルの答えの件数が合わない");

    let (mut ok, mut fail, mut mismatch) = (0, 0, 0);
    for (c, m) in cases.iter().zip(&model_answers) {
        let r = c.run_rust();
        if &r != m {
            mismatch += 1;
            if mismatch <= 5 {
                println!("不一致: {:<28} Rust={:<16} モデル={}", c.query(), r, m);
            }
        } else if r.starts_with("ok") {
            ok += 1;
        } else {
            fail += 1;
        }
    }
    println!("件数 {n}（seed {seed}）: 一致 {}（うち成功 {ok}・失敗 {fail}）／ 不一致 {mismatch}", ok + fail);
    if mismatch > 0 {
        std::process::exit(1);
    }
}
