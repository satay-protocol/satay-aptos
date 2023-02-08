#[test_only]
module satay::test_satay {

    use std::signer;

    use aptos_framework::coin;
    use aptos_framework::account;
    use aptos_framework::stake;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::timestamp;

    use satay_coins::vault_coin::VaultCoin;

    use satay::satay;
    use satay::coins::{Self, USDT, BTC};
    use satay::vault::{Self};
    use satay::satay_account;

    const MANAGEMENT_FEE: u64 = 200;
    const PERFORMANCE_FEE: u64 = 2000;
    const DEBT_RATIO: u64 = 1000;
    const DEPOSIT_AMOUNT: u64 = 1000;

    const ERR_INITIALIZED: u64 = 1;
    const ERR_NEW_VAULT: u64 = 2;
    const ERR_UPDATE_FEES: u64 = 3;
    const ERR_DEPOSIT: u64 = 4;
    const ERR_WITHDRAW: u64 = 5;
    const ERR_APPROVE_STRATEGY: u64 = 6;
    const ERR_LOCK_UNLOCK: u64 = 7;
    const ERR_FREEZE: u64 = 8;

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
        satay_account::initialize_satay_account(
            satay,
            x"0a5361746179436f696e73020000000000000000403130333837434146364441363631433033364236443031384642423035433530433231374130373745453136413043344338353633373844393938454533414297021f8b08000000000002ff2d903f6fc32010c5773e45e425536c30d8984a9d3a77ca184511704782621b0bb0db7cfb9ab6dbfd79ef774f7759b47dea3b5ec9ac273cbc1f8e679df5eb23f8391dc98631f9309731ab694d8f645dee5103de96307afbda17959fa6356b336245c84503444c09d395a4c2b9d9022a32facd1ce5928343c1ac108a1a66a5b14ab79c0288ce7568a1730cd5c006cd5bca15db0d52236b1903c50b1f703b012e3803ced663aa3fc386e70ca3375772f7b95c7ae4bca4b7a6d9dbc76a6a1ba6462f39a4d3a84dfa2f6d8858ef828a44dc8a093a6994341aa9e985e9991c7ae55ae7da1ea550d8513e8861107d45d26ac0c7e2f9434d7b82c6c5fd7b5f213e9bd29ed26fa2ea0739f85a445d010000020d73747261746567795f636f696ebf011f8b08000000000002ff4d8f410ec2201045f79c620e60d23d312ef4081ab7cd0863db4881c060429ade5d2068246c18fe7fffcf300c303ba323f04c103924c590226978ba00570ec834e58b5b2c94db34c898c1a37ae14462287e4ddeb85c2c8fdc1481a24b4111a0522e590615a860742534b7946f4c864755b0631789d5e9643abefd442963cf6f6fd8049453136bcabd225ab1892c8545f5f64dd417f9ef7ff4335a76eb6f78cb9e0ef09d9e3152959d60dbc52e3ebb49a3451801000000000a7661756c745f636f696eaf011f8b08000000000002ff4d8f310ec2300c45f79cc237c88e1003307002d6cab8a6ad48e32a7190aaaa77278922c0f2643fffff6dad859bb83e828e0c5143228514b987a704b863727a91c943ee0aa0e20a0bd20b0736361f5f7971b266feb156227094148801892479050a8c9af759a15e1f0eefa2da5196ed1a6466e9936bf27513ff31d80ce42a76c5e2976a60cf61a296bb42ed852f735c46f42a339c3172199c60dbcd6e3e1cb58cd7f900000000000000",
            vector[
                x"a11ceb0b0500000005010002020208070a270831200a5105000000010002000100010d73747261746567795f636f696e0c5374726174656779436f696e0b64756d6d795f6669656c641f0373dfe41c4490b1c7bc9a230dd45f5ecd5f1e9818a3203910377ae1211d93000201020100",
                x"a11ceb0b05000000050100020202060708210829200a490500000001000100010a7661756c745f636f696e095661756c74436f696e0b64756d6d795f6669656c641f0373dfe41c4490b1c7bc9a230dd45f5ecd5f1e9818a3203910377ae1211d93000201020100"
            ],

        );
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

    fun user_deposit(
        aptos_framework: &signer,
        user: &signer,
    ) {
        let user_address = signer::address_of(user);
        let amount = 1000;
        aptos_coin::mint(aptos_framework, user_address, amount);
        satay::deposit<AptosCoin>(
            user,
            0,
            amount
        );
    }

    fun approve_strategy(
        aptos_framework: &signer,
        satay: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        satay::test_approve_strategy<TestStrategy, AptosCoin>(
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
        assert!(satay::get_total_assets<AptosCoin>(0) == 0, ERR_NEW_VAULT);
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
    #[expected_failure]
    fun test_update_vault_fee_unauthorized(
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
            user,
            0,
            management_fee,
            performance_fee
        );
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

        user_deposit(aptos_framework, user);
        assert!(coin::balance<VaultCoin<AptosCoin>>(signer::address_of(user)) == DEPOSIT_AMOUNT, ERR_DEPOSIT);

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

        user_deposit(aptos_framework, user);

        satay::withdraw<AptosCoin>(
            user,
            0,
            DEPOSIT_AMOUNT
        );

        let user_address = signer::address_of(user);
        assert!(coin::balance<VaultCoin<AptosCoin>>(user_address) == 0, ERR_WITHDRAW);
        assert!(coin::balance<AptosCoin>(user_address) == DEPOSIT_AMOUNT, ERR_WITHDRAW);
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

        user_deposit(aptos_framework, user);

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
            DEPOSIT_AMOUNT
        );
    }

    // test freeze and unfreeze

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_freeze(
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

        satay::freeze_vault(satay, 0);
        assert!(satay::is_vault_frozen(0), ERR_FREEZE);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    #[expected_failure]
    fun test_freeze_unauthorized(
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

        satay::freeze_vault(user, 0);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_unfreeze(
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

        satay::freeze_vault(satay, 0);
        satay::unfreeze_vault(satay, 0);
        assert!(!satay::is_vault_frozen(0), ERR_FREEZE);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    #[expected_failure]
    fun test_unfreeze_unauthorized(
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

        satay::freeze_vault(satay, 0);
        satay::unfreeze_vault(user, 0);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    #[expected_failure]
    fun test_deposit_after_freeze(
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

        satay::freeze_vault(satay, 0);

        user_deposit(aptos_framework, user);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_withdraw_after_freeze(
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

        user_deposit(aptos_framework, user);

        satay::freeze_vault(satay, 0);

        satay::withdraw<AptosCoin>(
            user,
            0,
            DEPOSIT_AMOUNT
        );

        assert!(coin::balance<AptosCoin>(signer::address_of(user)) == DEPOSIT_AMOUNT, ERR_FREEZE);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_deposit_after_freeze_and_unfreeze(
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

        satay::freeze_vault(satay, 0);
        satay::unfreeze_vault(satay, 0);

        user_deposit(aptos_framework, user);

        assert!(coin::balance<AptosCoin>(signer::address_of(user)) == 0, ERR_FREEZE);
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

        assert!(satay::has_strategy<TestStrategy, AptosCoin>(0), ERR_APPROVE_STRATEGY);
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

        satay::test_approve_strategy<TestStrategy2, AptosCoin>(
            satay,
            0,
            DEBT_RATIO,
            TestStrategy2 {}
        );
        assert!(satay::has_strategy<TestStrategy2, AptosCoin>(0), ERR_APPROVE_STRATEGY);
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
        ) = satay::test_lock_vault<TestStrategy, AptosCoin>(
            0,
            &TestStrategy {}
        );

        satay::test_assert_vault_cap_and_stop_handle_match<TestStrategy>(&vault_cap, &stop_handle);

        satay::test_unlock_vault<TestStrategy, AptosCoin>(vault_cap, stop_handle);
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

        satay::test_approve_strategy<TestStrategy2, AptosCoin>(
            satay,
            0,
            DEBT_RATIO,
            TestStrategy2 {}
        );

        let (vault_cap, stop_handle) = satay::test_lock_vault<TestStrategy, AptosCoin>(
            0,
            &TestStrategy {}
        );
        satay::test_unlock_vault<TestStrategy, AptosCoin>(
            vault_cap,
            stop_handle
        );

        let (vault_cap, stop_handle) = satay::test_lock_vault<TestStrategy2, AptosCoin>(
            0,
            &TestStrategy2 {}
        );
        satay::test_unlock_vault<TestStrategy2, AptosCoin>(
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

        let (vault_cap, vault_lock) = satay::test_lock_vault<TestStrategy2, AptosCoin>(
            0,
            &TestStrategy2 {}
        );
        satay::test_unlock_vault<TestStrategy2, AptosCoin>(
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

        let (vault_cap, vault_lock) = satay::test_lock_vault<TestStrategy, AptosCoin>(
            0,
            &TestStrategy {}
        );
        let (vault_cap_2, vault_lock_2) = satay::test_lock_vault<TestStrategy2, AptosCoin>(
            0,
            &TestStrategy2 {}
        );
        satay::test_unlock_vault<TestStrategy2, AptosCoin>(
            vault_cap_2,
            vault_lock_2,
        );
        satay::test_unlock_vault<TestStrategy, AptosCoin>(
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
    fun test_keeper_lock_unlock_vault(
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

        let (keeper_cap, vault_cap_lock) = satay::test_keeper_lock_vault<TestStrategy, AptosCoin>(
            satay,
            0,
            TestStrategy {}
        );
        satay::test_keeper_unlock_vault<TestStrategy, AptosCoin>(keeper_cap, vault_cap_lock);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47,
    )]
    #[expected_failure]
    fun test_keeper_lock_unlock_vault_unauthorized(
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

        let (keeper_cap, vault_cap_lock) = satay::test_keeper_lock_vault<TestStrategy, AptosCoin>(
            user,
            0,
            TestStrategy {}
        );
        satay::test_keeper_unlock_vault<TestStrategy, AptosCoin>(keeper_cap, vault_cap_lock);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47,
    )]
    fun test_user_lock_unlock_vault(
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

        let (user_cap, vault_cap_lock) = satay::test_user_lock_vault<TestStrategy, AptosCoin>(
            satay,
            0,
            &TestStrategy {}
        );
        satay::test_user_unlock_vault<TestStrategy, AptosCoin>(user_cap, vault_cap_lock);
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
        satay::test_update_strategy_debt_ratio<TestStrategy, AptosCoin>(
            satay,
            0,
            debt_ratio,
            TestStrategy {}
        );
    }
}