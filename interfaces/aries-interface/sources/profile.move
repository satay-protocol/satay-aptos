module aries_interface::profile {

    use std::string::String;

    use aries_interface::decimal::{Self, Decimal};

    public fun available_borrowing_power(_addr: address, _name: String): Decimal {
        decimal::zero()
    }
}