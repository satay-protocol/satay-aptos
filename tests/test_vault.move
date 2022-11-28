#[test_only]
module satay::test_vault {

    use std::signer;

    use aptos_std::type_info;

    use aptos_framework::coin;
    use aptos_framework::account;
    use aptos_framework::stake;
    use aptos_framework::aptos_coin::{Self, AptosCoin};

    use satay::vault::{Self, VaultCapability, get_strategy_coin_type, VaultCoin};
    use satay::coins::{Self, USDT};
    use aptos_framework::timestamp;
    use satay::math;
    use satay::dao_storage;

    struct TestStrategy has drop {}

    const MAX_DEBT_RATIO_BPS: u64 = 10000;
    const SECS_PER_YEAR: u64 = 31556952; // 365.2425 days

    const DEFAULT_MAX_REPORT_DELAY: u64 = 30 * 24 * 3600; // 30 days
    const DEFAULT_CREDIT_THRESHOLD: u64 = 10000; // 10,000

    const MANAGEMENT_FEE: u64 = 200;
    const PERFORMANCE_FEE: u64 = 2000;
    const DEBT_RATIO: u64 = 1000;

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

    #[test_only]
    fun setup_tests(
        aptos_framework: &signer,
        user: &signer,
    ) {
        stake::initialize_for_test(aptos_framework);
        account::create_account_for_test(signer::address_of(user));
        coin::register<AptosCoin>(user);
    }

    #[test_only]
    fun create_vault(
        vault_manager: &signer,
    ): VaultCapability {
        vault::new_test<AptosCoin>(
            vault_manager,
            b"test_vault",
            0,
            MANAGEMENT_FEE,
            PERFORMANCE_FEE
        )
    }

    #[test_only]
    fun setup_tests_with_vault(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer,
    ): VaultCapability {
        setup_tests(aptos_framework, user);
        create_vault(vault_manager)
    }

    #[test_only]
    fun approve_strategy(
        vault_cap: &VaultCapability,
    ) {
        vault::test_approve_strategy<TestStrategy, USDT>(
            vault_cap,
            DEBT_RATIO,
        )
    }

    fun setup_tests_with_vault_and_strategy(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer,
    ): VaultCapability {
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, user);
        approve_strategy(&vault_cap);
        vault_cap
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
        setup_tests(aptos_framework, user);
        let vault_cap = create_vault(vault_manager);

        assert!(vault::get_base_coin_type(&vault_cap) == type_info::type_of<AptosCoin>(), ERR_CREATE_VAULT);
        assert!(vault::get_base_coin_decimals(&vault_cap) == coin::decimals<AptosCoin>(), ERR_CREATE_VAULT);
        let (management_fee, performance_fee) = vault::get_fees(&vault_cap);
        assert!(management_fee == MANAGEMENT_FEE, ERR_CREATE_VAULT);
        assert!(performance_fee == PERFORMANCE_FEE, ERR_CREATE_VAULT);
        assert!(vault::get_debt_ratio(&vault_cap) == 0, ERR_CREATE_VAULT);
        assert!(vault::get_total_debt(&vault_cap) == 0, ERR_CREATE_VAULT);

        assert!(vault::has_coin<AptosCoin>(&vault_cap), 0);
        assert!(vault::balance<AptosCoin>(&vault_cap) == 0, 0);

        assert!(vault::vault_cap_has_id(&vault_cap, 0), 0);
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
        vault::test_update_fee(&vault_cap, management_fee, performance_fee);
        let (management_fee_val, performance_fee_val) = vault::get_fees(&vault_cap);
        assert!(management_fee_val == management_fee, ERR_FEES);
        assert!(performance_fee_val == performance_fee, ERR_FEES);
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
        let management_fee = 5001;
        let performance_fee = 0;
        vault::test_update_fee(&vault_cap, management_fee, performance_fee);
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
        let management_fee = 0;
        let performance_fee = 5001;
        vault::test_update_fee(&vault_cap, management_fee, performance_fee);
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
        vault::test_deposit_as_user<AptosCoin>(
            user,
            &vault_cap,
            coin::withdraw<AptosCoin>(user, amount)
        );

        assert!(vault::balance<AptosCoin>(&vault_cap) == amount, ERR_DEPOIST_WITHDRAW_AS_USER);
        assert!(vault::is_vault_coin_registered<AptosCoin>(user_address), ERR_DEPOIST_WITHDRAW_AS_USER);
        assert!(vault::vault_coin_balance<AptosCoin>(user_address) == amount, ERR_DEPOIST_WITHDRAW_AS_USER);
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

        vault::test_deposit_as_user<USDT>(
            user,
            &vault_cap,
            coin::withdraw<USDT>(user, amount)
        );
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
        vault::test_deposit_as_user<AptosCoin>(
            user,
            &vault_cap,
            coin::withdraw<AptosCoin>(user, amount)
        );
        let base_coins = vault::test_withdraw_as_user<AptosCoin>(
            user,
            &vault_cap,
            amount
        );
        coin::deposit<AptosCoin>(user_address, base_coins);
        assert!(vault::vault_coin_balance<AptosCoin>(user_address) == 0, ERR_DEPOIST_WITHDRAW_AS_USER);
        assert!(coin::balance<AptosCoin>(user_address) == amount, ERR_DEPOIST_WITHDRAW_AS_USER);
        assert!(vault::balance<AptosCoin>(&vault_cap) == 0, ERR_DEPOIST_WITHDRAW_AS_USER);
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
        vault::test_deposit_as_user<AptosCoin>(
            user,
            &vault_cap,
            coin::withdraw<AptosCoin>(user, amount)
        );
        let base_coins = vault::test_withdraw_as_user<USDT>(
            user,
            &vault_cap,
            amount
        );
        coin::deposit<USDT>(user_address, base_coins);
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
        vault::test_deposit_as_user<AptosCoin>(
            user,
            &vault_cap,
            coin::withdraw<AptosCoin>(user, amount)
        );
        let base_coins = vault::test_withdraw_as_user<AptosCoin>(
            user,
            &vault_cap,
            amount + 1
        );
        coin::deposit<AptosCoin>(user_address, base_coins);
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
        vault::test_deposit_as_user<AptosCoin>(
            user, &vault_cap,
            coin::withdraw<AptosCoin>(user, amount / 2)
        );
        vault::test_deposit<AptosCoin>(
            &vault_cap,
            coin::withdraw<AptosCoin>(user, amount / 2)
        );

        assert!(vault::vault_coin_balance<AptosCoin>(user_address) == amount / 2, ERR_DEPOIST_WITHDRAW_AS_USER);

        let base_coins = vault::test_withdraw_as_user<AptosCoin>(user, &vault_cap, amount / 2);
        coin::deposit<AptosCoin>(user_address, base_coins);

        assert!(vault::vault_coin_balance<AptosCoin>(user_address) == 0, ERR_DEPOIST_WITHDRAW_AS_USER);
        assert!(coin::balance<AptosCoin>(user_address) == amount, ERR_DEPOIST_WITHDRAW_AS_USER);
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
        vault::test_deposit_as_user<AptosCoin>(
            user_a,
            &vault_cap,
            coin::withdraw<AptosCoin>(user_a, user_a_deposit_amount)
        );
        assert!(vault::vault_coin_balance<AptosCoin>(user_a_address) == user_a_deposit_amount, ERR_INCORRECT_VAULT_COIN_AMOUNT);

        // userB deposit 1000 coins
        // @dev: userB should get 10x token than userA
        let user_b_amount = 1000;
        let user_b_deposit_amount = 1000;
        aptos_coin::mint(aptos_framework, user_b_address, user_b_amount);
        vault::test_deposit_as_user<AptosCoin>(
            user_b,
            &vault_cap,
            coin::withdraw<AptosCoin>(
                user_b,
                user_b_deposit_amount
            ));
        assert!(vault::vault_coin_balance<AptosCoin>(user_b_address) == user_b_deposit_amount, ERR_INCORRECT_VAULT_COIN_AMOUNT);

        // userA deposit 400 coins
        // userA should have 500 shares in total
        let user_a_second_deposit_amount = 400;
        vault::test_deposit_as_user<AptosCoin>(
            user_a,
            &vault_cap,
            coin::withdraw<AptosCoin>(user_a, user_a_second_deposit_amount)
        );
        let user_a_total_deposits = user_a_deposit_amount + user_a_second_deposit_amount;
        assert!(coin::balance<vault::VaultCoin<AptosCoin>>(user_a_address) == user_a_total_deposits, ERR_INCORRECT_VAULT_COIN_AMOUNT);

        let farm_amount = 300;
        vault::test_deposit(&vault_cap, coin::withdraw<AptosCoin>(user_a, farm_amount));
        // userA withdraw 500 shares
        // userA should withdraw (1500 + 300) * 500 / 1500
        let total_deposits = user_a_total_deposits + user_b_deposit_amount + farm_amount;
        let user_a_withdraw_amount = user_a_total_deposits;
        let coins = vault::test_withdraw_as_user<AptosCoin>(
            user_a,
            &vault_cap,
            user_a_withdraw_amount
        );
        let withdraw_amount = coin::value(&coins);
        coin::deposit<AptosCoin>(user_a_address, coins);
        let expected_withdraw_amount = (total_deposits + farm_amount) / total_deposits * withdraw_amount;
        assert!(withdraw_amount == expected_withdraw_amount, ERR_INCORRECT_VAULT_COIN_AMOUNT);
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

        approve_strategy(&vault_cap);

        let user_address = signer::address_of(user);
        let amount = 100;

        aptos_coin::mint(aptos_framework, user_address, amount);
        vault::test_deposit<AptosCoin>(&vault_cap, coin::withdraw<AptosCoin>(user, amount));

        assert!(vault::has_strategy<TestStrategy>(&vault_cap), ERR_STRATEGY);
        assert!(vault::debt_ratio<TestStrategy>(&vault_cap) == DEBT_RATIO, ERR_STRATEGY);
        assert!(vault::credit_available<TestStrategy, AptosCoin>(&vault_cap) == amount * DEBT_RATIO / MAX_DEBT_RATIO_BPS, ERR_STRATEGY);
        assert!(vault::debt_out_standing<TestStrategy, AptosCoin>(&vault_cap) == 0, ERR_STRATEGY);
        assert!(vault::total_debt<TestStrategy>(&vault_cap) == 0, ERR_STRATEGY);
        assert!(vault::last_report<TestStrategy>(&vault_cap) == timestamp::now_seconds(), ERR_STRATEGY);
        assert!(vault::max_report_delay<TestStrategy>(&vault_cap) == DEFAULT_MAX_REPORT_DELAY, ERR_STRATEGY);
        let expected_credit_threshold = DEFAULT_CREDIT_THRESHOLD * math::pow_10(coin::decimals<AptosCoin>());
        assert!(vault::credit_threshold<TestStrategy>(&vault_cap) == expected_credit_threshold, ERR_STRATEGY);
        assert!(!vault::force_harvest_trigger_once<TestStrategy>(&vault_cap), ERR_STRATEGY);
        assert!(get_strategy_coin_type<TestStrategy>(&vault_cap) == type_info::type_of<USDT>(), ERR_STRATEGY);
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

        let withdraw_amount = amount * DEBT_RATIO / MAX_DEBT_RATIO_BPS;
        let base_coins = vault::test_withdraw_base_coin<TestStrategy, AptosCoin>(
            &vault_cap,
            withdraw_amount,
            &TestStrategy {}
        );
        coin::deposit(user_address, base_coins);
        assert!(coin::balance<AptosCoin>(user_address) == withdraw_amount, ERR_STRATEGY_BASE_COIN_DEPOSIT_WITHDRAW);
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
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        token_admin=@satay,
        user=@0x46
    )]
    fun test_deposit_strategy_coin(
        aptos_framework: &signer,
        vault_manager: &signer,
        token_admin: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, vault_manager, user);

        coins::register_coin<USDT>(token_admin);

        let user_address = signer::address_of(user);
        let amount = 100;
        coin::register<USDT>(user);
        coins::mint_coin<USDT>(token_admin, user_address, amount);
        let strategy_coins = coin::withdraw<USDT>(user, amount);

        vault::test_deposit_strategy_coin<TestStrategy, USDT>(
            &vault_cap,
            strategy_coins,
            &TestStrategy {}
        );
        assert!(vault::balance<USDT>(&vault_cap) == amount, ERR_STRATEGY_COIN_DEPOSIT_WITHDRAW);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        user=@0x46
    )]
    #[expected_failure]
    fun test_deposit_incorrect_strategy_coin(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, vault_manager, user);

        let user_address = signer::address_of(user);
        let amount = 100;
        aptos_coin::mint(aptos_framework, user_address, amount);
        let incorrect_strategy_coin = coin::withdraw<AptosCoin>(user, amount);

        vault::test_deposit_strategy_coin<TestStrategy, AptosCoin>(
            &vault_cap,
            incorrect_strategy_coin,
            &TestStrategy {}
        );
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        token_admin=@satay,
        user=@0x46
    )]
    fun test_withdraw_strategy_coin(
        aptos_framework: &signer,
        vault_manager: &signer,
        token_admin: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, vault_manager, user);

        coins::register_coin<USDT>(token_admin);

        let user_address = signer::address_of(user);
        let amount = 100;
        coin::register<USDT>(user);
        coins::mint_coin<USDT>(token_admin, user_address, amount);
        let strategy_coins = coin::withdraw<USDT>(user, amount);

        vault::test_deposit_strategy_coin<TestStrategy, USDT>(
            &vault_cap,
            strategy_coins,
            &TestStrategy {}
        );
        let strategy_coins = vault::test_withdraw_strategy_coin<TestStrategy, USDT>(
            &vault_cap,
            amount,
            &TestStrategy {}
        );
        coin::deposit(user_address, strategy_coins);
        assert!(coin::balance<USDT>(user_address) == amount, ERR_STRATEGY_COIN_DEPOSIT_WITHDRAW);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        token_admin=@satay,
        user=@0x46
    )]
    fun test_withdraw_strategy_coin_over_balance(
        aptos_framework: &signer,
        vault_manager: &signer,
        token_admin: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, vault_manager, user);

        coins::register_coin<USDT>(token_admin);

        let user_address = signer::address_of(user);
        let amount = 100;
        coin::register<USDT>(user);
        coins::mint_coin<USDT>(token_admin, user_address, amount);
        let strategy_coins = coin::withdraw<USDT>(user, amount);

        vault::test_deposit_strategy_coin<TestStrategy, USDT>(
            &vault_cap,
            strategy_coins,
            &TestStrategy {}
        );
        let strategy_coins = vault::test_withdraw_strategy_coin<TestStrategy, USDT>(
            &vault_cap,
            amount + 1000,
            &TestStrategy {}
        );
        coin::deposit(user_address, strategy_coins);
        assert!(coin::balance<USDT>(user_address) == amount, ERR_STRATEGY_COIN_DEPOSIT_WITHDRAW);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        user=@0x46
    )]
    #[expected_failure]
    fun test_withdraw_incorrect_strategy_coin(
        aptos_framework: &signer,
        vault_manager: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, vault_manager, user);

        let user_address = signer::address_of(user);

        let strategy_coins = vault::test_withdraw_strategy_coin<TestStrategy, AptosCoin>(
            &vault_cap,
            100,
            &TestStrategy {}
        );
        coin::deposit(user_address, strategy_coins);
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
        vault::test_update_strategy_debt_ratio<TestStrategy>(&vault_cap, new_debt_ratio);
        assert!(vault::debt_ratio<TestStrategy>(&vault_cap) == new_debt_ratio, ERR_STRATEGY_UPDATE);
        assert!(vault::get_debt_ratio(&vault_cap) == new_debt_ratio, ERR_STRATEGY_UPDATE);
        let credit_available = new_debt_ratio * vault::total_assets<AptosCoin>(&vault_cap) / MAX_DEBT_RATIO_BPS;
        assert!(vault::credit_available<TestStrategy, AptosCoin>(&vault_cap) == credit_available, ERR_STRATEGY_UPDATE);

        let new_max_report_delay = 100;
        vault::test_update_strategy_max_report_delay<TestStrategy>(&vault_cap, new_max_report_delay);
        assert!(vault::max_report_delay<TestStrategy>(&vault_cap) == new_max_report_delay, ERR_STRATEGY_UPDATE);

        let new_credit_threshold = 100;
        vault::test_update_strategy_credit_threshold<TestStrategy>(&vault_cap, new_credit_threshold);
        assert!(vault::credit_threshold<TestStrategy>(&vault_cap) == new_credit_threshold, ERR_STRATEGY_UPDATE);

        vault::test_set_force_harvest_trigger_once<TestStrategy>(&vault_cap);
        assert!(vault::force_harvest_trigger_once<TestStrategy>(&vault_cap), ERR_STRATEGY_UPDATE);
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
        vault::test_update_strategy_debt_ratio<TestStrategy>(&vault_cap, new_debt_ratio);
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

        assert!(vault::last_report<TestStrategy>(&vault_cap) == timestamp::now_seconds(), ERR_REPORTING);
        timestamp::fast_forward_seconds(100);
        vault::test_report_timestamp<TestStrategy>(&vault_cap);
        assert!(vault::last_report<TestStrategy>(&vault_cap) == timestamp::now_seconds(), ERR_REPORTING);

        let credit = 100;
        vault::test_update_total_debt(&vault_cap, credit, 0, &TestStrategy {});
        assert!(vault::total_debt<TestStrategy>(&vault_cap) == credit, ERR_REPORTING);

        vault::test_update_total_debt(&vault_cap, 0, 100, &TestStrategy {});
        assert!(vault::total_debt<TestStrategy>(&vault_cap) == 0, ERR_REPORTING);

        let gain_amount = 100;
        vault::test_report_gain<TestStrategy>(&vault_cap, gain_amount);
        assert!(vault::total_gain<TestStrategy>(&vault_cap) == gain_amount, ERR_REPORTING);

        vault::test_update_total_debt(&vault_cap, credit, 0, &TestStrategy {});

        let loss_amount = 50;
        vault::test_report_loss<TestStrategy>(&vault_cap, loss_amount);
        assert!(vault::total_loss<TestStrategy>(&vault_cap) == loss_amount, ERR_REPORTING);


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
        vault::test_deposit_as_user<AptosCoin>(
            user,
            &vault_cap,
            coin::withdraw<AptosCoin>(user, amount)
        );

        let duration = 100;
        timestamp::fast_forward_seconds(duration);

        let total_debt = 100;
        vault::test_update_total_debt<TestStrategy>(&vault_cap, total_debt, 0, &TestStrategy {});

        let gain = 60;

        let (management_fee, performance_fee) = vault::get_fees(&vault_cap);

        let management_fee_amount = total_debt * duration * management_fee / MAX_DEBT_RATIO_BPS / SECS_PER_YEAR;
        let performance_fee_amount = gain * performance_fee / MAX_DEBT_RATIO_BPS;
        let total_fee = management_fee_amount + performance_fee_amount;
        let expected_share_token_amount = vault::calculate_share_amount_from_base_coin_amount<AptosCoin>(
            &vault_cap,
            total_fee
        );

        vault::test_assess_fees<TestStrategy, AptosCoin>(gain, 0, &vault_cap, &TestStrategy{});
        let collected_fees = dao_storage::balance<VaultCoin<AptosCoin>>(vault::get_vault_addr(&vault_cap));
        assert!(expected_share_token_amount == collected_fees, ERR_ASSESS_FEES);
    }
}