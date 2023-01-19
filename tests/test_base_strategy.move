#[test_only]
module satay::test_base_strategy {

    use std::signer;

    use aptos_framework::stake;
    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::{Self, AptosCoin};

    use satay_vault_coin::vault_coin::VaultCoin;
    use satay::vault_coin_account;

    use satay::satay;
    use satay::base_strategy;
    use satay::coins::{Self, USDT, BTC};
    use satay::vault;
    use aptos_framework::timestamp;
    use satay::dao_storage;

    const MAX_DEBT_RATIO_BPS: u64 = 10000;
    const SECS_PER_YEAR: u64 = 31556952; // 365.2425 days

    const MANAGEMENT_FEE: u64 = 200;
    const PERFORMANCE_FEE: u64 = 2000;
    const DEBT_RATIO: u64 = 1000;

    const DEPOSIT_AMOUNT: u64 = 1000;
    const TEND_AMOUNT: u64 = 200;

    const ERR_INITIALIZE: u64 = 1;
    const ERR_DEPOSIT: u64 = 2;
    const ERR_WITHDRAW: u64 = 3;
    const ERR_PREPARE_RETURN: u64 = 4;
    const ERR_ADMIN_FUNCTIONS: u64 = 5;
    const ERR_TEND: u64 = 6;
    const ERR_HARVEST: u64 = 7;
    const ERR_USER_WITHDRAW: u64 = 8;
    const ERR_PROCESS_HARVEST: u64 = 9;

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
        vault_coin_account::initialize_satay_account(
            satay,
            x"0e53617461795661756c74436f696e020000000000000000404442334638364131454231354432454538373446303132424334384439373142373336344135453630354646303432353235434633383145383930333445334587021f8b08000000000002ff2d90cd6ec3201084ef3c45e44b4eb621fea5524f3df714a997c8b216583b28365880dde6ed0b6d6e3b3bb3f3497bdb403e60c6811858f1f47e3a5f21c0f30bf6257c586dcee440e7b535c962052de899ecdbec40e1b8d945cb673432bdae7b00b16046c80d9472e83dfa81f8d4351ea96c94b12d65e90f6d8077bc6f812b5a3159376d87ac111def0436ace58cca498a9a356dc52e757fc149b6c0b8a45051c9eb3e41141eb9c20d8d422335fae2d31e780d6ad16220b30e89740f61f36f6519e57d1785b46b095bb03e5f40f8d728adc3220632e2f048472b6863306abf0ba55d5afd27d708282717bff46ddda34c32f77fc0ec173b2d8c9145010000010a7661756c745f636f696e5d1f8b08000000000002ff45c8310a80300c40d13da7c8398a38e81d5c4ba80585b6119308527a77dbc93f7d5ee6dd524421a5d73f64497de0b338f73f56c09ee86d41711bbe769eae838a72c685240e98b13668f00109fb6b9d5200000000000000",
            x"a11ceb0b05000000050100020202060708210829200a490500000001000100010a7661756c745f636f696e095661756c74436f696e0b64756d6d795f6669656c6405a97986a9d031c4567e15b797be516910cfcb4156312482efc6a19c0a30c948000201020100"
        );
        satay::initialize(satay);
        coins::register_coins(coins_manager);

        account::create_account_for_test(signer::address_of(user));
        coin::register<AptosCoin>(user);
        coin::register<USDT>(user);
        account::create_account_for_test(signer::address_of(coins_manager));
        coin::register<AptosCoin>(coins_manager);
        coin::register<USDT>(coins_manager);

        satay::new_vault<AptosCoin>(
            satay,
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
            &TestStrategy {}
        );

        let keeper_cap = vault::test_get_keeper_cap<TestStrategy>(
            satay,
            vault_cap,
            TestStrategy {}
        );

        base_strategy::deposit_strategy_coin<TestStrategy, USDT>(
            &keeper_cap,
            usdt,
        );
        assert!(base_strategy::harvest_balance<TestStrategy, USDT>(&keeper_cap) == amount, ERR_DEPOSIT);

        vault_cap = vault::test_destroy_keeper_cap(keeper_cap);

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
            &TestStrategy {}
        );

        let keeper_cap = vault::test_get_keeper_cap<TestStrategy>(
            satay,
            vault_cap,
            TestStrategy {}
        );

        base_strategy::deposit_strategy_coin<TestStrategy, BTC>(
            &keeper_cap,
            btc,
        );

        vault_cap = vault::test_destroy_keeper_cap(keeper_cap);

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
            &TestStrategy {}
        );

        let keeper_cap = vault::test_get_keeper_cap<TestStrategy>(
            satay,
            vault_cap,
            TestStrategy {}
        );

        base_strategy::deposit_strategy_coin<TestStrategy, USDT>(
            &keeper_cap,
            usdt,
        );
        let strategy_coins = base_strategy::withdraw_strategy_coin<TestStrategy, USDT>(
            &keeper_cap,
            amount,
        );
        coin::deposit(user_address, strategy_coins);

        assert!(base_strategy::harvest_balance<TestStrategy, USDT>(&keeper_cap) == 0, ERR_WITHDRAW);
        assert!(coin::balance<USDT>(user_address) == amount, ERR_WITHDRAW);

        vault_cap = vault::test_destroy_keeper_cap(keeper_cap);

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
            &TestStrategy {}
        );

        let keeper_cap = vault::test_get_keeper_cap<TestStrategy>(
            satay,
            vault_cap,
            TestStrategy {}
        );

        base_strategy::deposit_strategy_coin<TestStrategy, USDT>(
            &keeper_cap,
            usdt,
        );
        let strategy_coins = base_strategy::withdraw_strategy_coin<TestStrategy, BTC>(
            &keeper_cap,
            amount,
        );
        coin::deposit(user_address, strategy_coins);

        vault_cap = vault::test_destroy_keeper_cap(keeper_cap);

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
        base_strategy::update_debt_ratio<TestStrategy>(
            satay,
            0,
            debt_ratio,
            TestStrategy {}
        );

        let vault_cap = satay::open_vault(0);

        assert!(vault::debt_ratio<TestStrategy>(&vault_cap) == debt_ratio, ERR_ADMIN_FUNCTIONS);

        satay::close_vault(0, vault_cap);
    }

    fun apply_position(
        coins_manager: &signer,
        strategy: &signer,
        aptos_coins: Coin<AptosCoin>
    ): Coin<USDT> {
        let amount = coin::value(&aptos_coins);
        let strategy_address = signer::address_of(strategy);
        coin::deposit<AptosCoin>(strategy_address, aptos_coins);
        coins::mint_coin<USDT>(coins_manager, strategy_address, amount);
        coin::withdraw<USDT>(strategy, amount)
    }

    fun liquidate_position(
        aptos_framework: &signer,
        strategy: &signer,
        usdt_coins: Coin<USDT>
    ): Coin<AptosCoin> {
        let amount = coin::value(&usdt_coins);
        let strategy_address = signer::address_of(strategy);
        coin::deposit<USDT>(strategy_address, usdt_coins);
        aptos_coin::mint(aptos_framework, strategy_address, amount);
        coin::withdraw<AptosCoin>(strategy, amount)
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_process_harvest_credit(
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

        let (keeper_cap, vault_cap_lock) = base_strategy::open_vault_for_harvest<TestStrategy, AptosCoin>(
            satay,
            0,
            TestStrategy {}
        );

        let strategy_balance = 0;
        let credit_available = vault::keeper_credit_available<TestStrategy, AptosCoin>(&keeper_cap);

        let (to_apply, harvest_lock) = base_strategy::process_harvest<TestStrategy, AptosCoin, USDT>(
            &keeper_cap,
            strategy_balance,
            vault_cap_lock
        );

        let debt_payment = base_strategy::get_harvest_debt_payment(&harvest_lock);
        let profit = base_strategy::get_harvest_profit(&harvest_lock);

        assert!(coin::value(&to_apply) == credit_available, ERR_PROCESS_HARVEST);
        assert!(debt_payment == 0, ERR_PROCESS_HARVEST);
        assert!(profit == 0, ERR_PROCESS_HARVEST);

        let usdt = apply_position(coins_manager, coins_manager, to_apply);

        base_strategy::close_vault_for_harvest<TestStrategy, AptosCoin, USDT>(
            keeper_cap,
            harvest_lock,
            coin::zero(),
            coin::zero(),
            usdt
        );
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_process_harvest_profit(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer,
    ) {
        let profit_amount = 50;

        setup_and_user_deposit(
            aptos_framework,
            satay,
            coins_manager,
            user,
        );

        let (keeper_cap, vault_cap_lock) = base_strategy::open_vault_for_harvest<TestStrategy, AptosCoin>(
            satay,
            0,
            TestStrategy {}
        );

        let seconds = 1000;
        timestamp::fast_forward_seconds(seconds);

        let strategy_balance = profit_amount;
        let credit_available = vault::keeper_credit_available<TestStrategy, AptosCoin>(&keeper_cap);

        let (to_apply, harvest_lock) = base_strategy::process_harvest<TestStrategy, AptosCoin, USDT>(
            &keeper_cap,
            strategy_balance,
            vault_cap_lock
        );

        let debt_payment = base_strategy::get_harvest_debt_payment(&harvest_lock);
        let profit = base_strategy::get_harvest_profit(&harvest_lock);

        assert!(coin::value(&to_apply) == credit_available, ERR_PROCESS_HARVEST);
        assert!(debt_payment == 0, ERR_PROCESS_HARVEST);
        assert!(profit == profit_amount, ERR_PROCESS_HARVEST);

        aptos_coin::mint(aptos_framework, signer::address_of(user), profit_amount);
        let profit_coins = coin::withdraw<AptosCoin>(user, profit_amount);

        let usdt = apply_position(coins_manager, coins_manager, to_apply);

        base_strategy::close_vault_for_harvest<TestStrategy, AptosCoin, USDT>(
            keeper_cap,
            harvest_lock,
            coin::zero(),
            profit_coins,
            usdt
        );
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_process_harvest_loss(
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


        let (keeper_cap, vault_cap_lock) = base_strategy::open_vault_for_harvest<TestStrategy, AptosCoin>(
            satay,
            0,
            TestStrategy {}
        );

        let debt_amount = vault::keeper_credit_available<TestStrategy, AptosCoin>(
            &keeper_cap
        );
        let loss_amount = debt_amount / 2;


        let aptos = vault::test_keeper_withdraw_base_coin<TestStrategy, AptosCoin>(
            &keeper_cap,
            debt_amount,
        );
        coin::deposit(signer::address_of(user), aptos);


        let strategy_balance = debt_amount - loss_amount;

        let (to_apply, harvest_lock) = base_strategy::process_harvest<TestStrategy, AptosCoin, USDT>(
            &keeper_cap,
            strategy_balance,
            vault_cap_lock
        );

        let usdt = apply_position(coins_manager, coins_manager, to_apply);

        let debt_payment = base_strategy::get_harvest_debt_payment(&harvest_lock);
        let profit = base_strategy::get_harvest_profit(&harvest_lock);



        base_strategy::close_vault_for_harvest<TestStrategy, AptosCoin, USDT>(
            keeper_cap,
            harvest_lock,
            coin::zero(),
            coin::zero(),
            usdt
        );

        let vault_cap = satay::open_vault(
            0,
        );
        assert!(debt_payment == 0, ERR_PROCESS_HARVEST);
        assert!(profit == 0, ERR_PROCESS_HARVEST);
        assert!(vault::total_debt<TestStrategy>(&vault_cap) == debt_amount - loss_amount, ERR_PROCESS_HARVEST);
        assert!(vault::debt_ratio<TestStrategy>(&vault_cap) == DEBT_RATIO / 2, ERR_PROCESS_HARVEST);
        satay::close_vault(0, vault_cap);

    }

    fun harvest(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer,
    ){
        let (keeper_cap, vault_cap_lock) = base_strategy::open_vault_for_harvest<TestStrategy, AptosCoin>(
            satay,
            0,
            TestStrategy {}
        );

        let strategy_balance = base_strategy::harvest_balance<TestStrategy, USDT>(&keeper_cap);

        let (to_apply, harvest_lock) = base_strategy::process_harvest<TestStrategy, AptosCoin, USDT>(
            &keeper_cap,
            strategy_balance,
            vault_cap_lock
        );

        let debt_payment = base_strategy::get_harvest_debt_payment(&harvest_lock);
        let profit = base_strategy::get_harvest_profit(&harvest_lock);

        let strategy_coins_to_liquidate = base_strategy::withdraw_strategy_coin<TestStrategy, USDT>(
            &keeper_cap,
            debt_payment + profit,
        );
        let liquidated_coins = liquidate_position(aptos_framework, user, strategy_coins_to_liquidate);
        let debt_payment = coin::extract<AptosCoin>(&mut liquidated_coins, debt_payment);
        let profit = coin::extract<AptosCoin>(&mut liquidated_coins, profit);
        coin::destroy_zero(liquidated_coins);

        let usdt = apply_position(coins_manager, coins_manager, to_apply);

        base_strategy::close_vault_for_harvest<TestStrategy, AptosCoin, USDT>(
            keeper_cap,
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
    fun test_harvest_credit(
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
    fun test_harvest_profit(
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

        let seconds = 1000;
        timestamp::fast_forward_seconds(seconds);

        let (vault_cap, vault_cap_lock) = satay::test_lock_vault<TestStrategy>(
            0,
            &TestStrategy {}
        );

        let balance_before = base_strategy::balance<AptosCoin>(
            &vault_cap,
        );

        let profit = 50;
        coins::mint_coin<USDT>(coins_manager, signer::address_of(user), profit);
        let usdt = coin::withdraw<USDT>(user, profit);

        let keeper_cap = vault::test_get_keeper_cap(satay, vault_cap, TestStrategy{});
        base_strategy::deposit_strategy_coin(
            &keeper_cap,
            usdt,
        );
        vault_cap = vault::test_destroy_keeper_cap(keeper_cap);

        let performance_fee = profit * PERFORMANCE_FEE / MAX_DEBT_RATIO_BPS;
        let management_fee = (
            vault::total_debt<TestStrategy>(&vault_cap) *
                seconds * MANAGEMENT_FEE / MAX_DEBT_RATIO_BPS /
                SECS_PER_YEAR
        );
        let expected_fee = vault::calculate_vault_coin_amount_from_base_coin_amount<AptosCoin>(
            &vault_cap,
            performance_fee + management_fee
        );

        satay::test_unlock_vault(vault_cap, vault_cap_lock);

        harvest(aptos_framework, satay, coins_manager, user);

        let vault_cap = satay::open_vault(0);

        assert!(base_strategy::balance<AptosCoin>(&vault_cap) == balance_before + profit, ERR_HARVEST);
        assert!(vault::total_gain<TestStrategy>(&vault_cap) == profit, ERR_HARVEST);
        let vault_addr = vault::get_vault_addr(&vault_cap);
        assert!(dao_storage::balance<VaultCoin<AptosCoin>>(vault_addr) == expected_fee, ERR_HARVEST);
        satay::close_vault(0, vault_cap);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_harvest_profit_and_credit(
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

        let seconds = 1000;
        timestamp::fast_forward_seconds(seconds);

        let (vault_cap, vault_cap_lock) = satay::test_lock_vault<TestStrategy>(
            0,
            &TestStrategy {},
        );

        let credit_available = vault::credit_available<TestStrategy, AptosCoin>(&vault_cap);

        let profit = 50;
        coins::mint_coin<USDT>(coins_manager, signer::address_of(user), profit);
        let usdt = coin::withdraw<USDT>(user, profit);

        let keeper_cap = vault::test_get_keeper_cap(satay, vault_cap, TestStrategy {});
        base_strategy::deposit_strategy_coin(
            &keeper_cap,
            usdt,
        );
        vault_cap = vault::test_destroy_keeper_cap(keeper_cap);

        let performance_fee = profit * PERFORMANCE_FEE / MAX_DEBT_RATIO_BPS;
        let management_fee = (
            vault::total_debt<TestStrategy>(&vault_cap) *
                seconds * MANAGEMENT_FEE / MAX_DEBT_RATIO_BPS /
                SECS_PER_YEAR
        );
        let expected_fee = vault::calculate_vault_coin_amount_from_base_coin_amount<AptosCoin>(
            &vault_cap,
            performance_fee + management_fee
        );

        satay::test_unlock_vault(vault_cap, vault_cap_lock);

        harvest(aptos_framework, satay, coins_manager, user);

        let vault_cap = satay::open_vault(0);
        assert!(base_strategy::balance<AptosCoin>(&vault_cap) == DEPOSIT_AMOUNT - credit_available + profit, ERR_HARVEST);
        let vault_addr = vault::get_vault_addr(&vault_cap);
        assert!(dao_storage::balance<VaultCoin<AptosCoin>>(vault_addr) == expected_fee, ERR_HARVEST);

        satay::close_vault(0, vault_cap);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_harvest_debt_payment(
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

        base_strategy::update_debt_ratio<TestStrategy>(
            satay,
            0,
            0,
            TestStrategy {}
        );

        harvest(aptos_framework, satay, coins_manager, user);

        let vault_cap = satay::open_vault(0);
        assert!(base_strategy::balance<AptosCoin>(&vault_cap) == DEPOSIT_AMOUNT, ERR_HARVEST);
        satay::close_vault(0, vault_cap);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    fun test_harvest_debt_payment_and_profit(
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

        let seconds = 1000;
        timestamp::fast_forward_seconds(seconds);

        let (vault_cap, vault_cap_lock) = satay::test_lock_vault<TestStrategy>(
            0,
            &TestStrategy {},
        );

        let profit = 50;
        coins::mint_coin<USDT>(coins_manager, signer::address_of(user), profit);
        let usdt = coin::withdraw<USDT>(user, profit);

        let keeper_cap = vault::test_get_keeper_cap(satay, vault_cap, TestStrategy {});
        base_strategy::deposit_strategy_coin(
            &keeper_cap,
            usdt,
        );
        vault_cap = vault::test_destroy_keeper_cap(keeper_cap);

        let performance_fee = profit * PERFORMANCE_FEE / MAX_DEBT_RATIO_BPS;
        let management_fee = (
            vault::total_debt<TestStrategy>(&vault_cap) *
                seconds * MANAGEMENT_FEE / MAX_DEBT_RATIO_BPS /
                SECS_PER_YEAR
        );
        let expected_fee = vault::calculate_vault_coin_amount_from_base_coin_amount<AptosCoin>(
            &vault_cap,
            performance_fee + management_fee
        );

        satay::test_unlock_vault(vault_cap, vault_cap_lock);

        base_strategy::update_debt_ratio<TestStrategy>(
            satay,
            0,
            0,
            TestStrategy {}
        );

        harvest(aptos_framework, satay, coins_manager, user);

        let vault_cap = satay::open_vault(0);
        assert!(base_strategy::balance<AptosCoin>(&vault_cap) == DEPOSIT_AMOUNT + profit, ERR_HARVEST);
        let vault_addr = vault::get_vault_addr(&vault_cap);
        assert!(dao_storage::balance<VaultCoin<AptosCoin>>(vault_addr) == expected_fee, ERR_HARVEST);
        satay::close_vault(0, vault_cap);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    #[expected_failure]
    fun test_harvest_profit_wrong_amount(
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

        let (vault_cap, vault_cap_lock) = satay::test_lock_vault<TestStrategy>(
            0,
            &TestStrategy {},
        );

        let profit = 50;
        coins::mint_coin<USDT>(coins_manager, signer::address_of(user), profit);
        let usdt = coin::withdraw<USDT>(user, profit);

        let keeper_cap = vault::test_get_keeper_cap(satay, vault_cap, TestStrategy {});
        base_strategy::deposit_strategy_coin(
            &keeper_cap,
            usdt,
        );
        vault_cap = vault::test_destroy_keeper_cap(keeper_cap);

        satay::test_unlock_vault(vault_cap, vault_cap_lock);

        let (keeper_cap, vault_cap_lock) = base_strategy::open_vault_for_harvest<TestStrategy, AptosCoin>(
            satay,
            0,
            TestStrategy {},
        );

        let strategy_balance = base_strategy::harvest_balance<TestStrategy, USDT>(&keeper_cap);
        let (
            to_apply,
            harvest_lock
        ) = base_strategy::process_harvest<TestStrategy, AptosCoin, USDT>(
            &keeper_cap,
            strategy_balance,
            vault_cap_lock
        );

        assert!(base_strategy::get_harvest_debt_payment<TestStrategy>(&harvest_lock) == 0, ERR_HARVEST);
        assert!(base_strategy::get_harvest_profit<TestStrategy>(&harvest_lock) == profit, ERR_HARVEST);

        let strategy_coins = apply_position(coins_manager, coins_manager, to_apply);

        base_strategy::close_vault_for_harvest<TestStrategy, AptosCoin, USDT>(
            keeper_cap,
            harvest_lock,
            coin::zero(),
            coin::zero(),
            strategy_coins,
        );
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    #[expected_failure]
    fun test_harvest_debt_payment_wrong_amount(
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

        base_strategy::update_debt_ratio<TestStrategy>(
            satay,
            0,
            0,
            TestStrategy {}
        );

        let (keeper_cap, vault_cap_lock) = base_strategy::open_vault_for_harvest<TestStrategy, AptosCoin>(
            satay,
            0,
            TestStrategy {},
        );

        let debt_out_standing = vault::keeper_debt_out_standing<TestStrategy, AptosCoin>(&keeper_cap);

        let strategy_balance = base_strategy::harvest_balance<TestStrategy, USDT>(&keeper_cap);
        let (
            to_apply,
            harvest_lock
        ) = base_strategy::process_harvest<TestStrategy, AptosCoin, USDT>(
            &keeper_cap,
            strategy_balance,
            vault_cap_lock
        );

        assert!(base_strategy::get_harvest_debt_payment<TestStrategy>(&harvest_lock) == debt_out_standing, ERR_HARVEST);
        assert!(base_strategy::get_harvest_profit<TestStrategy>(&harvest_lock) == 0, ERR_HARVEST);

        let strategy_coins = apply_position(coins_manager, coins_manager, to_apply);

        base_strategy::close_vault_for_harvest<TestStrategy, AptosCoin, USDT>(
            keeper_cap,
            harvest_lock,
            coin::zero(),
            coin::zero(),
            strategy_coins,
        );
    }

    fun tend(
        satay: &signer,
        coins_manager: &signer,
        user: &signer,
    ) {
        let user_address = signer::address_of(user);
        coins::mint_coin<USDT>(coins_manager, user_address, TEND_AMOUNT);

        let (
            vault_cap,
            tend_lock
        ) = base_strategy::open_vault_for_tend<TestStrategy, AptosCoin>(
            satay,
            0,
            TestStrategy {},
        );

        let usdt = coin::withdraw<USDT>(user, TEND_AMOUNT);

        base_strategy::close_vault_for_tend<TestStrategy, USDT>(
            vault_cap,
            tend_lock,
            usdt
        );
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
        setup_and_user_deposit(
            aptos_framework,
            satay,
            coins_manager,
            user,
        );

        tend(satay, coins_manager, user);

        let vault_cap = satay::open_vault(0);
        assert!(base_strategy::balance<USDT>(&vault_cap) == TEND_AMOUNT, ERR_TEND);
        satay::close_vault(0, vault_cap);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    #[expected_failure]
    fun test_tend_debt_outstanding(
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
        base_strategy::update_debt_ratio<TestStrategy>(
            satay,
            0,
            0,
            TestStrategy {}
        );

        tend(satay, coins_manager, user);
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

        let user_vault_coin_balance = vault::vault_coin_balance<AptosCoin>(signer::address_of(user));
        let vault_coins = coin::withdraw<VaultCoin<AptosCoin>>(user, user_vault_coin_balance);

        let vault_cap = satay::open_vault(0);
        let base_coin_expected = vault::calculate_base_coin_amount_from_vault_coin_amount<AptosCoin>(
            &vault_cap,
            user_vault_coin_balance
        );
        satay::close_vault(0, vault_cap);

        let (
            user_cap,
            user_withdraw_lock
        ) = base_strategy::open_vault_for_user_withdraw<TestStrategy, AptosCoin, USDT>(
            user,
            0,
            vault_coins,
            TestStrategy {}
        );



        let usdt = base_strategy::withdraw_strategy_coin_for_liquidation<TestStrategy, USDT, AptosCoin>(
            &user_cap,
            base_strategy::get_user_withdraw_amount_needed(&user_withdraw_lock),
            &user_withdraw_lock
        );


        let aptos_coins = liquidate_position(aptos_framework, user, usdt);


        base_strategy::close_vault_for_user_withdraw(
            user_cap,
            user_withdraw_lock,
            aptos_coins
        );

        let vault_cap = satay::open_vault(0);
        assert!(base_strategy::balance<USDT>(&vault_cap) == 0, ERR_USER_WITHDRAW);

        assert!(coin::balance<AptosCoin>(signer::address_of(user)) == base_coin_expected, ERR_USER_WITHDRAW);
        assert!(vault::total_loss<TestStrategy>(&vault_cap) == 0, ERR_USER_WITHDRAW);
        satay::close_vault(0, vault_cap);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    #[expected_failure]
    fun test_user_withdraw_loss(
        aptos_framework: &signer,
        satay: &signer,
        coins_manager: &signer,
        user: &signer,
    ) {
        let loss = 10;

        setup_and_user_deposit(
            aptos_framework,
            satay,
            coins_manager,
            user,
        );

        harvest(aptos_framework, satay, coins_manager, user);

        let user_vault_coin_balance = vault::vault_coin_balance<AptosCoin>(signer::address_of(user));
        let user_vault_coins = coin::withdraw<VaultCoin<AptosCoin>>(user, user_vault_coin_balance);

        let (
            user_cap,
            user_withdraw_lock
        ) = base_strategy::open_vault_for_user_withdraw<TestStrategy, AptosCoin, USDT>(
            user,
            0,
            user_vault_coins,
            TestStrategy {}
        );

        let usdt = base_strategy::withdraw_strategy_coin_for_liquidation<TestStrategy, USDT, AptosCoin>(
            &user_cap,
            base_strategy::get_user_withdraw_amount_needed(&user_withdraw_lock) - loss,
            &user_withdraw_lock
        );
        let aptos_coins = liquidate_position(aptos_framework, user, usdt);

        base_strategy::close_vault_for_user_withdraw(
            user_cap,
            user_withdraw_lock,
            aptos_coins
        );
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    #[expected_failure]
    fun test_user_withdraw_not_enough_share_coins(
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

        let user_withdraw_amount= vault::vault_coin_balance<AptosCoin>(signer::address_of(user)) + 1;
        let user_vault_coins = coin::withdraw<VaultCoin<AptosCoin>>(user, user_withdraw_amount);

        let (
            user_cap,
            user_withdraw_lock
        ) = base_strategy::open_vault_for_user_withdraw<TestStrategy, AptosCoin, USDT>(
            user,
            0,
            user_vault_coins,
            TestStrategy {}
        );
        base_strategy::close_vault_for_user_withdraw(
            user_cap,
            user_withdraw_lock,
            coin::zero<AptosCoin>()
        )
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        coins_manager = @satay,
        user = @0x47
    )]
    #[expected_failure]
    fun test_user_withdraw_enough_liquidity(
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

        let user_vault_coin_balance = vault::vault_coin_balance<AptosCoin>(signer::address_of(user));
        let user_vault_coins = coin::withdraw<VaultCoin<AptosCoin>>(user, user_vault_coin_balance);

        let (
            vault_cap,
            user_withdraw_lock
        ) = base_strategy::open_vault_for_user_withdraw<TestStrategy, AptosCoin, USDT>(
            user,
            0,
            user_vault_coins,
            TestStrategy {}
        );
        base_strategy::close_vault_for_user_withdraw(
            vault_cap,
            user_withdraw_lock,
            coin::zero<AptosCoin>()
        )
    }
}
