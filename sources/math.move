/// Implementation of math functions needed for Multi Swap.
module satay::math {


    // constants
    const MAX_U64: u64 = 18446744073709551615;
    const MAX_U128: u128 = 340282366920938463463374607431768211455;

    // Errors codes.

    /// When trying to divide by zero.
    const ERR_DIVIDE_BY_ZERO: u64 = 2000;
    const ERR_NOT_PROPORTION: u64 = 2001;
    const OVERFLOW: u64 = 2002;

    public fun mul_div(x: u64, y: u64, z: u64): u64 {
        assert!(z != 0, ERR_DIVIDE_BY_ZERO);
        assert_can_cast_to_u64((x as u128) * (y as u128) / (z as u128));
        ((x as u128) * (y as u128) / (z as u128) as u64)
    }

    public fun calculate_proportion_of_u64_with_u64_denominator(x: u64, numerator: u64, denominator: u64): u64 {
        assert!(denominator != 0, ERR_DIVIDE_BY_ZERO);
        // ensures that return value is not greater than u64::max_value()
        assert!(denominator >= numerator, ERR_NOT_PROPORTION);
        mul_div(x, numerator, denominator)
    }

    public fun calculate_proportion_of_u64_with_u128_denominator(x: u64, numerator: u64, denominator: u128): u64 {
        assert!(denominator != 0, ERR_DIVIDE_BY_ZERO);
        // ensures that return value is not greater than u64::max_value()
        assert!(denominator >= (numerator as u128), ERR_NOT_PROPORTION);
        ((x as u128) * (numerator as u128) / denominator as u64)
    }

    public fun mul_u128_u64_div_u64_result_u64(x: u128, y: u64, z: u64): u64 {
        assert!(z != 0, ERR_DIVIDE_BY_ZERO);
        let res = x * (y as u128) / (z as u128);
        assert_can_cast_to_u64(res);
        (res as u64)
    }

    public fun assert_can_cast_to_u64(x: u128) {
        assert!(x <= (MAX_U64 as u128), OVERFLOW);
    }
}