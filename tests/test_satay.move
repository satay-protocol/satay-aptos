#[test_only]
module satay::test_satay {

    use std::signer;

    use aptos_framework::coin;

    use satay::satay;

    use test_helpers::test_account;

    use test_coins::coins::{
        Self,
        USDT
    };
    use aptos_std::type_info;
    use satay::global_config;

    struct TestStrategy has drop {}
    struct TestStrategy2 has drop {}

    fun setup_tests(
        vault_manager: &signer,
        coins_manager: &signer,
        user: &signer,
    ) {

        global_config::initialize(vault_manager);

        satay::initialize(vault_manager);

        coins::register_coins(coins_manager);

        test_account::create_account(user);
        coin::register<USDT>(user);
    }

    #[test(
        vault_manager = @satay,
        coins_manager = @test_coins,
        user = @0x47
    )]
    fun test_initialize(vault_manager : signer, coins_manager : signer, user : signer) {
        setup_tests(&vault_manager, &coins_manager, &user);
    }

    #[test_reject(
        coins_manager = @test_coins,
        user = @0x47
    )]
    fun test_initialize_unauthorized(coins_manager : signer, user : signer) {
        setup_tests(&user, &coins_manager, &user);
    }

   #[test(
        vault_manager = @satay,
        coins_manager = @test_coins,
        user = @0x47
    )]
    fun test_new_vault(vault_manager : signer, coins_manager : signer, user : signer) {
        setup_tests(&vault_manager, &coins_manager, &user);
        satay::new_vault<USDT>(&vault_manager, b"USDT vault");
    }

    #[test(
        vault_manager = @satay,
        coins_manager = @test_coins,
        user = @0x47
    )]
    fun test_deposit(vault_manager : signer, coins_manager : signer, user : signer) {
        setup_tests(&vault_manager, &coins_manager, &user);
        satay::new_vault<USDT>(&vault_manager, b"USDT vault");

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
        coins_manager = @test_coins,
        user = @0x47
    )]
    fun test_withdraw(vault_manager : signer, coins_manager : signer, user : signer) {
        setup_tests(&vault_manager, &coins_manager, &user);
        satay::new_vault<USDT>(&vault_manager, b"USDT vault");

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
        coins_manager = @test_coins,
        user = @0x47
    )]
    fun test_approve_strategy(vault_manager : signer, coins_manager : signer, user : signer) {
        setup_tests(&vault_manager, &coins_manager, &user);
        satay::new_vault<USDT>(&vault_manager, b"USDT vault");

        satay::approve_strategy<TestStrategy>(&vault_manager, 0, type_info::type_of<USDT>());
        assert!(satay::has_strategy<TestStrategy>(&vault_manager, 0), 3);
    }

    #[test(
        vault_manager = @satay,
        coins_manager = @test_coins,
        user = @0x47
    )]
    fun test_approve_multiple_strategies(vault_manager : signer, coins_manager : signer, user : signer) {
        setup_tests(&vault_manager, &coins_manager, &user);
        satay::new_vault<USDT>(&vault_manager, b"USDT vault");

        satay::approve_strategy<TestStrategy>(&vault_manager, 0, type_info::type_of<USDT>());
        assert!(satay::has_strategy<TestStrategy>(&vault_manager, 0), 3);
        satay::approve_strategy<TestStrategy2>(&vault_manager, 0, type_info::type_of<USDT>());
        assert!(satay::has_strategy<TestStrategy2>(&vault_manager, 0), 3);

    }

    #[test(
        vault_manager = @satay,
        coins_manager = @test_coins,
        user = @0x47
    )]
    fun test_lock_unlock_vault(vault_manager : signer, coins_manager : signer, user : signer) {
        setup_tests(&vault_manager, &coins_manager, &user);
        satay::new_vault<USDT>(&vault_manager, b"USDT vault");

        satay::approve_strategy<TestStrategy>(&vault_manager, 0, type_info::type_of<USDT>());
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

    #[test(
        vault_manager = @satay,
        coins_manager = @test_coins,
        user = @0x47
    )]
    fun test_lock_unlock_vault_multiple_strategies(vault_manager : signer, coins_manager : signer, user : signer) {
        setup_tests(&vault_manager, &coins_manager, &user);
        satay::new_vault<USDT>(&vault_manager, b"USDT vault");

        satay::approve_strategy<TestStrategy>(&vault_manager, 0, type_info::type_of<USDT>());
        satay::approve_strategy<TestStrategy2>(&vault_manager, 0, type_info::type_of<USDT>());
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
        coins_manager = @test_coins,
        user = @0x47
    )]
    fun test_reject_unapproved_strategy(vault_manager : signer, coins_manager : signer, user : signer) {
        setup_tests(&vault_manager, &coins_manager, &user);
        satay::new_vault<USDT>(&vault_manager, b"USDT vault");

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