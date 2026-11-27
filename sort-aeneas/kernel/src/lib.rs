//! 挿入ソート（その場で並べ替える）。Charon → Aeneas で Lean に翻訳して、`../lean/Spec.lean` の仕様どおりであることを証明する。

/// `v[..i]` が並んでいるとき、`v[i]` を左へ1つずつ入れ替えながら正しい位置まで沈める。
/// 終わると `v[..=i]` が並ぶ。前提（`i < v.len()`・`v[..i]` が並んでいる）があるので外には出さない。
fn insert(v: &mut [u32], i: usize) {
    let mut j = i; // j は沈めている値の今の位置
    while j > 0 && v[j - 1] > v[j] { // 左隣のほうが大きい間だけ続ける
        v.swap(j - 1, j);
        j -= 1;
    }
}

/// 挿入ソート: 左から1つずつ、並んでいる部分に差し込む。
pub fn insertion_sort(v: &mut [u32]) {
    let n = v.len();
    let mut i = 1; // 先頭の1つは、それだけで並んでいる
    while i < n {
        insert(v, i); // v[i] を左の並んだ部分に差し込む
        i += 1;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sorts() {
        for input in [vec![], vec![1], vec![3, 1, 2], vec![2, 1, 2], vec![5, 4, 3, 2, 1], vec![u32::MAX, 0]] {
            let mut v = input.clone();
            insertion_sort(&mut v);
            let mut expected = input.clone();
            expected.sort();
            assert_eq!(v, expected);
        }
    }
}
