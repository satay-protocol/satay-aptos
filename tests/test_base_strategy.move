#[test_only]
module satay::test_base_strategy {

    use std::signer;

    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin;
    use aptos_framework::stake;

    use test_helpers::test_account;

    use satay::satay;
    use satay::global_config;
    use satay::base_strategy;

    struct TestStrategy has drop {}

    struct TestStrategyCoin {}

    fun setup_tests(
        aptos_framework: &signer,
        manager_acc: &signer,
        user: &signer
    ) {
        global_config::initialize(manager_acc);
        stake::initialize_for_test(aptos_framework);

        test_account::create_account(user);
        test_account::create_account(manager_acc);

        let user_address = signer::address_of(user);
        coin::register<AptosCoin>(user);

        aptos_coin::mint(aptos_framework, user_address, 100000);
    }

    #[test_only]
    fun setup_strategy_vault(
        aptos_framework: &signer,
        manager_acc: &signer,
        user: &signer
    ) {
        setup_tests(aptos_framework, manager_acc, user);
        satay::initialize(manager_acc);
        satay::new_vault<AptosCoin>(manager_acc, b"aptos_vault", 200, 5000);
        satay::deposit<AptosCoin>(user, signer::address_of(manager_acc), 0, 1000);
        base_strategy::initialize<TestStrategy, TestStrategyCoin>(manager_acc, 0,  1000, TestStrategy{});
    }

    #[test(
        aptos_framework = @aptos_framework,
        manager_acc = @satay,
        user = @0x45
    )]
    public fun test_initialize(
        aptos_framework: &signer,
        manager_acc: &signer,
        user: &signer
    ) {
        setup_strategy_vault(aptos_framework, manager_acc, user);
    }

    #[test_reject(
        aptos_framework = @aptos_framework,
        manager_acc = @satay,
        user = @0x45
    )]
    public fun test_withdraw_wrong_strategy_coin(
        aptos_framework: &signer,
        manager_acc: &signer,
        user: &signer
    ) {
        setup_strategy_vault(aptos_framework, manager_acc, user);
        let manager_addr = signer::address_of(manager_acc);
        let (vault_cap, stop_handle) = base_strategy::test_open_vault<TestStrategy>(
            manager_addr,
            0,
            TestStrategy {}
        );
        let strategy_coin = base_strategy::withdraw_strategy_coin<TestStrategy, TestStrategyCoin>(&vault_cap, 0);
        coin::destroy_zero(strategy_coin);
        base_strategy::test_close_vault<TestStrategy>(
            manager_addr,
            vault_cap,
            stop_handle
        );

    }
}
