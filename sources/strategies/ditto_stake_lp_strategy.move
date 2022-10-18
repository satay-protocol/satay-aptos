// module satay::ditto_stake_lp_strategy {
//     use std::signer;
//
//     use aptos_framework::coin::{Self, Coin};
//     use aptos_framework::aptos_coin::AptosCoin;
//
//     use liquidswap::router;
//     use liquidswap::curves::{Stable};
//
//     use ditt
//
//     use test_coins::coins::{USDT};
//     use liquidswap_lp::lp_coin::{LP};
//
//     use satay::vault;
//     use satay::satay;
//     use aptos_std::type_info;
//     use ditto_staking::staked_coin::StakedAptos;
//     use ditto_interface::ditto_interface::invoke_ditto_stake_aptos;
//     use ditto_interface::ditto_interface;
//
//     const ERR_NO_PERMISSIONS: u64 = 201;
//     const ERR_INITIALIZE: u64 = 202;
//     const ERR_NO_POSITION: u64 = 203;
//     const ERR_NOT_ENOUGH_POSITION: u64 = 204;
//
//     // used for witnessing
//     struct DittoStakeAndLPStrategy has drop {}
//
//     public entry fun initialize(manager: &signer, vault_id: u64) {
//         let manager_addr = signer::address_of(manager);
//
//         let witness = DittoStakeAndLPStrategy {};
//
//         satay::approve_strategy<DittoStakeAndLPStrategy>(manager, vault_id, type_info::type_of<LP<AptosCoin, StakedAptos, Stable>>());
//
//         let (vault_cap, stop_handle) = satay::lock_vault<DittoStakeAndLPStrategy>(manager_addr, vault_id, witness);
//         if (!vault::has_coin<LP<AptosCoin, StakedAptos, Stable>>(&vault_cap)) {
//             vault::add_coin<LP<AptosCoin, StakedAptos, Stable>>(&vault_cap);
//         };
//         satay::unlock_vault<DittoStakeAndLPStrategy>(manager_addr, vault_cap, stop_handle);
//     }
//
//     public entry fun apply_strategy(manager: &signer, vault_id: u64, amount : u64) {
//         let manager_addr = signer::address_of(manager);
//         let (vault_cap, lock) = satay::lock_vault<DittoStakeAndLPStrategy>(
//             manager_addr,
//             vault_id,
//             DittoStakeAndLPStrategy {}
//         );
//
//         // stake aptos
//         ditto_interface::invoke_ditto_stake_aptos(manager, amount);
//         // lp staked aptos and aptos
//         // deposit lp token to vault
//
//
//         satay::unlock_vault<DittoStakeAndLPStrategy>(manager_addr, vault_cap, lock);
//     }
//
//     public entry fun liquidate_strategy(manager: &signer, vault_id : u64, amount : u64) {
//         let manager_addr = signer::address_of(manager);
//         let (vault_cap, lock) = satay::lock_vault<AptosUsdcLpStrategy>(
//             manager_addr,
//             vault_id,
//             AptosUsdcLpStrategy {}
//         );
//
//         let lp_coins = vault::withdraw<LP<USDT, AptosCoin, Uncorrelated>>(&vault_cap, amount);
//         let (usdt_coins, aptos_coins) = remove_liquidity(lp_coins);
//
//         coin::merge(&mut aptos_coins, swap<USDT, AptosCoin>(usdt_coins));
//
//         vault::deposit<AptosCoin>(&vault_cap, aptos_coins);
//
//         satay::unlock_vault<AptosUsdcLpStrategy>(
//             manager_addr,
//             vault_cap,
//             lock
//         );
//     }
//
//     fun swap<From, To>(coins: Coin<From>): Coin<To> {
//         // swap on AMM
//         router::swap_exact_coin_for_coin<From, To, Uncorrelated>(
//             coins,
//             0
//         )
//     }
//
//     fun add_liquidity(
//         aptos_coins : Coin<AptosCoin>,
//         usdt_coins : Coin<USDT>
//     ) : (
//         Coin<USDT>,
//         Coin<AptosCoin>,
//         Coin<LP<USDT, AptosCoin, Uncorrelated>>
//     ) {
//         router::add_liquidity<USDT, AptosCoin, Uncorrelated>(usdt_coins, 1, aptos_coins, 1)
//     }
//
//     fun remove_liquidity(
//         lp_coins : Coin<LP<USDT, AptosCoin, Uncorrelated>>
//     ) : (
//         Coin<USDT>, Coin<AptosCoin>
//     ) {
//         router::remove_liquidity<USDT, AptosCoin, Uncorrelated>(lp_coins, 1, 1)
//     }
// }
