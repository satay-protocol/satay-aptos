#[test_only]
module satay::test_base_strategy {

    use std::signer;

    use aptos_framework::stake;
    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::timestamp;

    use satay_coins::vault_coin::VaultCoin;
    use satay_coins::strategy_coin::StrategyCoin;

    use satay::satay_account;

    use satay::satay;
    use satay::base_strategy;
    use satay::coins::{Self, BTC};
    use satay::vault;
    use satay::dao_storage;

    const MAX_DEBT_RATIO_BPS: u64 = 10000;
    const SECS_PER_YEAR: u64 = 31556952; // 365.2425 days

    const MANAGEMENT_FEE: u64 = 200;
    const PERFORMANCE_FEE: u64 = 2000;
    const DEBT_RATIO: u64 = 1000;
    const VAULT_ID: u64 = 0;
    const PROFIT_AMOUNT: u64 = 50;

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
        account::create_account_for_test(signer::address_of(coins_manager));
        coin::register<AptosCoin>(coins_manager);

        satay::new_vault<AptosCoin>(
            satay,
            MANAGEMENT_FEE,
            PERFORMANCE_FEE
        );

        satay::new_strategy<TestStrategy, AptosCoin>(satay, TestStrategy {});
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
        base_strategy::initialize<TestStrategy, AptosCoin>(
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
        assert!(vault::has_strategy<TestStrategy, AptosCoin>(&vault_cap), ERR_INITIALIZE);
        assert!(vault::has_coin<StrategyCoin<TestStrategy, AptosCoin>>(&vault_cap), ERR_INITIALIZE);
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

        base_strategy::initialize<TestStrategy, AptosCoin>(
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

        let amount = 1000;
        let strategy_coins = satay::strategy_mint<TestStrategy, AptosCoin>(amount, TestStrategy {});

        let (vault_cap, stop_handle) = satay::test_lock_vault<TestStrategy, AptosCoin>(
            0,
            &TestStrategy {}
        );

        let keeper_cap = vault::test_get_keeper_cap<TestStrategy, AptosCoin>(
            satay,
            vault_cap,
            TestStrategy {}
        );

        base_strategy::deposit_strategy_coin<TestStrategy, AptosCoin>(
            &keeper_cap,
            strategy_coins,
        );
        assert!(base_strategy::harvest_balance<TestStrategy, StrategyCoin<TestStrategy, AptosCoin>>(&keeper_cap) == amount, ERR_DEPOSIT);

        vault_cap = vault::test_destroy_keeper_cap(keeper_cap);

        satay::test_unlock_vault<TestStrategy, AptosCoin>(vault_cap, stop_handle);
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

        let amount = 1000;
        let strategy_coins = satay::strategy_mint<TestStrategy, AptosCoin>(amount, TestStrategy {});

        let (keeper_cap, stop_handle) = satay::test_keeper_lock_vault<TestStrategy, AptosCoin>(
            satay,
            0,
            TestStrategy {}
        );

        base_strategy::deposit_strategy_coin<TestStrategy, AptosCoin>(
            &keeper_cap,
            strategy_coins,
        );
        let strategy_coins = vault::test_withdraw_strategy_coin<TestStrategy, AptosCoin>(
            &keeper_cap,
            amount,
        );

        assert!(coin::value(&strategy_coins) == amount, ERR_WITHDRAW);
        satay::strategy_burn(strategy_coins, TestStrategy {});

        assert!(base_strategy::harvest_balance<TestStrategy, AptosCoin>(&keeper_cap) == 0, ERR_WITHDRAW);


        satay::test_keeper_unlock_vault<TestStrategy, AptosCoin>(keeper_cap, stop_handle);
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

        let amount = 1000;
        let strategy_coins = satay::strategy_mint<TestStrategy, AptosCoin>(amount, TestStrategy {});

        let (keeper_cap, stop_handle) = satay::test_keeper_lock_vault<TestStrategy, AptosCoin>(
            satay,
            0,
            TestStrategy {}
        );

        base_strategy::deposit_strategy_coin<TestStrategy, AptosCoin>(
            &keeper_cap,
            strategy_coins,
        );
        let strategy_coins = vault::test_withdraw_strategy_coin<TestStrategy, BTC>(
            &keeper_cap,
            amount,
        );
        satay::strategy_burn(strategy_coins, TestStrategy {});

        satay::test_keeper_unlock_vault<TestStrategy, AptosCoin>(keeper_cap, stop_handle);
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

        let vault_cap = satay::open_vault(0);

        assert!(vault::debt_ratio<TestStrategy, AptosCoin>(&vault_cap) == debt_ratio, ERR_ADMIN_FUNCTIONS);

        satay::close_vault(0, vault_cap);
    }

    fun apply_position(
        strategy: &signer,
        aptos_coins: Coin<AptosCoin>
    ): Coin<StrategyCoin<TestStrategy, AptosCoin>> {
        let amount = coin::value(&aptos_coins);
        let strategy_address = signer::address_of(strategy);
        coin::deposit<AptosCoin>(strategy_address, aptos_coins);
        satay::strategy_mint<TestStrategy, AptosCoin>(amount, TestStrategy {})
    }

    fun liquidate_position(
        strategy: &signer,
        strategy_coins: Coin<StrategyCoin<TestStrategy, AptosCoin>>
    ): Coin<AptosCoin> {
        let amount = coin::value(&strategy_coins);
        if (amount > 0) {
            satay::strategy_burn(strategy_coins, TestStrategy {});
            coin::withdraw<AptosCoin>(strategy, amount)
        } else {
            coin::destroy_zero(strategy_coins);
            coin::zero<AptosCoin>()
        }
    }

    fun harvest(
        satay: &signer,
        user: &signer,
    ){

        let strategy_balance = satay::get_vault_balance<StrategyCoin<TestStrategy, AptosCoin>>(VAULT_ID);

        let (to_apply, harvest_lock) = base_strategy::open_vault_for_harvest<TestStrategy, AptosCoin>(
            satay,
            VAULT_ID,
            strategy_balance,
            TestStrategy {}
        );

        let debt_payment = base_strategy::get_harvest_debt_payment(&harvest_lock);
        let profit = base_strategy::get_harvest_profit(&harvest_lock);

        let strategy_coins_to_liquidate = base_strategy::withdraw_strategy_coin<TestStrategy, AptosCoin>(
            &harvest_lock,
            debt_payment + profit,
        );
        let liquidated_coins = liquidate_position(user, strategy_coins_to_liquidate);
        let debt_payment = coin::extract<AptosCoin>(&mut liquidated_coins, debt_payment);
        let profit = coin::extract<AptosCoin>(&mut liquidated_coins, profit);
        coin::destroy_zero(liquidated_coins);

        let usdt = apply_position(user, to_apply);

        base_strategy::close_vault_for_harvest<TestStrategy, AptosCoin>(
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

        let credit_available = satay::get_credit_available<TestStrategy, AptosCoin>(VAULT_ID);

        assert!(credit_available == DEPOSIT_AMOUNT * DEBT_RATIO / MAX_DEBT_RATIO_BPS, ERR_HARVEST);

        harvest(satay, user);

        let strategy_coins = satay::get_vault_balance<StrategyCoin<TestStrategy, AptosCoin>>(VAULT_ID);
        assert!(strategy_coins == credit_available, ERR_HARVEST);
    }

    fun harvest_profit(
        aptos_framework: &signer,
        satay: &signer,
        user: &signer
    ) {
        let (keeper_cap, vault_cap_lock) = satay::test_keeper_lock_vault<TestStrategy, AptosCoin>(
            satay,
            VAULT_ID,
            TestStrategy {},
        );
        aptos_coin::mint(aptos_framework, signer::address_of(user), PROFIT_AMOUNT);
        let strategy_coins = satay::strategy_mint<TestStrategy, AptosCoin>(PROFIT_AMOUNT, TestStrategy {});
        base_strategy::deposit_strategy_coin(
            &keeper_cap,
            strategy_coins,
        );
        satay::test_keeper_unlock_vault<TestStrategy, AptosCoin>(keeper_cap, vault_cap_lock);
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

        harvest(satay, user);

        let seconds = 1000;
        timestamp::fast_forward_seconds(seconds);

        let balance_before = satay::get_vault_balance<AptosCoin>(VAULT_ID);

        harvest_profit(aptos_framework, satay, user);

        let performance_fee = PROFIT_AMOUNT * PERFORMANCE_FEE / MAX_DEBT_RATIO_BPS;
        let management_fee = (
            satay::get_strategy_total_debt<TestStrategy, AptosCoin>(VAULT_ID) *
                seconds * MANAGEMENT_FEE / MAX_DEBT_RATIO_BPS /
                SECS_PER_YEAR
        );
        let vault_cap = satay::open_vault(VAULT_ID);
        let expected_fee = vault::calculate_vault_coin_amount_from_base_coin_amount<AptosCoin>(
            &vault_cap,
            performance_fee + management_fee
        );
        satay::close_vault(VAULT_ID, vault_cap);

        harvest(satay, user);

        assert!(satay::get_vault_balance<AptosCoin>(VAULT_ID) == balance_before + PROFIT_AMOUNT, ERR_HARVEST);
        assert!(satay::get_total_gain<TestStrategy, AptosCoin>(VAULT_ID) == PROFIT_AMOUNT, ERR_HARVEST);
        let vault_addr = satay::get_vault_address_by_id(VAULT_ID);
        assert!(dao_storage::balance<VaultCoin<AptosCoin>>(vault_addr) == expected_fee, ERR_HARVEST);
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

        let credit_available = satay::get_credit_available<TestStrategy, AptosCoin>(VAULT_ID);

        harvest_profit(aptos_framework, satay, user);

        let performance_fee = PROFIT_AMOUNT * PERFORMANCE_FEE / MAX_DEBT_RATIO_BPS;
        let management_fee = (
            satay::get_strategy_total_debt<TestStrategy, AptosCoin>(VAULT_ID) *
                seconds * MANAGEMENT_FEE / MAX_DEBT_RATIO_BPS /
                SECS_PER_YEAR
        );
        let vault_cap = satay::open_vault(VAULT_ID);
        let expected_fee = vault::calculate_vault_coin_amount_from_base_coin_amount<AptosCoin>(
            &vault_cap,
            performance_fee + management_fee
        );
        satay::close_vault(VAULT_ID, vault_cap);

        harvest(satay, user);

        assert!(satay::get_vault_balance<AptosCoin>(VAULT_ID) == DEPOSIT_AMOUNT - credit_available + PROFIT_AMOUNT, ERR_HARVEST);
        let vault_addr = satay::get_vault_address_by_id(VAULT_ID);
        assert!(dao_storage::balance<VaultCoin<AptosCoin>>(vault_addr) == expected_fee, ERR_HARVEST);
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

        harvest(satay, user);

        base_strategy::update_debt_ratio<TestStrategy, AptosCoin>(
            satay,
            0,
            0,
            TestStrategy {}
        );

        harvest(satay, user);

        assert!(satay::get_vault_balance<AptosCoin>(VAULT_ID) == DEPOSIT_AMOUNT, ERR_HARVEST);
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

        harvest(satay, user);

        let seconds = 1000;
        timestamp::fast_forward_seconds(seconds);

        harvest_profit(aptos_framework, satay, user);

        let performance_fee = PROFIT_AMOUNT * PERFORMANCE_FEE / MAX_DEBT_RATIO_BPS;
        let management_fee = (
            satay::get_strategy_total_debt<TestStrategy, AptosCoin>(VAULT_ID) *
                seconds * MANAGEMENT_FEE / MAX_DEBT_RATIO_BPS /
                SECS_PER_YEAR
        );
        let vault_cap = satay::open_vault(VAULT_ID);
        let expected_fee = vault::calculate_vault_coin_amount_from_base_coin_amount<AptosCoin>(
            &vault_cap,
            performance_fee + management_fee
        );
        satay::close_vault(VAULT_ID, vault_cap);

        base_strategy::update_debt_ratio<TestStrategy, AptosCoin>(
            satay,
            0,
            0,
            TestStrategy {}
        );

        harvest(satay, user);

        assert!(satay::get_vault_balance<AptosCoin>(VAULT_ID) == DEPOSIT_AMOUNT + PROFIT_AMOUNT, ERR_HARVEST);
        let vault_addr = satay::get_vault_address_by_id(VAULT_ID);
        assert!(dao_storage::balance<VaultCoin<AptosCoin>>(vault_addr) == expected_fee, ERR_HARVEST);
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

        harvest(satay, user);
        harvest_profit(aptos_framework, satay, user);
        let strategy_balance = satay::get_vault_balance<StrategyCoin<TestStrategy, AptosCoin>>(VAULT_ID);

        let (to_apply, harvest_lock) = base_strategy::open_vault_for_harvest<TestStrategy, AptosCoin>(
            satay,
            VAULT_ID,
            strategy_balance,
            TestStrategy {},
        );

        assert!(base_strategy::get_harvest_debt_payment<TestStrategy>(&harvest_lock) == 0, ERR_HARVEST);
        assert!(base_strategy::get_harvest_profit<TestStrategy>(&harvest_lock) == PROFIT_AMOUNT, ERR_HARVEST);

        let strategy_coins = apply_position(user, to_apply);

        base_strategy::close_vault_for_harvest<TestStrategy, AptosCoin>(
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

        harvest(satay, user);

        base_strategy::update_debt_ratio<TestStrategy, AptosCoin>(
            satay,
            0,
            0,
            TestStrategy {}
        );

        let strategy_balance = satay::get_vault_balance<StrategyCoin<TestStrategy, AptosCoin>>(VAULT_ID);
        let debt_out_standing = satay::get_debt_out_standing<TestStrategy, AptosCoin>(VAULT_ID);

        let (to_apply, harvest_lock) = base_strategy::open_vault_for_harvest<TestStrategy, AptosCoin>(
            satay,
            VAULT_ID,
            strategy_balance,
            TestStrategy {},
        );

        assert!(base_strategy::get_harvest_debt_payment<TestStrategy>(&harvest_lock) == debt_out_standing, ERR_HARVEST);
        assert!(base_strategy::get_harvest_profit<TestStrategy>(&harvest_lock) == 0, ERR_HARVEST);

        let strategy_coins = apply_position(user, to_apply);

        base_strategy::close_vault_for_harvest<TestStrategy, AptosCoin>(
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
        harvest(satay, user);

        let user_vault_coin_balance = vault::vault_coin_balance<AptosCoin>(signer::address_of(user));
        let vault_coins = coin::withdraw<VaultCoin<AptosCoin>>(user, user_vault_coin_balance);

        let base_coin_expected = satay::get_base_coin_amount<AptosCoin>(VAULT_ID, user_vault_coin_balance);

        let user_withdraw_lock = base_strategy::open_vault_for_user_withdraw<TestStrategy, AptosCoin>(
            user,
            0,
            vault_coins,
            TestStrategy {}
        );
        let strategy_coins = base_strategy::withdraw_strategy_coin_for_liquidation<TestStrategy, AptosCoin>(
            &user_withdraw_lock,
            base_strategy::get_user_withdraw_amount_needed(&user_withdraw_lock)
        );

        let aptos_coins = liquidate_position(user, strategy_coins);

        base_strategy::close_vault_for_user_withdraw(
            user_withdraw_lock,
            aptos_coins
        );

        assert!(satay::get_vault_balance<StrategyCoin<TestStrategy, AptosCoin>>(VAULT_ID) == 0, ERR_USER_WITHDRAW);
        assert!(coin::balance<AptosCoin>(signer::address_of(user)) == base_coin_expected, ERR_USER_WITHDRAW);
        assert!(satay::get_total_loss<TestStrategy, AptosCoin>(VAULT_ID) == 0, ERR_USER_WITHDRAW);
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

        harvest(satay, user);

        let user_vault_coin_balance = vault::vault_coin_balance<AptosCoin>(signer::address_of(user));
        let user_vault_coins = coin::withdraw<VaultCoin<AptosCoin>>(user, user_vault_coin_balance);

        let user_withdraw_lock = base_strategy::open_vault_for_user_withdraw<TestStrategy, AptosCoin>(
            user,
            0,
            user_vault_coins,
            TestStrategy {}
        );

        let strategy_coins = base_strategy::withdraw_strategy_coin_for_liquidation<TestStrategy, AptosCoin>(
            &user_withdraw_lock,
            base_strategy::get_user_withdraw_amount_needed(&user_withdraw_lock) - loss
        );
        let aptos_coins = liquidate_position(user, strategy_coins);

        base_strategy::close_vault_for_user_withdraw(
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

        harvest(satay, user);

        let user_withdraw_amount= vault::vault_coin_balance<AptosCoin>(signer::address_of(user)) + 1;
        let user_vault_coins = coin::withdraw<VaultCoin<AptosCoin>>(user, user_withdraw_amount);

        let user_withdraw_lock = base_strategy::open_vault_for_user_withdraw<TestStrategy, AptosCoin>(
            user,
            0,
            user_vault_coins,
            TestStrategy {}
        );
        base_strategy::close_vault_for_user_withdraw(
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

        let user_withdraw_lock = base_strategy::open_vault_for_user_withdraw<TestStrategy, AptosCoin>(
            user,
            0,
            user_vault_coins,
            TestStrategy {}
        );

        base_strategy::close_vault_for_user_withdraw(
            user_withdraw_lock,
            coin::zero<AptosCoin>()
        )
    }
}
