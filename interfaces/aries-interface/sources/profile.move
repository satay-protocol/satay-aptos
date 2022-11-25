module aries_interface::profile {

    use std::string::String;

    use aptos_std::type_info::TypeInfo;

    use aries_interface::decimal::{Self, Decimal};

    public fun available_borrowing_power(_addr: address, _name: String): Decimal {
        decimal::zero()
    }

    public fun get_borrowed_amount(
        _user_addr: address,
        _name: String,
        _coin_type: TypeInfo
    ): Decimal {
        decimal::zero()
    }

    public fun get_deposited_amount(
        _user_addr: address,
        _name: String,
        _coin_type: TypeInfo
    ): u64 {
        0
    }
}