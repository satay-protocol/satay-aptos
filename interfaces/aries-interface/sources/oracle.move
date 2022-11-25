module aries_interface::oracle {

    use aries_interface::decimal::Decimal;
    use aries_interface::decimal;

    public fun get_price(): Decimal {
        decimal::zero()
    }
}
