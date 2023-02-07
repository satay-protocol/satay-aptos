#[test_only]
module satay::test_vault {

    use std::signer;

    use aptos_std::type_info;

    use aptos_framework::coin;
    use aptos_framework::account;
    use aptos_framework::stake;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::timestamp;

    use satay_vault_coin::vault_coin::VaultCoin;

    use satay::vault::{Self, VaultCapability, VaultManagerCapability};
    use satay::coins::{Self, USDT};
    use satay::dao_storage;
    use satay::vault_coin_account;
    use satay::satay;
    use satay::strategy_coin;
    use satay::strategy_coin::StrategyCoin;

    struct TestStrategy has drop {}

    const MAX_DEBT_RATIO_BPS: u64 = 10000;
    const SECS_PER_YEAR: u64 = 31556952; // 365.2425 days

    const DEFAULT_MAX_REPORT_DELAY: u64 = 30 * 24 * 3600; // 30 days
    const DEFAULT_CREDIT_THRESHOLD: u64 = 10000; // 10,000

    const MANAGEMENT_FEE: u64 = 200;
    const PERFORMANCE_FEE: u64 = 2000;
    const DEBT_RATIO: u64 = 6000;
    const USER_DEPOSIT: u64 = 1000;

    const ERR_CREATE_VAULT: u64 = 1;
    const ERR_FEES: u64 = 2;
    const ERR_DEPOSIT_WITHDRAW: u64 = 3;
    const ERR_DEPOIST_WITHDRAW_AS_USER: u64 = 4;
    const ERR_STRATEGY: u64 = 5;
    const ERR_INCORRECT_VAULT_COIN_AMOUNT: u64 = 6;
    const ERR_STRATEGY_BASE_COIN_DEPOSIT_WITHDRAW: u64 = 7;
    const ERR_STRATEGY_COIN_DEPOSIT_WITHDRAW: u64 = 8;
    const ERR_STRATEGY_UPDATE: u64 = 9;
    const ERR_REPORTING: u64 = 10;
    const ERR_ASSESS_FEES: u64 = 11;
    const ERR_DEBT_PAYMENT: u64 = 12;
    const ERR_DEPOSIT_PROFIT: u64 = 13;
    const ERR_FREEZE_VAULT: u64 = 14;
    const ERR_PREPARE_RETURN: u64 = 15;
    const ERR_USER_LIQUIDATION: u64 = 16;

    #[test_only]
    fun setup_tests(
        aptos_framework: &signer,
        satay: &signer,
        user: &signer,
    ) {
        stake::initialize_for_test(aptos_framework);
        account::create_account_for_test(signer::address_of(user));
        coin::register<AptosCoin>(user);
        coin::register<VaultCoin<AptosCoin>>(user);
        vault_coin_account::initialize_satay_account(
            satay,
            x"0e53617461795661756c74436f696e020000000000000000404442334638364131454231354432454538373446303132424334384439373142373336344135453630354646303432353235434633383145383930333445334587021f8b08000000000002ff2d90cd6ec3201084ef3c45e44b4eb621fea5524f3df714a997c8b216583b28365880dde6ed0b6d6e3b3bb3f3497bdb403e60c6811858f1f47e3a5f21c0f30bf6257c586dcee440e7b535c962052de899ecdbec40e1b8d945cb673432bdae7b00b16046c80d9472e83dfa81f8d4351ea96c94b12d65e90f6d8077bc6f812b5a3159376d87ac111def0436ace58cca498a9a356dc52e757fc149b6c0b8a45051c9eb3e41141eb9c20d8d422335fae2d31e780d6ad16220b30e89740f61f36f6519e57d1785b46b095bb03e5f40f8d728adc3220632e2f048472b6863306abf0ba55d5afd27d708282717bff46ddda34c32f77fc0ec173b2d8c9145010000010a7661756c745f636f696e5d1f8b08000000000002ff45c8310a80300c40d13da7c8398a38e81d5c4ba80585b6119308527a77dbc93f7d5ee6dd524421a5d73f64497de0b338f73f56c09ee86d41711bbe769eae838a72c685240e98b13668f00109fb6b9d5200000000000000",
            x"a11ceb0b05000000050100020202060708210829200a490500000001000100010a7661756c745f636f696e095661756c74436f696e0b64756d6d795f6669656c6405a97986a9d031c4567e15b797be516910cfcb4156312482efc6a19c0a30c948000201020100"
        );
        satay::initialize(satay)
    }

    #[test_only]
    fun create_vault(
        governance: &signer,
    ): VaultCapability {
        vault::new_test<AptosCoin>(
            governance,
            0,
            MANAGEMENT_FEE,
            PERFORMANCE_FEE
        )
    }

    #[test_only]
    fun setup_tests_with_vault(
        aptos_framework: &signer,
        satay: &signer,
        user: &signer,
    ): VaultCapability {
        setup_tests(aptos_framework, satay, user);
        create_vault(satay)
    }

    #[test_only]
    fun approve_strategy(
        vault_manager_cap: &VaultManagerCapability
    ) {
        vault::test_approve_strategy<TestStrategy, AptosCoin>(
            vault_manager_cap,
            DEBT_RATIO,
            TestStrategy {}
        )
    }

    fun setup_tests_with_vault_and_strategy(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer,
    ): VaultCapability {
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, user);
        let vault_manager_cap = vault::test_get_vault_manager_cap(vault_manager, vault_cap);
        approve_strategy(&vault_manager_cap);
        vault::test_destroy_vault_manager_cap(vault_manager_cap)
    }

    fun user_deposit_base_coin(
        aptos_framework: &signer,
        user: &signer,
        vault_cap: VaultCapability,
    ): VaultCapability {
        let user_address = signer::address_of(user);
        aptos_coin::mint(aptos_framework, user_address, USER_DEPOSIT);
        let base_coin = coin::withdraw<AptosCoin>(user, USER_DEPOSIT);
        vault::test_deposit_as_user(user, vault_cap, base_coin)
    }

    fun cleanup_tests(
        vault_cap: VaultCapability,
    ) {
        vault::test_destroy_vault_cap(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        user=@0x46,
    )]
    fun test_create_vault(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer
    ){
        setup_tests(aptos_framework, vault_manager, user);
        let vault_cap = create_vault(vault_manager);

        assert!(vault::get_base_coin_type(&vault_cap) == type_info::type_of<AptosCoin>(), ERR_CREATE_VAULT);
        assert!(coin::decimals<VaultCoin<AptosCoin>>() == coin::decimals<AptosCoin>(), ERR_CREATE_VAULT);
        let (management_fee, performance_fee) = vault::get_fees(&vault_cap);
        assert!(management_fee == MANAGEMENT_FEE, ERR_CREATE_VAULT);
        assert!(performance_fee == PERFORMANCE_FEE, ERR_CREATE_VAULT);
        assert!(vault::get_debt_ratio(&vault_cap) == 0, ERR_CREATE_VAULT);
        assert!(vault::get_total_debt(&vault_cap) == 0, ERR_CREATE_VAULT);

        assert!(vault::has_coin<AptosCoin>(&vault_cap), 0);
        assert!(vault::balance<AptosCoin>(&vault_cap) == 0, 0);

        assert!(vault::vault_cap_has_id(&vault_cap, 0), 0);
        cleanup_tests(vault_cap);
    }

    // test fees

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        user=@0x46,
    )]
    fun test_update_fee(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, user);
        let management_fee = 1000;
        let performance_fee = 2000;
        let vault_manager_cap = vault::test_get_vault_manager_cap(vault_manager, vault_cap);
        vault::test_update_fee(&vault_manager_cap, management_fee, performance_fee);
        vault_cap = vault::test_destroy_vault_manager_cap(vault_manager_cap);
        let (management_fee_val, performance_fee_val) = vault::get_fees(&vault_cap);
        assert!(management_fee_val == management_fee, ERR_FEES);
        assert!(performance_fee_val == performance_fee, ERR_FEES);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        user=@0x46,
    )]
    #[expected_failure]
    fun test_update_management_fee_reject(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, user);
        let vault_manager_cap = vault::test_get_vault_manager_cap(vault_manager, vault_cap);
        let management_fee = 5001;
        let performance_fee = 0;
        vault::test_update_fee(&vault_manager_cap, management_fee, performance_fee);
        vault_cap = vault::test_destroy_vault_manager_cap(vault_manager_cap);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        user=@0x46,
    )]
    #[expected_failure]
    fun test_update_performance_fee_reject(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, user);
        let vault_manager_cap = vault::test_get_vault_manager_cap(vault_manager, vault_cap);
        let management_fee = 0;
        let performance_fee = 5001;
        vault::test_update_fee(&vault_manager_cap, management_fee, performance_fee);
        vault_cap = vault::test_destroy_vault_manager_cap(vault_manager_cap);
        cleanup_tests(vault_cap);
    }

    // test deposit and withdraw

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        user=@0x46,
    )]
    fun test_deposit(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, user);

        let user_address = signer::address_of(user);
        let amount = 100;

        aptos_coin::mint(aptos_framework, user_address, amount);
        vault::test_deposit<AptosCoin>(&vault_cap, coin::withdraw<AptosCoin>(user, amount));
        assert!(vault::balance<AptosCoin>(&vault_cap) == amount, ERR_DEPOSIT_WITHDRAW);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        user=@0x46,
    )]
    fun test_withdraw(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, user);

        let user_address = signer::address_of(user);
        let amount = 100;

        aptos_coin::mint(aptos_framework, user_address, amount);
        vault::test_deposit<AptosCoin>(&vault_cap, coin::withdraw<AptosCoin>(user, amount));

        let aptos_coin = vault::test_withdraw<AptosCoin>(&vault_cap, amount);
        coin::deposit<AptosCoin>(user_address, aptos_coin);
        assert!(vault::balance<AptosCoin>(&vault_cap) == 0, ERR_DEPOSIT_WITHDRAW);
        assert!(coin::balance<AptosCoin>(user_address) == amount, ERR_DEPOSIT_WITHDRAW);
        cleanup_tests(vault_cap);
    }

    // test deposit and withdraw as user

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        user=@0x46,
    )]
    fun test_deposit_as_user(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer
    ){

        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, user);

        let user_address = signer::address_of(user);
        let amount = 100;

        aptos_coin::mint(aptos_framework, user_address, amount);
        vault_cap = vault::test_deposit_as_user<AptosCoin>(
            user,
            vault_cap,
            coin::withdraw<AptosCoin>(user, amount)
        );

        assert!(vault::balance<AptosCoin>(&vault_cap) == amount, ERR_DEPOIST_WITHDRAW_AS_USER);
        assert!(vault::is_vault_coin_registered<AptosCoin>(user_address), ERR_DEPOIST_WITHDRAW_AS_USER);
        assert!(vault::vault_coin_balance<AptosCoin>(user_address) == amount, ERR_DEPOIST_WITHDRAW_AS_USER);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        token_admin=@satay,
        user=@0x46,
    )]
    #[expected_failure]
    fun test_deposit_as_user_incorrect_base_coin(
        aptos_framework: &signer,
        vault_manager: &signer,
        token_admin: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, user);

        let user_address = signer::address_of(user);
        let amount = 100;

        coins::register_coin<USDT>(token_admin);
        coins::mint_coin<USDT>(token_admin, user_address, amount);

        vault_cap = vault::test_deposit_as_user<USDT>(
            user,
            vault_cap,
            coin::withdraw<USDT>(user, amount)
        );
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        user=@0x46,
    )]
    fun test_withdraw_as_user(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer
    ){

        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, user);

        let user_address = signer::address_of(user);
        let amount = 100;

        aptos_coin::mint(aptos_framework, user_address, amount);
        vault_cap = vault::test_deposit_as_user<AptosCoin>(
            user,
            vault_cap,
            coin::withdraw<AptosCoin>(user, amount)
        );
        vault_cap = vault::test_withdraw_as_user<AptosCoin>(
            user,
            vault_cap,
            coin::withdraw<VaultCoin<AptosCoin>>(user, amount)
        );
        assert!(vault::vault_coin_balance<AptosCoin>(user_address) == 0, ERR_DEPOIST_WITHDRAW_AS_USER);
        assert!(coin::balance<AptosCoin>(user_address) == amount, ERR_DEPOIST_WITHDRAW_AS_USER);
        assert!(vault::balance<AptosCoin>(&vault_cap) == 0, ERR_DEPOIST_WITHDRAW_AS_USER);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        user=@0x46,
    )]
    #[expected_failure]
    fun test_withdraw_as_user_incorrect_base_coin(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, user);

        let user_address = signer::address_of(user);
        let amount = 100;

        aptos_coin::mint(aptos_framework, user_address, amount);
        vault_cap = vault::test_deposit_as_user<AptosCoin>(
            user,
            vault_cap,
            coin::withdraw<AptosCoin>(user, amount)
        );
        vault_cap = vault::test_withdraw_as_user<USDT>(
            user,
            vault_cap,
            coin::withdraw<VaultCoin<USDT>>(user, amount)
        );
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        user=@0x46,
    )]
    #[expected_failure]
    fun test_withdraw_as_user_not_enough_vault_coin(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, user);

        let user_address = signer::address_of(user);
        let amount = 100;

        aptos_coin::mint(aptos_framework, user_address, amount);
        vault_cap = vault::test_deposit_as_user<AptosCoin>(
            user,
            vault_cap,
            coin::withdraw<AptosCoin>(user, amount)
        );
        vault_cap = vault::test_withdraw_as_user<AptosCoin>(
            user,
            vault_cap,
            coin::withdraw<VaultCoin<AptosCoin>>(user, amount + 1)
        );
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        user=@0x46,
    )]
    fun test_withdraw_as_user_after_farm(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, user);

        let user_address = signer::address_of(user);
        let amount = 100;

        aptos_coin::mint(aptos_framework, user_address, amount);
        vault_cap = vault::test_deposit_as_user<AptosCoin>(
            user,
            vault_cap,
            coin::withdraw<AptosCoin>(user, amount / 2)
        );
        vault::test_deposit<AptosCoin>(
            &vault_cap,
            coin::withdraw<AptosCoin>(user, amount / 2)
        );

        assert!(vault::vault_coin_balance<AptosCoin>(user_address) == amount / 2, ERR_DEPOIST_WITHDRAW_AS_USER);

        vault_cap = vault::test_withdraw_as_user<AptosCoin>(
            user,
            vault_cap,
            coin::withdraw<VaultCoin<AptosCoin>>(user, amount / 2)
        );

        assert!(vault::vault_coin_balance<AptosCoin>(user_address) == 0, ERR_DEPOIST_WITHDRAW_AS_USER);
        assert!(coin::balance<AptosCoin>(user_address) == amount, ERR_DEPOIST_WITHDRAW_AS_USER);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        user_a =@0x46,
        user_b =@0x047
    )]
    fun test_share_amount_calculation(
        aptos_framework: &signer,
        vault_manager: &signer,
        user_a: &signer,
        user_b: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, user_a);
        let user_a_address = signer::address_of(user_a);
        let user_b_address = signer::address_of(user_b);
        account::create_account_for_test(user_b_address);
        coin::register<AptosCoin>(user_b);

        // for the first depositor, mint amount equal to deposit
        let user_a_amount = 1000;
        let user_a_deposit_amount = 100;
        aptos_coin::mint(aptos_framework, user_a_address, user_a_amount);
        vault_cap = vault::test_deposit_as_user<AptosCoin>(
            user_a,
            vault_cap,
            coin::withdraw<AptosCoin>(user_a, user_a_deposit_amount)
        );
        assert!(vault::vault_coin_balance<AptosCoin>(user_a_address) == user_a_deposit_amount, ERR_INCORRECT_VAULT_COIN_AMOUNT);

        // userB deposit 1000 coins
        // @dev: userB should get 10x token than userA
        let user_b_amount = 1000;
        let user_b_deposit_amount = 1000;
        aptos_coin::mint(aptos_framework, user_b_address, user_b_amount);
        coin::register<VaultCoin<AptosCoin>>(user_b);
        vault_cap = vault::test_deposit_as_user<AptosCoin>(
            user_b,
            vault_cap,
            coin::withdraw<AptosCoin>(
                user_b,
                user_b_deposit_amount
            )
        );
        assert!(vault::vault_coin_balance<AptosCoin>(user_b_address) == user_b_deposit_amount, ERR_INCORRECT_VAULT_COIN_AMOUNT);

        // userA deposit 400 coins
        // userA should have 500 shares in total
        let user_a_second_deposit_amount = 400;
        vault_cap = vault::test_deposit_as_user<AptosCoin>(
            user_a,
            vault_cap,
            coin::withdraw<AptosCoin>(user_a, user_a_second_deposit_amount)
        );
        let user_a_total_deposits = user_a_deposit_amount + user_a_second_deposit_amount;
        assert!(coin::balance<VaultCoin<AptosCoin>>(user_a_address) == user_a_total_deposits, ERR_INCORRECT_VAULT_COIN_AMOUNT);

        let farm_amount = 300;
        vault::test_deposit(&vault_cap, coin::withdraw<AptosCoin>(user_a, farm_amount));
        // userA withdraw 500 shares
        // userA should withdraw (1500 + 300) * 500 / 1500
        let total_deposits = user_a_total_deposits + user_b_deposit_amount + farm_amount;
        let user_a_withdraw_amount = user_a_total_deposits;
        let user_a_balance_before = coin::balance<AptosCoin>(user_a_address);
        vault_cap = vault::test_withdraw_as_user<AptosCoin>(
            user_a,
            vault_cap,
            coin::withdraw<VaultCoin<AptosCoin>>(user_a, user_a_withdraw_amount)
        );
        let withdraw_amount = coin::balance<AptosCoin>(user_a_address) - user_a_balance_before;
        let expected_withdraw_amount = (total_deposits + farm_amount) / total_deposits * withdraw_amount;
        assert!(withdraw_amount == expected_withdraw_amount, ERR_INCORRECT_VAULT_COIN_AMOUNT);
        cleanup_tests(vault_cap);
    }


    // test freeze and unfreeze

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        user=@0x46,
    )]
    fun test_freeze_vault(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, user);
        let vault_manager_cap = vault::test_get_vault_manager_cap(vault_manager, vault_cap);
        vault::test_freeze_vault(&vault_manager_cap);
        vault_cap = vault::test_destroy_vault_manager_cap(vault_manager_cap);
        assert!(vault::is_vault_frozen(&vault_cap), ERR_FREEZE_VAULT);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        user=@0x46,
    )]
    #[expected_failure]
    fun test_freeze_while_frozen(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, user);
        let vault_manager_cap = vault::test_get_vault_manager_cap(vault_manager, vault_cap);
        vault::test_freeze_vault(&vault_manager_cap);
        vault::test_freeze_vault(&vault_manager_cap);
        vault_cap = vault::test_destroy_vault_manager_cap(vault_manager_cap);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        user=@0x46,
    )]
    fun test_unfreeze_vault(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, user);
        let vault_manager_cap = vault::test_get_vault_manager_cap(vault_manager, vault_cap);
        vault::test_freeze_vault(&vault_manager_cap);
        vault::test_unfreeze_vault(&vault_manager_cap);
        vault_cap = vault::test_destroy_vault_manager_cap(vault_manager_cap);
        assert!(!vault::is_vault_frozen(&vault_cap), ERR_FREEZE_VAULT);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        user=@0x46,
    )]
    #[expected_failure]
    fun test_unfreeze_while_unfrozen(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, user);
        let vault_manager_cap = vault::test_get_vault_manager_cap(vault_manager, vault_cap);
        vault::test_unfreeze_vault(&vault_manager_cap);
        vault_cap = vault::test_destroy_vault_manager_cap(vault_manager_cap);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        user=@0x46,
    )]
    fun test_withdraw_after_freeze(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, user);
        let vault_cap = user_deposit_base_coin(aptos_framework, user, vault_cap);
        let vault_manager_cap = vault::test_get_vault_manager_cap(vault_manager, vault_cap);
        vault::test_freeze_vault(&vault_manager_cap);
        vault_cap = vault::test_destroy_vault_manager_cap(vault_manager_cap);
        let user_address = signer::address_of(user);
        vault_cap = vault::test_withdraw_as_user<AptosCoin>(
            user,
            vault_cap,
            coin::withdraw<VaultCoin<AptosCoin>>(user, USER_DEPOSIT)
        );
        assert!(vault::balance<AptosCoin>(&vault_cap) == 0, ERR_FREEZE_VAULT);
        assert!(coin::balance<AptosCoin>(user_address) == USER_DEPOSIT, ERR_FREEZE_VAULT);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        user=@0x46,
    )]
    #[expected_failure]
    fun test_deposit_after_freeze(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, user);
        let vault_manager_cap = vault::test_get_vault_manager_cap(vault_manager, vault_cap);
        vault::test_freeze_vault(&vault_manager_cap);
        vault_cap = vault::test_destroy_vault_manager_cap(vault_manager_cap);
        vault_cap = user_deposit_base_coin(aptos_framework, user, vault_cap);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        user=@0x46,
    )]
    fun test_deposit_after_unfreeze(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, user);
        let vault_manager_cap = vault::test_get_vault_manager_cap(vault_manager, vault_cap);
        vault::test_freeze_vault(&vault_manager_cap);
        vault::test_unfreeze_vault(&vault_manager_cap);
        vault_cap = vault::test_destroy_vault_manager_cap(vault_manager_cap);
        vault_cap = user_deposit_base_coin(aptos_framework, user, vault_cap);
        assert!(vault::balance<AptosCoin>(&vault_cap) == USER_DEPOSIT, ERR_FREEZE_VAULT);
        cleanup_tests(vault_cap);
    }

    // test strategy functions

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        user=@0x46,
    )]
    fun test_approve_strategy(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, user);
        let vault_manager_cap = vault::test_get_vault_manager_cap(vault_manager, vault_cap);
        approve_strategy(&vault_manager_cap);
        vault_cap = vault::test_destroy_vault_manager_cap(vault_manager_cap);

        let user_address = signer::address_of(user);
        let amount = 100;

        aptos_coin::mint(aptos_framework, user_address, amount);
        vault::test_deposit<AptosCoin>(&vault_cap, coin::withdraw<AptosCoin>(user, amount));

        assert!(vault::has_strategy<TestStrategy, AptosCoin>(&vault_cap), ERR_STRATEGY);
        assert!(vault::debt_ratio<TestStrategy, AptosCoin>(&vault_cap) == DEBT_RATIO, ERR_STRATEGY);
        assert!(vault::credit_available<TestStrategy, AptosCoin>(&vault_cap) == amount * DEBT_RATIO / MAX_DEBT_RATIO_BPS, ERR_STRATEGY);
        assert!(vault::debt_out_standing<TestStrategy, AptosCoin>(&vault_cap) == 0, ERR_STRATEGY);
        assert!(vault::total_debt<TestStrategy, AptosCoin>(&vault_cap) == 0, ERR_STRATEGY);
        assert!(vault::last_report<TestStrategy, AptosCoin>(&vault_cap) == timestamp::now_seconds(), ERR_STRATEGY);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        user=@0x46,
    )]
    fun test_strategy_deposit_base_coin(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, vault_manager, user);

        let user_address = signer::address_of(user);
        let amount = 100;
        aptos_coin::mint(aptos_framework, user_address, amount);
        let base_coins = coin::withdraw<AptosCoin>(user, amount);

        vault::test_deposit_base_coin<TestStrategy, AptosCoin>(
            &vault_cap,
            base_coins,
            &TestStrategy {}
        );
        assert!(vault::balance<AptosCoin>(&vault_cap) == amount, ERR_DEPOSIT_WITHDRAW);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        token_admin=@satay,
        user=@0x46,
    )]
    #[expected_failure]
    fun test_strategy_deposit_incorrect_base_coin(
        aptos_framework: &signer,
        vault_manager: &signer,
        token_admin: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, vault_manager, user);

        coins::register_coin<USDT>(token_admin);

        let user_address = signer::address_of(user);
        let amount = 100;
        coins::mint_coin<USDT>(token_admin, user_address, amount);
        let incorrect_base_coins = coin::withdraw<USDT>(user, amount);

        vault::test_deposit_base_coin<TestStrategy, USDT>(
            &vault_cap,
            incorrect_base_coins,
            &TestStrategy {}
        );
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        user=@0x46,
    )]
    fun test_strategy_withdraw_base_coin(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, vault_manager, user);

        let user_address = signer::address_of(user);
        let amount = 100;
        aptos_coin::mint(aptos_framework, user_address, amount);
        let base_coins = coin::withdraw<AptosCoin>(user, amount);

        vault::test_deposit_base_coin<TestStrategy, AptosCoin>(
            &vault_cap,
            base_coins,
            &TestStrategy {}
        );

        let withdraw_amount = vault::credit_available<TestStrategy, AptosCoin>(&vault_cap);
        let base_coins = vault::test_withdraw_base_coin<TestStrategy, AptosCoin>(
            &vault_cap,
            withdraw_amount,
            &TestStrategy {}
        );
        coin::deposit(user_address, base_coins);

        assert!(coin::balance<AptosCoin>(user_address) == withdraw_amount, ERR_STRATEGY_BASE_COIN_DEPOSIT_WITHDRAW);
        assert!(vault::total_debt<TestStrategy, AptosCoin>(&vault_cap) == withdraw_amount, ERR_STRATEGY_BASE_COIN_DEPOSIT_WITHDRAW);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        user=@0x46,
    )]
    #[expected_failure]
    fun test_strategy_withdraw_base_coin_over_credit_availale(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, vault_manager, user);

        let user_address = signer::address_of(user);
        let amount = 100;
        aptos_coin::mint(aptos_framework, user_address, amount);
        let base_coins = coin::withdraw<AptosCoin>(user, amount);

        vault::test_deposit_base_coin<TestStrategy, AptosCoin>(
            &vault_cap,
            base_coins,
            &TestStrategy {}
        );

        let withdraw_amount = amount * DEBT_RATIO / MAX_DEBT_RATIO_BPS + 1;
        let base_coins = vault::test_withdraw_base_coin<TestStrategy, AptosCoin>(
            &vault_cap,
            withdraw_amount,
            &TestStrategy {}
        );
        coin::deposit(user_address, base_coins);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        user=@0x46,
    )]
    #[expected_failure]
    fun test_strategy_withdraw_wrong_base_coin(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, vault_manager, user);

        let user_address = signer::address_of(user);
        let amount = 100;
        aptos_coin::mint(aptos_framework, user_address, amount);
        let base_coins = coin::withdraw<AptosCoin>(user, amount);

        vault::test_deposit_base_coin<TestStrategy, AptosCoin>(
            &vault_cap,
            base_coins,
            &TestStrategy {}
        );

        let base_coins = vault::test_withdraw_base_coin<TestStrategy, USDT>(
            &vault_cap,
            0,
            &TestStrategy {}
        );
        coin::deposit(user_address, base_coins);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        keeper=@satay,
        user=@0x46,
    )]
    fun test_debt_payment(
        aptos_framework: &signer,
        keeper: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, keeper, user);
        vault_cap = user_deposit_base_coin(aptos_framework, user, vault_cap);

        let credit_available = vault::credit_available<TestStrategy, AptosCoin>(&vault_cap);
        let base_coin = vault::test_withdraw_base_coin<TestStrategy, AptosCoin>(
            &vault_cap,
            credit_available,
            &TestStrategy {}
        );
        assert!(vault::total_debt<TestStrategy, AptosCoin>(&vault_cap) == credit_available, ERR_DEBT_PAYMENT);

        let debt_payment_amount = 50;
        let debt_payment = coin::extract(&mut base_coin, debt_payment_amount);
        let keeper_cap = vault::test_get_keeper_cap<TestStrategy, AptosCoin>(keeper, vault_cap, TestStrategy {});
        vault::test_keeper_debt_payment<TestStrategy, AptosCoin>(&keeper_cap, debt_payment);
        coin::deposit(signer::address_of(user), base_coin);
        vault_cap = vault::test_destroy_keeper_cap(keeper_cap);

        assert!(vault::balance<AptosCoin>(&vault_cap) == USER_DEPOSIT - credit_available + debt_payment_amount, ERR_DEPOSIT_WITHDRAW);
        assert!(vault::total_debt<TestStrategy, AptosCoin>(&vault_cap) == credit_available - debt_payment_amount, ERR_DEBT_PAYMENT);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        keeper=@satay,
        user=@0x46,
    )]
    fun test_deposit_profit(
        aptos_framework: &signer,
        keeper: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, keeper, user);
        vault_cap = user_deposit_base_coin(aptos_framework, user, vault_cap);

        let seconds = 1000;
        timestamp::fast_forward_seconds(seconds);

        let profit_amount = 100;
        aptos_coin::mint(aptos_framework, signer::address_of(user), profit_amount);
        let profit = coin::withdraw<AptosCoin>(user, profit_amount);
        let performance_fee = profit_amount * PERFORMANCE_FEE / MAX_DEBT_RATIO_BPS;
        let management_fee = (
            vault::total_debt<TestStrategy, AptosCoin>(&vault_cap) *
                seconds * MANAGEMENT_FEE / MAX_DEBT_RATIO_BPS /
                SECS_PER_YEAR
        );
        let expected_fee = vault::calculate_vault_coin_amount_from_base_coin_amount<AptosCoin>(
            &vault_cap,
            performance_fee + management_fee
        );

        let keeper_cap = vault::test_get_keeper_cap<TestStrategy, AptosCoin>(keeper, vault_cap, TestStrategy {});
        vault::test_deposit_profit<TestStrategy, AptosCoin>(&keeper_cap, profit);
        vault_cap = vault::test_destroy_keeper_cap(keeper_cap);

        assert!(vault::balance<AptosCoin>(&vault_cap) == USER_DEPOSIT + profit_amount, ERR_DEPOSIT_PROFIT);
        let vault_address = vault::get_vault_addr(&vault_cap);
        assert!(dao_storage::balance<VaultCoin<AptosCoin>>(vault_address) == expected_fee, ERR_DEPOSIT_PROFIT);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        keeper=@satay,
        user=@0x46
    )]
    fun test_deposit_strategy_coin(
        aptos_framework: &signer,
        keeper: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, keeper, user);

        strategy_coin::initialize<TestStrategy, AptosCoin>(keeper, TestStrategy {});
        let amount = 100;
        let strategy_coins = strategy_coin::mint<TestStrategy, AptosCoin>(
            amount,
            TestStrategy {}
        );

        let keeper_cap = vault::test_get_keeper_cap<TestStrategy, AptosCoin>(keeper, vault_cap, TestStrategy {});
        vault::test_deposit_strategy_coin<TestStrategy, AptosCoin>(
            &keeper_cap,
            strategy_coins,
        );
        vault_cap = vault::test_destroy_keeper_cap(keeper_cap);
        assert!(vault::balance<StrategyCoin<TestStrategy, AptosCoin>>(&vault_cap) == amount, ERR_STRATEGY_COIN_DEPOSIT_WITHDRAW);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        keeper=@satay,
        user=@0x46
    )]
    fun test_withdraw_strategy_coin(
        aptos_framework: &signer,
        keeper: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, keeper, user);

        strategy_coin::initialize<TestStrategy, AptosCoin>(keeper, TestStrategy {});
        let amount = 100;
        let strategy_coins = strategy_coin::mint<TestStrategy, AptosCoin>(
            amount,
            TestStrategy {}
        );

        let keeper_cap = vault::test_get_keeper_cap<TestStrategy, AptosCoin>(keeper, vault_cap, TestStrategy {});
        vault::test_deposit_strategy_coin<TestStrategy, AptosCoin>(
            &keeper_cap,
            strategy_coins,
        );
        let strategy_coins = vault::test_withdraw_strategy_coin<TestStrategy, AptosCoin>(
            &keeper_cap,
            amount,
        );
        vault_cap = vault::test_destroy_keeper_cap(keeper_cap);

        let user_address = signer::address_of(user);
        strategy_coin::safe_deposit(user, strategy_coins);
        assert!(coin::balance<StrategyCoin<TestStrategy, AptosCoin>>(user_address) == amount, ERR_STRATEGY_COIN_DEPOSIT_WITHDRAW);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        keeper=@satay,
        user=@0x46
    )]
    fun test_withdraw_strategy_coin_over_balance(
        aptos_framework: &signer,
        keeper: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, keeper, user);

        strategy_coin::initialize<TestStrategy, AptosCoin>(keeper, TestStrategy {});
        let amount = 100;
        let strategy_coins = strategy_coin::mint<TestStrategy, AptosCoin>(
            amount,
            TestStrategy {}
        );

        let keeper_cap = vault::test_get_keeper_cap<TestStrategy, AptosCoin>(keeper, vault_cap, TestStrategy {});
        vault::test_deposit_strategy_coin<TestStrategy, AptosCoin>(
            &keeper_cap,
            strategy_coins,
        );
        let strategy_coins = vault::test_withdraw_strategy_coin<TestStrategy, AptosCoin>(
            &keeper_cap,
            amount + 1000,
        );
        strategy_coin::safe_deposit(user, strategy_coins);

        vault_cap = vault::test_destroy_keeper_cap(keeper_cap);

        let user_address = signer::address_of(user);
        assert!(coin::balance<StrategyCoin<TestStrategy, AptosCoin>>(user_address) == amount, ERR_STRATEGY_COIN_DEPOSIT_WITHDRAW);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        keeper=@satay,
        user=@0x46
    )]
    #[expected_failure]
    fun test_withdraw_incorrect_strategy_coin(
        aptos_framework: &signer,
        keeper: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, keeper, user);

        let user_address = signer::address_of(user);

        let keeper_cap = vault::test_get_keeper_cap<TestStrategy, AptosCoin>(keeper, vault_cap, TestStrategy {});
        let strategy_coins = vault::test_withdraw_strategy_coin<TestStrategy, AptosCoin>(
            &keeper_cap,
            100,
        );
        coin::deposit(user_address, strategy_coins);
        vault_cap = vault::test_destroy_keeper_cap(keeper_cap);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        user=@0x46
    )]
    fun test_update_strategy_properties(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, vault_manager, user);

        let new_debt_ratio = 500;
        let vault_manager_cap = vault::test_get_vault_manager_cap(vault_manager, vault_cap);
        vault::test_update_strategy_debt_ratio<TestStrategy, AptosCoin>(
            &vault_manager_cap,
            new_debt_ratio,
            &TestStrategy {}
        );
        vault_cap = vault::test_destroy_vault_manager_cap(vault_manager_cap);
        assert!(vault::debt_ratio<TestStrategy, AptosCoin>(&vault_cap) == new_debt_ratio, ERR_STRATEGY_UPDATE);
        assert!(vault::get_debt_ratio(&vault_cap) == new_debt_ratio, ERR_STRATEGY_UPDATE);

        let credit_available = new_debt_ratio * vault::total_assets<AptosCoin>(&vault_cap) / MAX_DEBT_RATIO_BPS;
        assert!(vault::credit_available<TestStrategy, AptosCoin>(&vault_cap) == credit_available, ERR_STRATEGY_UPDATE);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        user=@0x46
    )]
    #[expected_failure]
    fun test_update_strategy_debt_ratio_exceed_limit(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, vault_manager, user);

        let new_debt_ratio = MAX_DEBT_RATIO_BPS + 1;
        let vault_manager_cap = vault::test_get_vault_manager_cap(vault_manager, vault_cap);
        vault::test_update_strategy_debt_ratio<TestStrategy, AptosCoin>(
            &vault_manager_cap,
            new_debt_ratio,
            &TestStrategy {}
        );
        vault_cap = vault::test_destroy_vault_manager_cap(vault_manager_cap);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        user=@0x46
    )]
    fun test_reporting(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, vault_manager, user);

        assert!(vault::last_report<TestStrategy, AptosCoin>(&vault_cap) == timestamp::now_seconds(), ERR_REPORTING);
        timestamp::fast_forward_seconds(100);
        vault::test_report_timestamp<TestStrategy, AptosCoin>(&vault_cap, &TestStrategy {});
        assert!(vault::last_report<TestStrategy, AptosCoin>(&vault_cap) == timestamp::now_seconds(), ERR_REPORTING);

        let credit = 100;
        vault::test_update_total_debt<TestStrategy, AptosCoin>(&vault_cap, credit, 0, &TestStrategy {});
        assert!(vault::total_debt<TestStrategy, AptosCoin>(&vault_cap) == credit, ERR_REPORTING);

        vault::test_update_total_debt<TestStrategy, AptosCoin>(&vault_cap, 0, 100, &TestStrategy {});
        assert!(vault::total_debt<TestStrategy, AptosCoin>(&vault_cap) == 0, ERR_REPORTING);

        let gain_amount = 100;
        vault::test_report_gain<TestStrategy, AptosCoin>(&vault_cap, gain_amount, &TestStrategy {});
        assert!(vault::total_gain<TestStrategy, AptosCoin>(&vault_cap) == gain_amount, ERR_REPORTING);

        vault::test_update_total_debt<TestStrategy, AptosCoin>(&vault_cap, credit, 0, &TestStrategy {});

        let loss_amount = 50;
        vault::test_report_loss<TestStrategy, AptosCoin>(&vault_cap, loss_amount, &TestStrategy {});
        assert!(vault::total_loss<TestStrategy, AptosCoin>(&vault_cap) == loss_amount, ERR_REPORTING);
        assert!(vault::total_debt<TestStrategy, AptosCoin>(&vault_cap) == credit - loss_amount, ERR_REPORTING);

        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        user=@0x46
    )]
    fun test_assess_fees(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, vault_manager, user);

        let user_address = signer::address_of(user);
        let amount = 100;
        aptos_coin::mint(aptos_framework, user_address, amount);
        vault_cap = vault::test_deposit_as_user<AptosCoin>(
            user,
            vault_cap,
            coin::withdraw<AptosCoin>(user, amount)
        );

        let duration = 100;
        timestamp::fast_forward_seconds(duration);

        let total_debt = 100;
        vault::test_update_total_debt<TestStrategy, AptosCoin>(&vault_cap, total_debt, 0, &TestStrategy {});

        let gain = 60;
        aptos_coin::mint(aptos_framework, user_address, gain);
        let aptos_coin = coin::withdraw<AptosCoin>(user, gain);

        let (management_fee, performance_fee) = vault::get_fees(&vault_cap);

        let management_fee_amount = total_debt * duration * management_fee / MAX_DEBT_RATIO_BPS / SECS_PER_YEAR;
        let performance_fee_amount = gain * performance_fee / MAX_DEBT_RATIO_BPS;
        let total_fee = management_fee_amount + performance_fee_amount;
        let expected_share_token_amount = vault::calculate_vault_coin_amount_from_base_coin_amount<AptosCoin>(
            &vault_cap,
            total_fee
        );

        vault::test_assess_fees<TestStrategy, AptosCoin>(
            &aptos_coin,
            &vault_cap,
            &TestStrategy{}
        );
        coin::deposit(user_address, aptos_coin);
        let collected_fees = dao_storage::balance<VaultCoin<AptosCoin>>(vault::get_vault_addr(&vault_cap));
        assert!(expected_share_token_amount == collected_fees, ERR_ASSESS_FEES);

        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        user = @0x47
    )]
    fun test_prepare_return_profit(
        aptos_framework: &signer,
        satay: &signer,
        user: &signer,
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(
            aptos_framework,
            satay,
            user,
        );

        vault_cap = user_deposit_base_coin(aptos_framework, user, vault_cap);

        let strategy_balance = 500;
        let (profit, loss, debt_payment) = vault::test_prepare_return<TestStrategy, AptosCoin>(
            &vault_cap,
            strategy_balance,
        );

        assert!(profit == strategy_balance, ERR_PREPARE_RETURN);
        assert!(loss == 0, ERR_PREPARE_RETURN);
        assert!(debt_payment == 0, ERR_PREPARE_RETURN);

        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        user = @0x47
    )]
    fun test_prepare_return_loss(
        aptos_framework: &signer,
        satay: &signer,
        user: &signer,
    ){
        let loss_amount = 50;

        let vault_cap = setup_tests_with_vault_and_strategy(
            aptos_framework,
            satay,
            user,
        );

        vault_cap = user_deposit_base_coin(aptos_framework, user, vault_cap);

        let credit = vault::credit_available<TestStrategy, AptosCoin>(&vault_cap);
        vault::test_update_total_debt<TestStrategy, AptosCoin>(
            &vault_cap,
            credit,
            0,
            &TestStrategy {}
        );

        let strategy_balance = credit - loss_amount;
        let (profit, loss, debt_payment) = vault::test_prepare_return<TestStrategy, AptosCoin>(
            &vault_cap,
            strategy_balance,
        );
        assert!(profit == 0, ERR_PREPARE_RETURN);
        assert!(loss == loss_amount, ERR_PREPARE_RETURN);
        assert!(debt_payment == 0, ERR_PREPARE_RETURN);

        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        user = @0x47
    )]
    fun test_prepare_return_debt_payment(
        aptos_framework: &signer,
        satay: &signer,
        user: &signer,
    ){

        let vault_cap = setup_tests_with_vault_and_strategy(
            aptos_framework,
            satay,
            user,
        );

        vault_cap = user_deposit_base_coin(aptos_framework, user, vault_cap);

        let credit = vault::credit_available<TestStrategy, AptosCoin>(&vault_cap);

        let aptos = vault::test_withdraw_base_coin<TestStrategy, AptosCoin>(
            &vault_cap,
            credit,
            &TestStrategy {}
        );
        coin::deposit(signer::address_of(user), aptos);

        let vault_manager_cap = vault::test_get_vault_manager_cap(satay, vault_cap);
        vault::test_update_strategy_debt_ratio<TestStrategy, AptosCoin>(
            &vault_manager_cap,
            0,
            &TestStrategy {}
        );
        vault_cap = vault::test_destroy_vault_manager_cap(vault_manager_cap);

        let strategy_balance = credit;
        let (profit, loss, debt_payment) = vault::test_prepare_return<TestStrategy, AptosCoin>(
            &vault_cap,
            strategy_balance,
        );
        assert!(profit == 0, ERR_PREPARE_RETURN);
        assert!(loss == 0, ERR_PREPARE_RETURN);
        assert!(debt_payment == credit, ERR_PREPARE_RETURN);

        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        user = @0x47
    )]
    fun test_user_liquidation(
        aptos_framework: &signer,
        satay: &signer,
        user: &signer,
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(
            aptos_framework,
            satay,
            user,
        );

        vault_cap = user_deposit_base_coin(aptos_framework, user, vault_cap);

        let credit = vault::credit_available<TestStrategy, AptosCoin>(&vault_cap);
        let aptos = vault::test_withdraw_base_coin<TestStrategy, AptosCoin>(
            &vault_cap,
            credit,
            &TestStrategy {}
        );

        let vault_coin_balance = coin::balance<VaultCoin<AptosCoin>>(signer::address_of(user));
        let vault_coin_liquidate = vault_coin_balance * DEBT_RATIO / MAX_DEBT_RATIO_BPS;
        let vault_coins = coin::withdraw<VaultCoin<AptosCoin>>(user, vault_coin_liquidate);
        let amount_needed = vault_coin_liquidate - vault::balance<AptosCoin>(&vault_cap);

        let debt_payment = coin::extract(&mut aptos, amount_needed);

        let user_cap = vault::test_get_user_cap(user, vault_cap);
        let user_liq_lock = vault::test_get_liquidation_lock<TestStrategy, AptosCoin>(
            &user_cap,
            vault_coins
        );
        assert!(vault::get_liquidation_amount_needed(&user_liq_lock) == amount_needed, ERR_USER_LIQUIDATION);
        vault::test_user_liquidation(&user_cap, debt_payment, user_liq_lock, &TestStrategy {});
        let (vault_cap, _) = vault::test_destroy_user_cap(user_cap);
        assert!(coin::balance<AptosCoin>(signer::address_of(user)) == vault_coin_liquidate, ERR_USER_LIQUIDATION);
        assert!(vault::total_debt<TestStrategy, AptosCoin>(&vault_cap) == credit - amount_needed, ERR_USER_LIQUIDATION);

        coin::deposit(signer::address_of(user), aptos);

        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        user = @0x47
    )]
    #[expected_failure]
    fun test_user_liquidation_insufficient(
        aptos_framework: &signer,
        satay: &signer,
        user: &signer,
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(
            aptos_framework,
            satay,
            user,
        );

        vault_cap = user_deposit_base_coin(aptos_framework, user, vault_cap);

        let credit = vault::credit_available<TestStrategy, AptosCoin>(&vault_cap);
        let aptos = vault::test_withdraw_base_coin<TestStrategy, AptosCoin>(
            &vault_cap,
            credit,
            &TestStrategy {}
        );

        let vault_coin_balance = coin::balance<VaultCoin<AptosCoin>>(signer::address_of(user));
        let vault_coin_liquidate = vault_coin_balance * DEBT_RATIO / MAX_DEBT_RATIO_BPS;
        let vault_coins = coin::withdraw<VaultCoin<AptosCoin>>(user, vault_coin_liquidate);
        let amount_needed = vault_coin_liquidate - vault::balance<AptosCoin>(&vault_cap);

        let insufficient_aptos = coin::extract(&mut aptos, amount_needed - 1);
        coin::deposit(signer::address_of(user), aptos);

        let user_cap = vault::test_get_user_cap(user, vault_cap);
        let user_liq_lock = vault::test_get_liquidation_lock<TestStrategy, AptosCoin>(
            &user_cap,
            vault_coins
        );
        vault::test_user_liquidation(&user_cap, insufficient_aptos, user_liq_lock, &TestStrategy {});
        let (vault_cap, _) = vault::test_destroy_user_cap(user_cap);

        cleanup_tests(vault_cap);
    }

}