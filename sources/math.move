/// Implementation of math functions needed for Multi Swap.
module satay::math {
    // Errors codes.

    /// When trying to divide by zero.
    const ERR_DIVIDE_BY_ZERO: u64 = 2000;

    /// Implements: `x` * `y` / `z`.
    public fun mul_div(x: u64, y: u64, z: u64): u64 {
        assert!(z != 0, ERR_DIVIDE_BY_ZERO);
        let r = (x as u128) * (y as u128) / (z as u128);
        (r as u64)
    }

    /// Implements: `x` * `y` / `z`.
    public fun mul_div_u128(x: u128, y: u128, z: u128): u64 {
        assert!(z != 0, ERR_DIVIDE_BY_ZERO);
        let r = x * y / z;
        (r as u64)
    }

    /// Multiple two u64 and get u128, e.g. ((`x` * `y`) as u128).
    public fun mul_to_u128(x: u64, y: u64): u128 {
        (x as u128) * (y as u128)
    }

    /// Returns 10^degree.
    public fun pow_10(degree: u8): u64 {
        let res = 1;
        let i = 0;
        while ({
            i < degree
        }) {
            res = res * 10;
            i = i + 1;
        };
        res
    }
}