// #[test_only]
// module satay::test_usdt_btc_strategy {
//     use std::string;
//     use std::signer;
//
//     use aptos_framework::coin;
//     use aptos_framework::stake;
//
//     use liquidswap::liquidity_pool;
//     use liquidswap_lp::coins::{Self, USDT, BTC};
//     use liquidswap_lp::lp::LP;
//
//     use satay::usdt_btc_strategy::{
//         Self,
//         UsdtBtcStrategy,
//     };
//     use satay::satay;
//     // use satay::vault;
//
//     use test_helpers::test_account;
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
//         liquidity_pool::register<BTC, USDT, LP<BTC, USDT>>(
//             &pool_owner,
//             string::utf8(b"LP"),
//             string::utf8(b"LP"),
//             1
//         );
//         let user_address = signer::address_of(&user);
//         coin::register<USDT>(&user);
//         coin::register<BTC>(&user);
//
//         coins::mint_coin<USDT>(&token_admin, user_address, 100000);
//         coins::mint_coin<BTC>(&token_admin, user_address, 100000);
//
//         let usdt = coin::withdraw<USDT>(&user, 100000);
//         let btc = coin::withdraw<BTC>(&user, 100000);
//         let lp = liquidity_pool::mint<BTC, USDT, LP<BTC, USDT>>(
//             signer::address_of(&pool_owner),
//             btc,
//             usdt
//         );
//         coin::register<LP<BTC, USDT>>(&user);
//         coin::deposit(user_address, lp);
//
//         coins::mint_coin<USDT>(&token_admin, signer::address_of(&user), 1000);
//
//         satay::initialize(&manager_acc);
//         satay::new_vault<USDT>(&manager_acc, b"usdt_btc_lp_vault");
//
//         satay::approve_strategy<UsdtBtcStrategy>(&manager_acc, 0);
//         usdt_btc_strategy::initialize(&manager_acc, @satay, 0);
//
//         satay::deposit<USDT>(&user, @satay, 0, 1000);
//
//         usdt_btc_strategy::run_strategy(&manager_acc, @satay, 0);
//
//         // assert!(satay::balance<LP<BTC, USDT>>(signer::address_of(&manager_acc), 0) > 0, 0);
//     }
// }
//
//
//
//
//
//
//
//
//
//
//
//
//
//
//
//
//
//
//
//
