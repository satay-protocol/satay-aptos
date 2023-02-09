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
    use satay::coins::{Self, USDT};
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
            x"0a5361746179436f696e73020000000000000000403241383933453237324133313136324437393735414641464239344439333132453041413143323532424139353946393543323536453939343342373946434196021f8b08000000000002ff2d50bd6e833010defd14114ba6800163a052a7ce9d32465174679f132b80916d68f3f6b5db6ef7dd7d7fbacb0aea0977bab205663abc1f8e6788f0fa70760947b6930fd62d795d97bce447b6ad770f9a6eab9bac7aa54361e7798b8013158c5d406b4f2150b8b2907d6e2a1b651affeeb88151486839081c00476ca5a4bad502a996ad018d8d31bcefc4d0b4d874c2d4ed28fb5e0d409cab2efb6bda4f9a565a342dca52283fdd4ee7a8278b5776b731273d625cc35b5525f8d8b0546eae608d2e9c26c0f03f2ae7a94c848279dab348773d8e3da624940265dd0f7234a94e23a9172375bc1dc4300859b0b0a1b63e6bfeace6d4a0323e7defcbf96795e129fc362a7e00444fcab75d010000020d73747261746567795f636f696ec4011f8b08000000000002ff4d8f410ac3201045f79e620e50c85e4a17ed115aba0d539d26a14946742c48c8ddab62a0e2c6f1fff7ff745d0723cf36808c04417c3402319085377bb88b47a121dd785a21dfaa41c1040ecd0707525df65b7233a76c79a5aaf014387a4380c6705c058ca78cb18550dd5a7f31ced29b8ced9b482d6ce3dcf0f527681d5a7e7dc3a6209f9258529e05518b0db4929f4c6b5f456d91fffe6737e22abcc0150395c1098ec9217b24471aac6777816d57bbfa012fb975701e01000000000a7661756c745f636f696eaf011f8b08000000000002ff4d8f310ec2300c45f79cc237c88e1003307002d6cab8a6ad48e32a7190aaaa77278922c0f2643fffff6dad859bb83e828e0c5143228514b987a704b863727a91c943ee0aa0e20a0bd20b0736361f5f7971b266feb156227094148801892479050a8c9af759a15e1f0eefa2da5196ed1a6466e9936bf27513ff31d80ce42a76c5e2976a60cf61a296bb42ed852f735c46f42a339c3172199c60dbcd6e3e1cb58cd7f900000000000000",
            vector[
                x"a11ceb0b0500000005010002020208070a270831200a5105000000010002000102010d73747261746567795f636f696e0c5374726174656779436f696e0b64756d6d795f6669656c6450fa946a30a4b8ab9b366e13d4be163fadb2ff0754823b254f139677c8ae00c5000201020100",
                x"a11ceb0b05000000050100020202060708210829200a490500000001000100010a7661756c745f636f696e095661756c74436f696e0b64756d6d795f6669656c6450fa946a30a4b8ab9b366e13d4be163fadb2ff0754823b254f139677c8ae00c5000201020100"
            ],
        );
        satay::initialize(satay);
        coins::register_coins(coins_manager);

        account::create_account_for_test(signer::address_of(user));
        coin::register<AptosCoin>(user);
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
            amount
        );
    }

    fun approve_strategy(
        aptos_framework: &signer,
        satay: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        satay::test_approve_strategy<AptosCoin, TestStrategy>(
            satay,
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
        assert!(satay::get_total_assets<AptosCoin>() == 0, ERR_NEW_VAULT);
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

        satay::update_vault_fee<AptosCoin>(
            satay,
            management_fee,
            performance_fee
        );

        let vault_cap = satay::test_lock_vault<AptosCoin>();
        let (management_fee_val, performance_fee_val) = vault::get_fees(&vault_cap);
        satay::test_unlock_vault(vault_cap);

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

        satay::update_vault_fee<AptosCoin>(
            user,
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

        let vault_cap = satay::test_lock_vault<AptosCoin>();

        let credit = vault::credit_available<AptosCoin, TestStrategy>(&vault_cap);
        let aptos = vault::test_withdraw_base_coin<AptosCoin, TestStrategy>(
            &vault_cap,
            credit,
            &TestStrategy {}
        );
        coin::deposit(signer::address_of(aptos_framework), aptos);

        satay::test_unlock_vault<AptosCoin>(vault_cap);

        satay::withdraw<AptosCoin>(
            user,
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

        satay::freeze_vault<AptosCoin>(satay);
        assert!(satay::is_vault_frozen<AptosCoin>(), ERR_FREEZE);
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

        satay::freeze_vault<AptosCoin>(user);
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

        satay::freeze_vault<AptosCoin>(satay);
        satay::unfreeze_vault<AptosCoin>(satay);
        assert!(!satay::is_vault_frozen<AptosCoin>(), ERR_FREEZE);
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

        satay::freeze_vault<AptosCoin>(satay);
        satay::unfreeze_vault<AptosCoin>(user);
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

        satay::freeze_vault<AptosCoin>(satay);

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

        satay::freeze_vault<AptosCoin>(satay);

        satay::withdraw<AptosCoin>(
            user,
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

        satay::freeze_vault<AptosCoin>(satay);
        satay::unfreeze_vault<AptosCoin>(satay);

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

        assert!(satay::has_strategy<AptosCoin, TestStrategy>(), ERR_APPROVE_STRATEGY);
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

        satay::test_approve_strategy<AptosCoin, TestStrategy2>(
            satay,
            DEBT_RATIO,
            TestStrategy2 {}
        );
        assert!(satay::has_strategy<AptosCoin, TestStrategy2>(), ERR_APPROVE_STRATEGY);
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

        let vault_cap = satay::test_strategy_lock_vault<AptosCoin, TestStrategy>(
            &TestStrategy {}
        );
        satay::test_strategy_unlock_vault<AptosCoin, TestStrategy>(vault_cap);
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

        satay::test_approve_strategy<AptosCoin, TestStrategy2>(
            satay,
            DEBT_RATIO,
            TestStrategy2 {}
        );

        let vault_cap = satay::test_strategy_lock_vault<AptosCoin, TestStrategy>(&TestStrategy {});
        satay::test_strategy_unlock_vault<AptosCoin, TestStrategy>(vault_cap, );
        let vault_cap = satay::test_strategy_lock_vault<AptosCoin, TestStrategy2>(&TestStrategy2 {});
        satay::test_strategy_unlock_vault<AptosCoin, TestStrategy2>(vault_cap, );
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

        let vault_cap = satay::test_strategy_lock_vault<AptosCoin, TestStrategy2>(&TestStrategy2 {});
        satay::test_strategy_unlock_vault<AptosCoin, TestStrategy2>(vault_cap)
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

        satay::test_approve_strategy<AptosCoin, TestStrategy2>(
            satay,
            DEBT_RATIO,
            TestStrategy2 {}
        );

        let vault_cap = satay::test_strategy_lock_vault<AptosCoin, TestStrategy>(&TestStrategy {});
        let vault_cap_2 = satay::test_strategy_lock_vault<AptosCoin, TestStrategy2>(&TestStrategy2 {});
        satay::test_strategy_unlock_vault<AptosCoin, TestStrategy2>(vault_cap_2);
        satay::test_strategy_unlock_vault<AptosCoin, TestStrategy>(vault_cap);
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

        let keeper_cap = satay::test_keeper_lock_vault<AptosCoin, TestStrategy>(
            satay,
            TestStrategy {}
        );
        satay::test_keeper_unlock_vault<AptosCoin, TestStrategy>(keeper_cap);
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

        let keeper_cap = satay::test_keeper_lock_vault<AptosCoin, TestStrategy>(
            user,
            TestStrategy {}
        );
        satay::test_keeper_unlock_vault<AptosCoin, TestStrategy>(keeper_cap);
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

        let user_cap = satay::test_user_lock_vault<AptosCoin>(satay, );
        satay::test_user_unlock_vault<AptosCoin>(user_cap);
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
        satay::test_update_strategy_debt_ratio<AptosCoin, TestStrategy>(
            satay,
            debt_ratio,
            TestStrategy {}
        );
    }
}