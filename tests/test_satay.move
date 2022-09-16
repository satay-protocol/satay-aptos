// #[test_only]
// module satay::test_satay {
//
//     use aptos_framework::signer;
//     use aptos_framework::coin;
//
//     use satay::satay;
//
//     use test_helpers::test_account;
//
//     use liquidswap_lp::coins::{
//         Self,
//         USDT
//     };
//
//     fun setup_tests(
//         vault_manager: &signer,
//         coins_manager: &signer,
//         user: &signer,
//     ) {
//
//         satay::initialize(vault_manager);
//
//         coins::register_coins(coins_manager);
//
//         test_account::create_account(user);
//         coin::register<USDT>(user);
//     }
//
//     #[test(
//         vault_manager = @satay,
//         coins_manager = @liquidswap_lp,
//         user = @0x47
//     )]
//     fun test_initialize(vault_manager : signer, coins_manager : signer, user : signer) {
//         setup_tests(&vault_manager, &coins_manager, &user);
//     }
//
//    #[test(
//         vault_manager = @satay,
//         coins_manager = @liquidswap_lp,
//         user = @0x47
//     )]
//     fun test_new_vault(vault_manager : signer, coins_manager : signer, user : signer) {
//         setup_tests(&vault_manager, &coins_manager, &user);
//         satay::new_vault<USDT>(&vault_manager, b"USDT vault");
//     }
//
//     #[test(
//         vault_manager = @satay,
//         coins_manager = @liquidswap_lp,
//         user = @0x47
//     )]
//     fun test_deposit(vault_manager : signer, coins_manager : signer, user : signer) {
//         setup_tests(&vault_manager, &coins_manager, &user);
//         satay::new_vault<USDT>(&vault_manager, b"USDT vault");
//
//         coins::mint_coin<USDT>(&coins_manager, signer::address_of(&user), 100);
//         satay::deposit<USDT>(
//             &user,
//             signer::address_of(&vault_manager),
//             0,
//             100
//         );
//     }
//
//     #[test(
//         vault_manager = @satay,
//         coins_manager = @liquidswap_lp,
//         user = @0x47
//     )]
//     fun test_withdraw(vault_manager : signer, coins_manager : signer, user : signer) {
//         setup_tests(&vault_manager, &coins_manager, &user);
//         satay::new_vault<USDT>(&vault_manager, b"USDT vault");
//
//         coins::mint_coin<USDT>(&coins_manager, signer::address_of(&user), 100);
//         satay::deposit<USDT>(
//             &user,
//             signer::address_of(&vault_manager),
//             0,
//             100
//         );
//
//         satay::withdraw<USDT>(
//             &user,
//             signer::address_of(&vault_manager),
//             0,
//             100
//         );
//     }
//
//
//
// }