#[test_only]
module satay::test_aptos_usdt_strategy {
    use std::signer;
    use std::string;

    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin;
    use aptos_framework::stake;

    use liquidswap::liquidity_pool;
    use liquidswap_lp::coins::{Self, USDT};
    use liquidswap_lp::lp::LP;

    use test_helpers::test_account;

    use satay::satay;
    use satay::aptos_usdt_strategy::{
        Self,
        AptosUsdcLpStrategy
    };

    #[test(
        aptos_framework = @aptos_framework,
        token_admin = @liquidswap_lp,
        pool_owner = @liquidswap_lp,
        manager_acc = @satay,
        user = @0x45
    )]
    fun test_vault_end_to_end(
        aptos_framework: signer,
        token_admin: signer,
        pool_owner: signer,
        manager_acc: signer,
        user: signer
    ) {
        stake::initialize_for_test(&aptos_framework);

        coins::register_coins(&token_admin);

        test_account::create_account(&token_admin);
        test_account::create_account(&user);

        liquidity_pool::register<AptosCoin, USDT, LP<AptosCoin, USDT>>(
            &pool_owner,
            string::utf8(b"LP"),
            string::utf8(b"LP"),
            1
        );
        let user_address = signer::address_of(&user);
        coin::register<USDT>(&user);
        coin::register<AptosCoin>(&user);

        coins::mint_coin<USDT>(&token_admin, user_address, 100000);
        aptos_coin::mint(&aptos_framework, user_address, 100000);

        let usdt = coin::withdraw<USDT>(&user, 100000);
        let aptos = coin::withdraw<AptosCoin>(&user, 100000);
        let lp = liquidity_pool::mint<AptosCoin, USDT, LP<AptosCoin, USDT>>(
            signer::address_of(&pool_owner),
            aptos,
            usdt
        );
        coin::register<LP<AptosCoin, USDT>>(&user);
        coin::deposit(user_address, lp);

        aptos_coin::mint(&aptos_framework, user_address, 100000);

        satay::initialize(&manager_acc);
        satay::new_vault<AptosCoin>(&manager_acc, b"aptos_vault");
        satay::approve_strategy<AptosUsdcLpStrategy>(&manager_acc, 0);

        aptos_usdt_strategy::initialize(&manager_acc, @satay, 0);

        satay::deposit<AptosCoin>(&user, @satay, 0, 1000);

        aptos_usdt_strategy::apply_strategy(&manager_acc, 0, 1000);
        assert!(satay::balance<AptosCoin>(signer::address_of(&manager_acc), 0) < 1000, 2);

        let lp_position_value = satay::balance<LP<AptosCoin, USDT>>(@satay, 0);
        assert!(lp_position_value > 0, 1);

        aptos_usdt_strategy::liquidate_strategy(&manager_acc, 0, lp_position_value);

        assert!(satay::balance<LP<AptosCoin, USDT>>(signer::address_of(&manager_acc), 0) == 0, 0);
        assert!(satay::balance<AptosCoin>(signer::address_of(&manager_acc), 0) > 0, 2);
    }
}