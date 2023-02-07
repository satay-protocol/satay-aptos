// #[test_only]
// module satay::aptos_wrapper_product {
//
//     use std::signer;
//
//     use aptos_framework::account;
//     use aptos_framework::coin::{Self, Coin};
//     use aptos_framework::aptos_coin::AptosCoin;
//     use satay::strategy_coin;
//     use satay::strategy_coin::StrategyCoin;
//
//     const ERR_NOT_SATAY: u64 = 1;
//
//     struct WrappedAptos has drop {}
//
//     public fun initialize(satay: &signer) {
//         assert!(signer::address_of(satay) == @satay, ERR_NOT_SATAY);
//
//         strategy_coin::initialize<WrappedAptos, AptosCoin>(satay, WrappedAptos {});
//
//         coin::register<AptosCoin>(&account);
//     }
//
//     public fun apply_position(aptos_coins: Coin<AptosCoin>): Coin<StrategyCoin<WrappedAptos, AptosCoin>> {
//         let aptos_value = coin::value(&aptos_coins);
//         coin::deposit(
//             strategy_coin::strategy_account_address<WrappedAptos, AptosCoin>(),
//             aptos_coins
//         );
//         strategy_coin::mint(aptos_value, WrappedAptos {})
//     }
//
//     public fun liquidate_position(wrapped_aptos_coins: Coin<StrategyCoin<WrappedAptos, AptosCoin>>): Coin<AptosCoin> {
//         let wrapped_aptos_value = coin::value(&wrapped_aptos_coins);
//         strategy_coin::burn(
//             wrapped_aptos_coins,
//             WrappedAptos {}
//         );
//         strategy_coin::withdraw_base_coin<WrappedAptos, AptosCoin>(wrapped_aptos_value, WrappedAptos {})
//     }
//
//     public fun reinvest_returns(): Coin<WrappedAptos> {
//         coin::zero<WrappedAptos>()
//     }
//
//     public fun get_aptos_amount_for_wrapped_amount(wrapped_amount: u64): u64 {
//         wrapped_amount
//     }
//
//     public fun get_wrapped_amount_for_aptos_amount(aptos_amount: u64): u64 {
//         aptos_amount
//     }
// }
