//! Lean で正しさを証明する対象の Rust コード。
//! Aeneas（Charon 経由）で Lean の定義に変換し、`../lean-aeneas/` で証明する。

/// 足し算。u32 なので 2^32 - 1 を超えるとあふれる（debug ビルドでは panic）。
pub fn add(a: u32, b: u32) -> u32 {
    a + b
}

/// 2倍して1を足す。
pub fn double_plus_one(x: u32) -> u32 {
    add(x, x) + 1
}

/// 1 + 2 + ... + n をループで計算する。
/// 証明したいこと: 結果は n(n+1)/2（ガウスの公式）。
pub fn sum_to(n: u32) -> u32 {
    let mut total = 0;
    let mut i = 0;
    while i < n {
        i += 1;
        total += i;
    }
    total
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn it_works() {
        assert_eq!(add(2, 3), 5);
        assert_eq!(double_plus_one(10), 21);
        assert_eq!(sum_to(10), 55);
    }
}
