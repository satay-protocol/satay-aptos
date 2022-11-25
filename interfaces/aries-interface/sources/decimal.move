module aries_interface::decimal {

    struct Decimal has copy, drop, store {
        val: u128
    }

    public fun add(a: Decimal, b: Decimal): Decimal {
        Decimal { val: a.val + b.val }
    }

    public fun sub(a: Decimal, b: Decimal): Decimal {
        Decimal { val: a.val - b.val }
    }

    public fun mul(a: Decimal, b: Decimal): Decimal {
        Decimal { val: a.val * b.val }
    }

    public fun div(a: Decimal, b: Decimal): Decimal {
        Decimal { val: a.val / b.val }
    }

    public fun zero(): Decimal {
        Decimal { val: 0 }
    }
}
