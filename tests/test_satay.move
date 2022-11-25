#[test_only]
module satay::test_satay {

    use std::signer;

    use aptos_framework::coin;

    use satay::satay;

    use satay::base_strategy;

    use test_helpers::test_account;

    use satay::coins::{
        Self,
        USDT
    };
    use aptos_framework::timestamp::set_time_has_started_for_testing;

    struct TestStrategy has drop {}
    struct TestStrategy2 has drop {}

    fun setup_tests(
        vault_manager: &signer,
        coins_manager: &signer,
        user: &signer,
    ) {
        satay::initialize(vault_manager);
        coins::register_coins(coins_manager);

        test_account::create_account(user);
        coin::register<USDT>(user);
    }

    #[test(
        vault_manager = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_initialize(vault_manager : signer, coins_manager : signer, user : signer) {
        setup_tests(&vault_manager, &coins_manager, &user);
    }

   #[test(
        vault_manager = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_new_vault(vault_manager : signer, coins_manager : signer, user : signer) {
        setup_tests(&vault_manager, &coins_manager, &user);

        let manager_addr = signer::address_of(&vault_manager);

        satay::new_vault<USDT>(&vault_manager, manager_addr, b"USDT vault", 200, 5000);
    }

   #[test(
        vault_manager = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_update_vault_fee(vault_manager : signer, coins_manager : signer, user : signer) {
        setup_tests(&vault_manager, &coins_manager, &user);

        let manager_addr = signer::address_of(&vault_manager);

        satay::new_vault<USDT>(&vault_manager, manager_addr, b"USDT vault", 200, 5000);

        satay::update_vault_fee(&vault_manager, manager_addr, 0, 1000, 2000);
    }

    #[test(
        vault_manager = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_deposit(vault_manager : signer, coins_manager : signer, user : signer) {
        setup_tests(&vault_manager, &coins_manager, &user);

        let manager_addr = signer::address_of(&vault_manager);

        satay::new_vault<USDT>(&vault_manager, manager_addr, b"USDT vault", 200, 5000);

        coins::mint_coin<USDT>(&coins_manager, signer::address_of(&user), 100);
        satay::deposit<USDT>(
            &user,
            signer::address_of(&vault_manager),
            0,
            100
        );
    }

    #[test(
        vault_manager = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_withdraw(vault_manager : signer, coins_manager : signer, user : signer) {
        setup_tests(&vault_manager, &coins_manager, &user);

        let manager_addr = signer::address_of(&vault_manager);

        satay::new_vault<USDT>(&vault_manager, manager_addr, b"USDT vault", 200, 5000);

        coins::mint_coin<USDT>(&coins_manager, signer::address_of(&user), 100);
        satay::deposit<USDT>(
            &user,
            signer::address_of(&vault_manager),
            0,
            100
        );

        satay::withdraw<USDT>(
            &user,
            signer::address_of(&vault_manager),
            0,
            100
        );
    }

    #[test(
        vault_manager = @satay,
        coins_manager = @satay,
        user = @0x47,
        aptos_framework = @aptos_framework
    )]
    fun test_approve_strategy(vault_manager : signer, coins_manager : signer, user : signer, aptos_framework : signer) {
        setup_tests(&vault_manager, &coins_manager, &user);
        set_time_has_started_for_testing(&aptos_framework);

        let manager_addr = signer::address_of(&vault_manager);

        satay::new_vault<USDT>(&vault_manager, manager_addr, b"USDT vault", 200, 5000);

        base_strategy::initialize<TestStrategy, USDT, USDT>(&vault_manager, 0, 1000, TestStrategy {});
        assert!(satay::has_strategy<TestStrategy>(&vault_manager, 0), 3);
    }

    #[test(
        vault_manager = @satay,
        coins_manager = @satay,
        user = @0x47,
        aptos_framework = @aptos_framework
    )]
    fun test_approve_multiple_strategies(vault_manager : signer, coins_manager : signer, user : signer, aptos_framework : signer) {
        setup_tests(&vault_manager, &coins_manager, &user);

        let manager_addr = signer::address_of(&vault_manager);

        satay::new_vault<USDT>(&vault_manager, manager_addr, b"USDT vault", 200, 5000);

        set_time_has_started_for_testing(&aptos_framework);
        base_strategy::initialize<TestStrategy, USDT, USDT>(&vault_manager, 0, 1000, TestStrategy {});
        assert!(satay::has_strategy<TestStrategy>(&vault_manager, 0), 3);
        base_strategy::initialize<TestStrategy2, USDT, USDT>(&vault_manager, 0, 1000, TestStrategy2 {});
        assert!(satay::has_strategy<TestStrategy2>(&vault_manager, 0), 3);

    }

    #[test(
        vault_manager = @satay,
        coins_manager = @satay,
        user = @0x47,
        aptos_framework = @aptos_framework
    )]
    fun test_lock_unlock_vault(vault_manager : signer, coins_manager : signer, user : signer, aptos_framework : signer) {
        setup_tests(&vault_manager, &coins_manager, &user);
        set_time_has_started_for_testing(&aptos_framework);

        let manager_addr = signer::address_of(&vault_manager);

        satay::new_vault<USDT>(&vault_manager, manager_addr, b"USDT vault", 200, 5000);

        base_strategy::initialize<TestStrategy, USDT, USDT>(&vault_manager, 0, 1000, TestStrategy {});
        let (vault_cap, vault_lock) = satay::lock_vault<TestStrategy>(
            manager_addr,
            0,
            TestStrategy{}
        );
        satay::unlock_vault<TestStrategy>(
            manager_addr,
            vault_cap,
            vault_lock
        )
    }

    #[test(
        vault_manager = @satay,
        coins_manager = @satay,
        user = @0x47,
        aptos_framework = @aptos_framework
    )]
    fun test_lock_unlock_vault_multiple_strategies(vault_manager : signer, coins_manager : signer, user : signer, aptos_framework : signer) {
        setup_tests(&vault_manager, &coins_manager, &user);
        set_time_has_started_for_testing(&aptos_framework);

        let manager_addr = signer::address_of(&vault_manager);

        satay::new_vault<USDT>(&vault_manager, manager_addr, b"USDT vault", 200, 5000);

        base_strategy::initialize<TestStrategy, USDT, USDT>(&vault_manager, 0, 1000, TestStrategy {});
        base_strategy::initialize<TestStrategy2, USDT, USDT>(&vault_manager, 0, 1000, TestStrategy2 {});
        let (vault_cap, vault_lock) = satay::lock_vault<TestStrategy>(
            signer::address_of(&vault_manager),
            0,
            TestStrategy{}
        );
        satay::unlock_vault<TestStrategy>(
            signer::address_of(&vault_manager),
            vault_cap,
            vault_lock
        );
        let (vault_cap, vault_lock) = satay::lock_vault<TestStrategy2>(
            signer::address_of(&vault_manager),
            0,
            TestStrategy2{}
        );
        satay::unlock_vault<TestStrategy2>(
            signer::address_of(&vault_manager),
            vault_cap,
            vault_lock
        )

    }

    #[test_reject(
        vault_manager = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_reject_unapproved_strategy(vault_manager : signer, coins_manager : signer, user : signer) {
        setup_tests(&vault_manager, &coins_manager, &user);

        let manager_addr = signer::address_of(&vault_manager);

        satay::new_vault<USDT>(&vault_manager, manager_addr, b"USDT vault", 200, 5000);

        let (vault_cap, vault_lock) = satay::lock_vault<TestStrategy>(
            signer::address_of(&vault_manager),
            0,
            TestStrategy{}
        );
        satay::unlock_vault<TestStrategy>(
            signer::address_of(&vault_manager),
            vault_cap,
            vault_lock
        )
    }

}