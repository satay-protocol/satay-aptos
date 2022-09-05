#[test_only]
module satay::usdc_aptos_strategy_tests {
    // use std::signer;
    // use std::string;

    // use aptos_framework::aptos_coin::{Self, AptosCoin};
    // use aptos_framework::coin;
    // use aptos_framework::genesis;
    // use liquidswap::liquidity_pool;
    // use liquidswap_lp::coins::{Self, USDT};
    // use liquidswap_lp::lp::LP;

    // // use satay::usdc_aptos_strategy;
    // // use satay::satay;
    // // use satay::usdc_aptos_strategy::UsdcAptosStrategy;

    // #[test(
    //     aptos_framework = @aptos_framework,
    //     token_admin = @liquidswap_lp,
    //     pool_owner = @liquidswap_lp,
    //     _manager_acc = @satay,
    //     user = @0x45
    // )]
    // fun test_vault_end_to_end(
    //     aptos_framework: signer,
    //     token_admin: signer,
    //     pool_owner: signer,
    //     _manager_acc: signer,
    //     user: signer
    // ) {
    //     genesis::setup();
    //     let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
    //     coin::destroy_mint_cap(mint_cap);
    //     coin::destroy_burn_cap(burn_cap);

    //     coins::register_coins(&token_admin);

    //     liquidity_pool::register<USDT, AptosCoin, LP<USDT, AptosCoin>>(
    //         &pool_owner,
    //         string::utf8(b"LP"),
    //         string::utf8(b"LP"),
    //         1
    //     );
    //     let user_address = signer::address_of(&user);
    //     coin::register<USDT>(&user);
    //     coin::register<AptosCoin>(&user);

    //     coins::mint_coin<USDT>(&token_admin, user_address, 100000);
    //     aptos_coin::mint(&aptos_framework, user_address, 100000);

    //     // let usdt = coin::withdraw<USDT>(&user, 100000);
    //     // let aptos = coin::withdraw<AptosCoin>(&user, 100000);
    //     // let lp = liquidity_pool::mint<USDC, AptosCoin, LP<USDC, AptosCoin>>(
    //     //     signer::address_of(&pool_owner),
    //     //     usdc,
    //     //     aptos
    //     // );
    //     // coin::register_for_test<LP<USDC, AptosCoin>>(&user);
    //     // coin::deposit(user_address, lp);

    //     // coins_extended::mint_coin<USDC>(&token_admin, signer::address_of(&user), 1000);

    //     // satay::initialize(&manager_acc);
    //     // satay::new_vault<USDC>(&manager_acc, b"usdc_aptos_vault_50_50");
    //     // satay::approve_strategy<UsdcAptosStrategy>(&manager_acc, 0);

    //     // usdc_aptos_strategy::initialize(&manager_acc, @satay, 0);

    //     // satay::deposit<USDC>(&user, @satay, 0, 1000);

    //     // usdc_aptos_strategy::run_strategy(&manager_acc, @satay, 0);

    //     // satay::withdraw<USDC>(&user, @satay, 0, 300);
    // }
}




















