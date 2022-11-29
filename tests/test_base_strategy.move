#[test_only]
module satay::test_base_strategy {

    use std::signer;

    use aptos_framework::stake;
    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::{Self, AptosCoin};

    use satay::satay;
    use satay::base_strategy;
    use satay::coins::{Self, USDT, BTC};
    use satay::vault;

    const MAX_DEBT_RATIO_BPS: u64 = 10000;

    const MANAGEMENT_FEE: u64 = 200;
    const PERFORMANCE_FEE: u64 = 2000;
    const DEBT_RATIO: u64 = 1000;

    const DEPOSIT_AMOUNT: u64 = 1000;

    const ERR_INITIALIZE: u64 = 1;
    const ERR_DEPOSIT: u64 = 2;
    const ERR_WITHDRAW: u64 = 3;
    const ERR_PREPARE_RETURN: u64 = 4;
    const ERR_ADMIN_FUNCTIONS: u64 = 5;
    const ERR_TEND: u64 = 6;
    const ERR_HARVEST: u64 = 7;

    struct TestStrategy has drop {}

    fun setup_tests_and_create_vault(
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

        satay::new_vault<AptosCoin>(
            satay,
            b"Aptos vault",
            MANAGEMENT_FEE,
            PERFORMANCE_FEE
        );
    }

    fun user_deposit(
        aptos_framework: &signer,
        user: &signer,
        amount: u64
    ) {
        aptos_coin::mint(aptos_framework, signer::address_of(user), amount);
        satay::deposit<AptosCoin>( user, 0, amount);
    }

    fun initialize_strategy(
        satay: &signer
    ) {
        base_strategy::initialize<TestStrategy, USDT>(
            satay,
            0,
            DEBT_RATIO,
            TestStrategy {}
        );
    }

    fun setup_tests_and_create_vault_and_strategy(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer,
    ) {
        setup_tests_and_create_vault(aptos_framework, satay, coins_manager, user);
        initialize_strategy(satay);
    }

    fun setup_and_user_deposit(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer,
    ) {
        setup_tests_and_create_vault_and_strategy(
            aptos_framework,
            satay,
            coins_manager,
            user,
        );

        user_deposit(aptos_framework, user, DEPOSIT_AMOUNT);
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
        user: &signer,
    ){
        setup_tests_and_create_vault(
            aptos_framework,
            satay,
            coins_manager,
            user,
        );

        initialize_strategy(satay);

        let vault_cap = satay::open_vault(0);
        assert!(vault::has_strategy<TestStrategy>(&vault_cap), ERR_INITIALIZE);
        assert!(vault::has_coin<USDT>(&vault_cap), ERR_INITIALIZE);
        satay::close_vault(0, vault_cap);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    #[expected_failure]
    fun test_initialize_unauthorized(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer,
    ){
        setup_tests_and_create_vault(
            aptos_framework,
            satay,
            coins_manager,
            user,
        );

        base_strategy::initialize<TestStrategy, USDT>(
            user,
            0,
            DEBT_RATIO,
            TestStrategy {}
        );
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_deposit_strategy_coin(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer,
    ){
        setup_tests_and_create_vault_and_strategy(
            aptos_framework,
            satay,
            coins_manager,
            user,
        );

        let user_address = signer::address_of(user);
        let amount = 1000;
        coins::mint_coin<USDT>(coins_manager, user_address, amount);
        let usdt = coin::withdraw<USDT>(user, amount);

        let (vault_cap, stop_handle) = satay::test_lock_vault(
            0,
            TestStrategy {}
        );

        base_strategy::deposit_strategy_coin<TestStrategy, USDT>(
            &vault_cap,
            usdt,
            &stop_handle
        );
        assert!(base_strategy::balance<USDT>(&vault_cap) == amount, ERR_DEPOSIT);

        satay::test_unlock_vault(vault_cap, stop_handle);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    #[expected_failure]
    fun test_deposit_wrong_strategy_coin(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer,
    ){
        setup_tests_and_create_vault_and_strategy(
            aptos_framework,
            satay,
            coins_manager,
            user,
        );

        let user_address = signer::address_of(user);
        let amount = 1000;
        coins::mint_coin<BTC>(coins_manager, user_address, amount);
        let btc = coin::withdraw<BTC>(user, amount);

        let (vault_cap, stop_handle) = satay::test_lock_vault(
            0,
            TestStrategy {}
        );

        base_strategy::deposit_strategy_coin<TestStrategy, BTC>(
            &vault_cap,
            btc,
            &stop_handle
        );

        satay::test_unlock_vault(vault_cap, stop_handle);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_withdraw_strategy_coin(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer,
    ){
        setup_tests_and_create_vault_and_strategy(
            aptos_framework,
            satay,
            coins_manager,
            user,
        );

        let user_address = signer::address_of(user);
        let amount = 1000;
        coins::mint_coin<USDT>(coins_manager, user_address, amount);
        let usdt = coin::withdraw<USDT>(user, amount);

        let (vault_cap, stop_handle) = satay::test_lock_vault(
            0,
            TestStrategy {}
        );

        base_strategy::deposit_strategy_coin<TestStrategy, USDT>(
            &vault_cap,
            usdt,
            &stop_handle
        );
        let strategy_coins = base_strategy::withdraw_strategy_coin<TestStrategy, USDT>(
            &vault_cap,
            amount,
            &stop_handle
        );
        coin::deposit(user_address, strategy_coins);

        assert!(base_strategy::balance<USDT>(&vault_cap) == 0, ERR_WITHDRAW);
        assert!(coin::balance<USDT>(user_address) == amount, ERR_WITHDRAW);

        satay::test_unlock_vault(vault_cap, stop_handle);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    #[expected_failure]
    fun test_withdraw_wrong_strategy_coin(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer,
    ){
        setup_tests_and_create_vault_and_strategy(
            aptos_framework,
            satay,
            coins_manager,
            user,
        );

        let user_address = signer::address_of(user);
        let amount = 1000;
        coins::mint_coin<USDT>(coins_manager, user_address, amount);
        let usdt = coin::withdraw<USDT>(user, amount);

        let (vault_cap, stop_handle) = satay::test_lock_vault(
            0,
            TestStrategy {}
        );

        base_strategy::deposit_strategy_coin<TestStrategy, USDT>(
            &vault_cap,
            usdt,
            &stop_handle
        );
        let strategy_coins = base_strategy::withdraw_strategy_coin<TestStrategy, BTC>(
            &vault_cap,
            amount,
            &stop_handle
        );
        coin::deposit(user_address, strategy_coins);

        satay::test_unlock_vault(vault_cap, stop_handle);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_admin_functions(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer,
    ) {
        setup_tests_and_create_vault_and_strategy(
            aptos_framework,
            satay,
            coins_manager,
            user,
        );

        let debt_ratio = 100;
        base_strategy::update_debt_ratio<TestStrategy, AptosCoin>(
            satay,
            0,
            debt_ratio,
            TestStrategy {}
        );

        let credit_threshold = 200;
        base_strategy::update_credit_threshold<TestStrategy, AptosCoin>(
            satay,
            0,
            credit_threshold,
            TestStrategy {}
        );

        base_strategy::set_force_harvest_trigger_once<TestStrategy, AptosCoin>(
            satay,
            0,
            TestStrategy {}
        );

        let max_report_delay = 300;
        base_strategy::update_max_report_delay<TestStrategy, AptosCoin>(
            satay,
            0,
            max_report_delay,
            TestStrategy {}
        );

        let vault_cap = satay::open_vault(0);

        assert!(vault::credit_threshold<TestStrategy>(&vault_cap) == credit_threshold, ERR_ADMIN_FUNCTIONS);
        assert!(vault::debt_ratio<TestStrategy>(&vault_cap) == debt_ratio, ERR_ADMIN_FUNCTIONS);
        assert!(vault::force_harvest_trigger_once<TestStrategy>(&vault_cap), ERR_ADMIN_FUNCTIONS);
        assert!(vault::max_report_delay<TestStrategy>(&vault_cap) == max_report_delay, ERR_ADMIN_FUNCTIONS);

        satay::close_vault(0, vault_cap);
    }

    fun apply_position(
        coins_manager: &signer,
        user: &signer,
        aptos_coins: Coin<AptosCoin>
    ): Coin<USDT> {
        let amount = coin::value(&aptos_coins);
        let user_address = signer::address_of(user);
        coin::deposit<AptosCoin>(user_address, aptos_coins);
        coins::mint_coin<USDT>(coins_manager, user_address, amount);
        coin::withdraw<USDT>(user, amount)
    }

    fun liquidate_position(
        aptos_framework: &signer,
        user: &signer,
        usdt_coins: Coin<USDT>
    ): Coin<AptosCoin> {
        let amount = coin::value(&usdt_coins);
        let user_address = signer::address_of(user);
        coin::deposit<USDT>(user_address, usdt_coins);
        aptos_coin::mint(aptos_framework, user_address, amount);
        coin::withdraw<AptosCoin>(user, amount)
    }

    fun harvest(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer,
    ){
        let (vault_cap, vault_cap_lock) = base_strategy::open_vault_for_harvest<TestStrategy, AptosCoin>(
            satay,
            0,
            TestStrategy {}
        );

        let (to_apply, harvest_lock) = base_strategy::process_harvest<TestStrategy, AptosCoin, USDT>(
            &vault_cap,
            0,
            vault_cap_lock
        );

        let debt_payment = base_strategy::harvest_debt_payment(&harvest_lock);
        let profit = base_strategy::harvest_profit(&harvest_lock);

        let strategy_coins_to_liquidate = coin::withdraw<USDT>(user, debt_payment + profit);
        let liquidated_coins = liquidate_position(aptos_framework, user, strategy_coins_to_liquidate);
        let debt_payment = coin::extract<AptosCoin>(&mut liquidated_coins, debt_payment);
        let profit = coin::extract<AptosCoin>(&mut liquidated_coins, profit);
        coin::destroy_zero(liquidated_coins);

        let usdt = apply_position(coins_manager, user, to_apply);

        base_strategy::close_vault_for_harvest<TestStrategy, AptosCoin, USDT>(
            vault_cap,
            harvest_lock,
            debt_payment,
            profit,
            usdt
        );
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_harvest(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer,
    ) {
        setup_and_user_deposit(
            aptos_framework,
            satay,
            coins_manager,
            user,
        );

        let vault_cap = satay::open_vault(0);
        let credit_available = vault::credit_available<TestStrategy, AptosCoin>(
            &vault_cap,
        );
        assert!(credit_available == DEPOSIT_AMOUNT * DEBT_RATIO / MAX_DEBT_RATIO_BPS, ERR_HARVEST);
        satay::close_vault(0, vault_cap);

        harvest(aptos_framework, satay, coins_manager, user);

        let vault_cap = satay::open_vault(0);
        let strategy_coins = base_strategy::balance<USDT>(
            &vault_cap,
        );
        satay::close_vault(0, vault_cap);

        assert!(strategy_coins == credit_available, ERR_HARVEST);

    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_tend(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer,
    ) {
        setup_tests_and_create_vault_and_strategy(
            aptos_framework,
            satay,
            coins_manager,
            user,
        );

        let user_address = signer::address_of(user);
        let amount = 1000;
        coins::mint_coin<USDT>(coins_manager, user_address, amount);

        let (
            vault_cap,
            tend_lock
        ) = base_strategy::open_vault_for_tend<TestStrategy, AptosCoin>(
            satay,
            0,
            TestStrategy {},
        );

        let usdt = coin::withdraw<USDT>(user, amount);

        base_strategy::close_vault_for_tend<TestStrategy, USDT>(
            vault_cap,
            tend_lock,
            usdt
        );

        let vault_cap = satay::open_vault(0);
        assert!(base_strategy::balance<USDT>(&vault_cap) == amount, ERR_TEND);
        satay::close_vault(0, vault_cap);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_user_withdraw(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer,
    ) {
        setup_and_user_deposit(
            aptos_framework,
            satay,
            coins_manager,
            user,
        );

        harvest(aptos_framework, satay, coins_manager, user);

        let (
            vault_cap,
            user_withdraw_lock
        ) = base_strategy::open_vault_for_user_withdraw<TestStrategy, AptosCoin, USDT>(
            user,
            0,
            vault::vault_coin_balance<AptosCoin>(signer::address_of(user)),
            TestStrategy {}
        );

        let usdt = base_strategy::withdraw_strategy_coin<TestStrategy, USDT>(
            &vault_cap,
            base_strategy::user_withdraw_amount_needed(&user_withdraw_lock),
            base_strategy::user_withdraw_vault_cap_lock(&user_withdraw_lock)
        );
        let aptos_coins = liquidate_position(aptos_framework, user, usdt);

        base_strategy::close_vault_for_user_withdraw(
            vault_cap,
            user_withdraw_lock,
            aptos_coins
        )
    }

    fun setup_prepare_return_tests(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer,
        deposit_amount: u64,
    ) {
        setup_tests_and_create_vault_and_strategy(
            aptos_framework,
            satay,
            coins_manager,
            user,
        );

        user_deposit(aptos_framework, user, deposit_amount);

    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_prepare_return_profit(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer,
    ){
        let deposit_amount = 1000;
        setup_prepare_return_tests(
            aptos_framework,
            satay,
            coins_manager,
            user,
            deposit_amount
        );

        let (vault_cap, stop_handle) = satay::test_lock_vault(
            0,
            TestStrategy {}
        );

        let strategy_balance = 500;
        let (profit, loss, debt_payment) = base_strategy::test_prepare_return<TestStrategy, AptosCoin>(
            &vault_cap,
            strategy_balance,
        );

        assert!(profit == strategy_balance, ERR_PREPARE_RETURN);
        assert!(loss == 0, ERR_PREPARE_RETURN);
        assert!(debt_payment == 0, ERR_PREPARE_RETURN);

        satay::test_unlock_vault(vault_cap, stop_handle);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_prepare_return_loss(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer,
    ){
        let deposit_amount = 1000;
        let loss_amount = 50;

        setup_prepare_return_tests(
            aptos_framework,
            satay,
            coins_manager,
            user,
            deposit_amount
        );

        let (vault_cap, stop_handle) = satay::test_lock_vault(
            0,
            TestStrategy {}
        );

        let credit = vault::credit_available<TestStrategy, AptosCoin>(&vault_cap);
        vault::test_update_total_debt<TestStrategy>(
            &vault_cap,
            credit,
            0,
            &TestStrategy {}
        );

        let strategy_balance = credit - loss_amount;
        let (profit, loss, debt_payment) = base_strategy::test_prepare_return<TestStrategy, AptosCoin>(
            &vault_cap,
            strategy_balance,
        );
        assert!(profit == 0, ERR_PREPARE_RETURN);
        assert!(loss == loss_amount, ERR_PREPARE_RETURN);
        assert!(debt_payment == 0, ERR_PREPARE_RETURN);

        satay::test_unlock_vault(vault_cap, stop_handle);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_prepare_return_debt_payment(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer,
    ){
        let deposit_amount = 1000;

        setup_prepare_return_tests(
            aptos_framework,
            satay,
            coins_manager,
            user,
            deposit_amount
        );

        let (vault_cap, stop_handle) = satay::test_lock_vault(
            0,
            TestStrategy {}
        );

        let credit = vault::credit_available<TestStrategy, AptosCoin>(&vault_cap);

        let aptos = vault::test_withdraw_base_coin<TestStrategy, AptosCoin>(
            &vault_cap,
            credit,
            &TestStrategy {}
        );
        coin::deposit(@aptos_framework, aptos);

        vault::test_update_strategy_debt_ratio<TestStrategy>(
            &vault_cap,
            0,
            &TestStrategy {}
        );

        let strategy_balance = credit;
        let (profit, loss, debt_payment) = base_strategy::test_prepare_return<TestStrategy, AptosCoin>(
            &vault_cap,
            strategy_balance,
        );
        assert!(profit == 0, ERR_PREPARE_RETURN);
        assert!(loss == 0, ERR_PREPARE_RETURN);
        assert!(debt_payment == credit, ERR_PREPARE_RETURN);

        satay::test_unlock_vault(vault_cap, stop_handle);
    }

}
