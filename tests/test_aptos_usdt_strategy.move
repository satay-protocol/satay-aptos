// #[test_only]
// module satay::test_aptos_usdt_strategy {
//     use std::signer;
//     use std::string;
//
//     use aptos_framework::aptos_coin::{Self, AptosCoin};
//     use aptos_framework::coin;
//     use aptos_framework::stake;
//
//     use liquidswap::liquidity_pool;
//     use test_coins::coins::{Self, USDT};
//     use liquidswap_lp::lp_coin::LP;
//
//     use test_helpers::test_account;
//
//     use satay::satay;
//     use satay::aptos_usdt_strategy::{
//         Self,
//         AptosUsdcLpStrategy
//     };
//
//     #[test(
//         aptos_framework = @aptos_framework,
//         token_admin = @liquidswap_lp,
//         pool_owner = @liquidswap_lp,
//         manager_acc = @satay,
//         user = @0x45
//     )]
//     fun test_vault_end_to_end(
//         aptos_framework: signer,
//         token_admin: signer,
//         pool_owner: signer,
//         manager_acc: signer,
//         user: signer
//     ) {
//         stake::initialize_for_test(&aptos_framework);
//
//         coins::register_coins(&token_admin);
//
//         test_account::create_account(&token_admin);
//         test_account::create_account(&user);
//
//         liquidity_pool::register<USDT, AptosCoin, LP<USDT, AptosCoin>>(
//             &pool_owner,
//             string::utf8(b"LP"),
//             string::utf8(b"LP"),
//             1
//         );
//         let user_address = signer::address_of(&user);
//         coin::register<USDT>(&user);
//         coin::register<AptosCoin>(&user);
//
//         coins::mint_coin<USDT>(&token_admin, user_address, 100000);
//         aptos_coin::mint(&aptos_framework, user_address, 100000);
//
//         let usdt = coin::withdraw<USDT>(&user, 100000);
//         let aptos = coin::withdraw<AptosCoin>(&user, 100000);
//         let lp = liquidity_pool::mint<USDT, AptosCoin, LP<USDT, AptosCoin>>(
//             signer::address_of(&pool_owner),
//             usdt,
//             aptos
//         );
//         coin::register<LP<USDT, AptosCoin>>(&user);
//         coin::deposit(user_address, lp);
//
//         aptos_coin::mint(&aptos_framework, user_address, 100000);
//
//         satay::initialize(&manager_acc);
//         satay::new_vault<AptosCoin>(&manager_acc, b"aptos_vault");
//         satay::approve_strategy<AptosUsdcLpStrategy>(&manager_acc, 0);
//
//         aptos_usdt_strategy::initialize(&manager_acc, @satay, 0);
//
//         satay::deposit<AptosCoin>(&user, @satay, 0, 1000);
//
//         aptos_usdt_strategy::run_strategy(&manager_acc, @satay, 0);
//     }
// }