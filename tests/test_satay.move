#[test_only]
module satay::test_satay {

    use std::signer;

    use aptos_framework::coin;
    use aptos_framework::account;
    use aptos_framework::stake;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::timestamp;

    use satay::satay;
    use satay::coins::{Self, USDT, BTC};
    use satay::vault::{Self, VaultCoin};

    const MANAGEMENT_FEE: u64 = 200;
    const PERFORMANCE_FEE: u64 = 2000;
    const DEBT_RATIO: u64 = 1000;

    const ERR_INITIALIZED: u64 = 1;
    const ERR_NEW_VAULT: u64 = 2;
    const ERR_UPDATE_FEES: u64 = 3;
    const ERR_DEPOSIT: u64 = 4;
    const ERR_WITHDRAW: u64 = 5;
    const ERR_APPROVE_STRATEGY: u64 = 6;
    const ERR_LOCK_UNLOCK: u64 = 7;

    struct TestStrategy has drop {}
    struct TestStrategy2 has drop {}

    fun setup_tests(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer,
    ) {
        stake::initialize_for_test(aptos_framework);
        account::create_account_for_test(signer::address_of(aptos_framework));
        coin::register<AptosCoin>(aptos_framework);
        satay::initialize(satay);
        coins::register_coins(coins_manager);

        account::create_account_for_test(signer::address_of(user));
        coin::register<AptosCoin>(user);
        coin::register<USDT>(user);
    }

    fun create_vault(
        satay: &signer
    ) {
        satay::new_vault<AptosCoin>(
            satay,
            b"Aptos vault",
            MANAGEMENT_FEE,
            PERFORMANCE_FEE
        );
    }

    fun setup_tests_and_create_vault(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer,
    ) {
        setup_tests(aptos_framework, satay, coins_manager, user);
        create_vault(satay);
    }

    fun approve_strategy(
        aptos_framework: &signer,
        satay: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        satay::test_approve_strategy<TestStrategy, USDT>(
            satay,
            0,
            DEBT_RATIO,
            TestStrategy {}
        );
    }

    fun setup_test_and_create_vault_with_strategy(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer,
    ) {
        setup_tests_and_create_vault(aptos_framework, satay, coins_manager, user);
        approve_strategy(aptos_framework, satay);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_initialize(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer
    ) {
        setup_tests(
            aptos_framework,
            satay,
            coins_manager,
            user
        );
        satay::test_assert_manager_initialized();
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @0x1,
        coins_manager = @satay,
        user = @0x47
    )]
    #[expected_failure]
    fun test_initialize_unauthorized(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer
    ) {
        setup_tests(
            aptos_framework,
            satay,
            coins_manager,
            user
        );
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_new_vault(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer
    ) {
        setup_tests(
            aptos_framework,
            satay,
            coins_manager,
            user
        );
        create_vault(satay);
        assert!(satay::get_next_vault_id() == 1, ERR_NEW_VAULT);
        assert!(satay::get_vault_total_asset<AptosCoin>(0) == 0, ERR_NEW_VAULT);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    #[expected_failure]
    fun test_new_vault_unathorized(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer
    ) {
        setup_tests(
            aptos_framework,
            satay,
            coins_manager,
            user
        );
        create_vault(user);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_two_new_vaults(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer
    ) {
        setup_tests(
            aptos_framework,
            satay,
            coins_manager,
            user
        );
        create_vault(satay);
        satay::new_vault<USDT>(
            satay,
            b"USDT vault",
            MANAGEMENT_FEE,
            PERFORMANCE_FEE
        );
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_update_vault_fee(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer
    ) {
        setup_tests_and_create_vault(
            aptos_framework,
            satay,
            coins_manager,
            user
        );

        let management_fee = 1000;
        let performance_fee = 2000;

        satay::update_vault_fee(
            satay,
            0,
            management_fee,
            performance_fee
        );

        let vault_cap = satay::open_vault(0);
        let (management_fee_val, performance_fee_val) = vault::get_fees(&vault_cap);
        satay::close_vault(0, vault_cap);

        assert!(management_fee_val == management_fee, ERR_UPDATE_FEES);
        assert!(performance_fee_val == performance_fee, ERR_UPDATE_FEES);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_deposit(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer
    ) {
        setup_tests_and_create_vault(
            aptos_framework,
            satay,
            coins_manager,
            user
        );

        let user_address = signer::address_of(user);

        let amount = 1000;
        aptos_coin::mint(aptos_framework, user_address, amount);
        satay::deposit<AptosCoin>(
            user,
            0,
            amount
        );
        assert!(coin::balance<VaultCoin<AptosCoin>>(user_address) == amount, ERR_DEPOSIT);

    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_withdraw(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer
    ) {
        setup_tests_and_create_vault(
            aptos_framework,
            satay,
            coins_manager,
            user
        );

        let user_address = signer::address_of(user);

        let amount = 1000;
        aptos_coin::mint(aptos_framework, user_address, amount);
        satay::deposit<AptosCoin>(
            user,
            0,
            amount
        );

        satay::withdraw<AptosCoin>(
            user,
            0,
            amount
        );
        assert!(coin::balance<VaultCoin<AptosCoin>>(user_address) == 0, ERR_WITHDRAW);
        assert!(coin::balance<AptosCoin>(user_address) == amount, ERR_WITHDRAW);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    #[expected_failure]
    fun test_withdraw_no_liquidity(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer
    ) {
        setup_test_and_create_vault_with_strategy(
            aptos_framework,
            satay,
            coins_manager,
            user
        );

        let user_address = signer::address_of(user);

        let amount = 1000;
        aptos_coin::mint(aptos_framework, user_address, amount);
        satay::deposit<AptosCoin>(
            user,
            0,
            amount
        );

        let vault_cap = satay::open_vault(0);

        let credit = vault::credit_available<TestStrategy, AptosCoin>(&vault_cap);
        let aptos = vault::test_withdraw_base_coin<TestStrategy, AptosCoin>(
            &vault_cap,
            credit,
            &TestStrategy {}
        );
        coin::deposit(signer::address_of(aptos_framework), aptos);

        satay::close_vault(0, vault_cap);

        satay::withdraw<AptosCoin>(
            user,
            0,
            amount
        );
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47,
    )]
    fun test_approve_strategy(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer
    ) {
        setup_tests_and_create_vault(
            aptos_framework,
            satay,
            coins_manager,
            user
        );

        approve_strategy(aptos_framework, satay);

        assert!(satay::has_strategy<TestStrategy>(0), ERR_APPROVE_STRATEGY);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47,
    )]
    fun test_approve_multiple_strategies(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer
    ) {
        setup_test_and_create_vault_with_strategy(
            aptos_framework,
            satay,
            coins_manager,
            user
        );

        satay::test_approve_strategy<TestStrategy2, BTC>(
            satay,
            0,
            DEBT_RATIO,
            TestStrategy2 {}
        );
        assert!(satay::has_strategy<TestStrategy2>(0), ERR_APPROVE_STRATEGY);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47,
    )]
    fun test_lock_unlock_vault(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer
    ) {
        setup_test_and_create_vault_with_strategy(
            aptos_framework,
            satay,
            coins_manager,
            user
        );

        let (
            vault_cap,
            stop_handle
        ) = satay::test_lock_vault<TestStrategy>(
            0,
            TestStrategy {}
        );

        assert!(satay::get_strategy_witness(&stop_handle) == &TestStrategy {}, ERR_LOCK_UNLOCK);
        satay::test_assert_vault_cap_and_stop_handle_match<TestStrategy>(&vault_cap, &stop_handle);

        satay::test_unlock_vault<TestStrategy>(vault_cap, stop_handle);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47,
    )]
    fun test_lock_unlock_vault_multiple_strategies(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer
    ) {
        setup_test_and_create_vault_with_strategy(
            aptos_framework,
            satay,
            coins_manager,
            user
        );

        satay::test_approve_strategy<TestStrategy2, BTC>(
            satay,
            0,
            DEBT_RATIO,
            TestStrategy2 {}
        );

        let (vault_cap, stop_handle) = satay::test_lock_vault<TestStrategy>(
            0,
            TestStrategy {}
        );
        satay::test_unlock_vault<TestStrategy>(
            vault_cap,
            stop_handle
        );

        let (vault_cap, stop_handle) = satay::test_lock_vault<TestStrategy2>(
            0,
            TestStrategy2 {}
        );
        satay::test_unlock_vault<TestStrategy2>(
            vault_cap,
            stop_handle
        );
    }


    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47,
    )]
    #[expected_failure]
    fun test_reject_unapproved_strategy(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer
    ) {
        setup_test_and_create_vault_with_strategy(
            aptos_framework,
            satay,
            coins_manager,
            user
        );

        let (vault_cap, vault_lock) = satay::test_lock_vault<TestStrategy2>(
            0,
            TestStrategy2 {}
        );
        satay::test_unlock_vault<TestStrategy2>(
            vault_cap,
            vault_lock
        )
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47,
    )]
    #[expected_failure]
    fun test_lock_locked_vault(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer
    ) {
        setup_test_and_create_vault_with_strategy(
            aptos_framework,
            satay,
            coins_manager,
            user
        );

        satay::test_approve_strategy<TestStrategy2, BTC>(
            satay,
            0,
            DEBT_RATIO,
            TestStrategy2 {}
        );

        let (vault_cap, vault_lock) = satay::test_lock_vault<TestStrategy>(
            0,
            TestStrategy {}
        );
        let (vault_cap_2, vault_lock_2) = satay::test_lock_vault<TestStrategy2>(
            0,
            TestStrategy2 {}
        );
        satay::test_unlock_vault<TestStrategy2>(
            vault_cap_2,
            vault_lock_2,
        );
        satay::test_unlock_vault<TestStrategy>(
            vault_cap,
            vault_lock
        )
    }

    // test admin functions
    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47,
    )]
    fun test_admin_functions(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer
    ) {
        setup_test_and_create_vault_with_strategy(
            aptos_framework,
            satay,
            coins_manager,
            user
        );

        let debt_ratio = 100;
        satay::test_update_strategy_debt_ratio(
            0,
            debt_ratio,
            TestStrategy {}
        );
    }
}