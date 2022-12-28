/// Implementation of math functions needed for Multi Swap.
module satay::math {


    // constants
    const MAX_U64: u128 = 18446744073709551615;

    // Errors codes.

    /// When trying to divide by zero.
    const ERR_DIVIDE_BY_ZERO: u64 = 2000;
    const ERR_NOT_PROPORTION: u64 = 2001;

    /// Multiple two u64 and get u128, e.g. ((`x` * `y`) as u128).
    public fun mul_to_u128(x: u64, y: u64): u128 {
        (x as u128) * (y as u128)
    }

    /// Implements: `x` * `y` / `z`.
    public fun mul_div(x: u64, y: u64, z: u64): u128 {
        assert!(z != 0, ERR_DIVIDE_BY_ZERO);
        (x as u128) * (y as u128) / (z as u128)
    }

    /// Implements: `x` * `y` / `z`
    public fun mul_div_u128(x: u128, y: u128, z: u128): u256 {
        assert!(z != 0, ERR_DIVIDE_BY_ZERO);
        (x as u256) * (y as u256) / (z as u256)
    }

    public fun calculate_proportion_of_u64_with_u64(x: u64, numerator: u64, denominator: u64): u64 {
        // ensures that return value is not greater than u64::max_value()
        assert!(denominator > numerator, ERR_NOT_PROPORTION);
        (mul_div(x, numerator, denominator) as u64)
    }

    public fun calculate_proportion_of_u64_with_u128(x: u64, numerator: u128, denominator: u128): u64 {
        // ensures that return value is not greater than u64::max_value()
        assert!(denominator > numerator, ERR_NOT_PROPORTION);
        (mul_div_u128((x as u128), numerator, denominator) as u64)
    }

    public fun calculate_proportion_of_u128_with_u128(x: u128, numerator: u128, denominator: u128): u128 {
        // ensures that return value is not greater than u128::max_value()
        assert!(denominator > numerator, ERR_NOT_PROPORTION);
        (mul_div_u128(x, numerator, denominator) as u128)
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

    public fun less_than_max_u64(x: u128): bool {
        x <= (MAX_U64 as u128)
    }
}