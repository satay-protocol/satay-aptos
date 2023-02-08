#[test_only]
module satay::test_vault {

    use std::signer;

    use aptos_std::type_info;

    use aptos_framework::coin;
    use aptos_framework::account;
    use aptos_framework::stake;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::timestamp;

    use satay_coins::vault_coin::VaultCoin;
    use satay_coins::strategy_coin::StrategyCoin;

    use satay::vault::{Self, VaultCapability, VaultManagerCapability};
    use satay::coins::{Self, USDT};
    use satay::dao_storage;
    use satay::satay;
    use satay::satay_account;

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
        satay_account::initialize_satay_account(
            satay,
            x"0a5361746179436f696e73020000000000000000403130333837434146364441363631433033364236443031384642423035433530433231374130373745453136413043344338353633373844393938454533414297021f8b08000000000002ff2d903f6fc32010c5773e45e425536c30d8984a9d3a77ca184511704782621b0bb0db7cfb9ab6dbfd79ef774f7759b47dea3b5ec9ac273cbc1f8e679df5eb23f8391dc98631f9309731ab694d8f645dee5103de96307afbda17959fa6356b336245c84503444c09d395a4c2b9d9022a32facd1ce5928343c1ac108a1a66a5b14ab79c0288ce7568a1730cd5c006cd5bca15db0d52236b1903c50b1f703b012e3803ced663aa3fc386e70ca3375772f7b95c7ae4bca4b7a6d9dbc76a6a1ba6462f39a4d3a84dfa2f6d8858ef828a44dc8a093a6994341aa9e985e9991c7ae55ae7da1ea550d8513e8861107d45d26ac0c7e2f9434d7b82c6c5fd7b5f213e9bd29ed26fa2ea0739f85a445d010000020d73747261746567795f636f696ebf011f8b08000000000002ff4d8f410ec2201045f79c620e60d23d312ef4081ab7cd0863db4881c060429ade5d2068246c18fe7fffcf300c303ba323f04c103924c590226978ba00570ec834e58b5b2c94db34c898c1a37ae14462287e4ddeb85c2c8fdc1481a24b4111a0522e590615a860742534b7946f4c864755b0631789d5e9643abefd442963cf6f6fd8049453136bcabd225ab1892c8545f5f64dd417f9ef7ff4335a76eb6f78cb9e0ef09d9e3152959d60dbc52e3ebb49a3451801000000000a7661756c745f636f696eaf011f8b08000000000002ff4d8f310ec2300c45f79cc237c88e1003307002d6cab8a6ad48e32a7190aaaa77278922c0f2643fffff6dad859bb83e828e0c5143228514b987a704b863727a91c943ee0aa0e20a0bd20b0736361f5f7971b266feb156227094148801892479050a8c9af759a15e1f0eefa2da5196ed1a6466e9936bf27513ff31d80ce42a76c5e2976a60cf61a296bb42ed852f735c46f42a339c3172199c60dbcd6e3e1cb58cd7f900000000000000",
            vector[
                x"a11ceb0b0500000005010002020208070a270831200a5105000000010002000100010d73747261746567795f636f696e0c5374726174656779436f696e0b64756d6d795f6669656c641f0373dfe41c4490b1c7bc9a230dd45f5ecd5f1e9818a3203910377ae1211d93000201020100",
                x"a11ceb0b05000000050100020202060708210829200a490500000001000100010a7661756c745f636f696e095661756c74436f696e0b64756d6d795f6669656c641f0373dfe41c4490b1c7bc9a230dd45f5ecd5f1e9818a3203910377ae1211d93000201020100"
            ],

        );
        satay::initialize(satay);
    }

    #[test_only]
    fun create_vault(
        satay_coins_account: &signer,
    ): VaultCapability {
        vault::new_test<AptosCoin>(
            satay_coins_account,
            0,
            MANAGEMENT_FEE,
            PERFORMANCE_FEE
        )
    }

    #[test_only]
    fun setup_tests_with_vault(
        aptos_framework: &signer,
        satay: &signer,
        satay_coins_account: &signer,
        user: &signer,
    ): VaultCapability {
        setup_tests(aptos_framework, satay, user);
        create_vault(satay_coins_account)
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
        satay_coins_account: &signer,
        user: &signer,
    ): VaultCapability {
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, satay_coins_account, user);
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
        satay_coins_account=@satay_coins,
        user=@0x46,
    )]
    fun test_create_vault(
        aptos_framework: &signer,
        vault_manager: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        setup_tests(aptos_framework, vault_manager, user);
        let vault_cap = create_vault(satay_coins_account);

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
        satay_coins_account=@satay_coins,
        user=@0x46,
    )]
    fun test_update_fee(
        aptos_framework: &signer,
        vault_manager: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, satay_coins_account, user);
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
        satay_coins_account=@satay_coins,
        user=@0x46,
    )]
    #[expected_failure]
    fun test_update_management_fee_reject(
        aptos_framework: &signer,
        vault_manager: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, satay_coins_account, user);
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
        satay_coins_account=@satay_coins,
        user=@0x46,
    )]
    #[expected_failure]
    fun test_update_performance_fee_reject(
        aptos_framework: &signer,
        vault_manager: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, satay_coins_account, user);
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
        satay_coins_account=@satay_coins,
        user=@0x46,
    )]
    fun test_deposit(
        aptos_framework: &signer,
        vault_manager: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, satay_coins_account, user);

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
        satay_coins_account=@satay_coins,
        user=@0x46,
    )]
    fun test_withdraw(
        aptos_framework: &signer,
        vault_manager: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, satay_coins_account, user);

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
        satay_coins_account=@satay_coins,
        user=@0x46,
    )]
    fun test_deposit_as_user(
        aptos_framework: &signer,
        vault_manager: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){

        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, satay_coins_account, user);

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
        satay_coins_account=@satay_coins,
        token_admin=@satay,
        user=@0x46,
    )]
    #[expected_failure]
    fun test_deposit_as_user_incorrect_base_coin(
        aptos_framework: &signer,
        vault_manager: &signer,
        satay_coins_account: &signer,
        token_admin: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, satay_coins_account, user);

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
        satay_coins_account=@satay_coins,
        user=@0x46,
    )]
    fun test_withdraw_as_user(
        aptos_framework: &signer,
        vault_manager: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){

        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, satay_coins_account, user);

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
        satay_coins_account=@satay_coins,
        user=@0x46,
    )]
    #[expected_failure]
    fun test_withdraw_as_user_incorrect_base_coin(
        aptos_framework: &signer,
        vault_manager: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, satay_coins_account, user);

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
        satay_coins_account=@satay_coins,
        user=@0x46,
    )]
    #[expected_failure]
    fun test_withdraw_as_user_not_enough_vault_coin(
        aptos_framework: &signer,
        vault_manager: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, satay_coins_account, user);

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
        satay_coins_account=@satay_coins,
        user=@0x46,
    )]
    fun test_withdraw_as_user_after_farm(
        aptos_framework: &signer,
        vault_manager: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, satay_coins_account, user);

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
        satay_coins_account=@satay_coins,
        user_a =@0x46,
        user_b =@0x047
    )]
    fun test_share_amount_calculation(
        aptos_framework: &signer,
        vault_manager: &signer,
        satay_coins_account: &signer,
        user_a: &signer,
        user_b: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, satay_coins_account, user_a);
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
        satay_coins_account=@satay_coins,
        user=@0x46,
    )]
    fun test_freeze_vault(
        aptos_framework: &signer,
        vault_manager: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, satay_coins_account, user);
        let vault_manager_cap = vault::test_get_vault_manager_cap(vault_manager, vault_cap);
        vault::test_freeze_vault(&vault_manager_cap);
        vault_cap = vault::test_destroy_vault_manager_cap(vault_manager_cap);
        assert!(vault::is_vault_frozen(&vault_cap), ERR_FREEZE_VAULT);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        satay_coins_account=@satay_coins,
        user=@0x46,
    )]
    #[expected_failure]
    fun test_freeze_while_frozen(
        aptos_framework: &signer,
        vault_manager: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, satay_coins_account, user);
        let vault_manager_cap = vault::test_get_vault_manager_cap(vault_manager, vault_cap);
        vault::test_freeze_vault(&vault_manager_cap);
        vault::test_freeze_vault(&vault_manager_cap);
        vault_cap = vault::test_destroy_vault_manager_cap(vault_manager_cap);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        satay_coins_account=@satay_coins,
        user=@0x46,
    )]
    fun test_unfreeze_vault(
        aptos_framework: &signer,
        vault_manager: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, satay_coins_account, user);
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
        satay_coins_account=@satay_coins,
        user=@0x46,
    )]
    #[expected_failure]
    fun test_unfreeze_while_unfrozen(
        aptos_framework: &signer,
        vault_manager: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, satay_coins_account, user);
        let vault_manager_cap = vault::test_get_vault_manager_cap(vault_manager, vault_cap);
        vault::test_unfreeze_vault(&vault_manager_cap);
        vault_cap = vault::test_destroy_vault_manager_cap(vault_manager_cap);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        satay_coins_account=@satay_coins,
        user=@0x46,
    )]
    fun test_withdraw_after_freeze(
        aptos_framework: &signer,
        vault_manager: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, satay_coins_account, user);
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
        satay_coins_account=@satay_coins,
        user=@0x46,
    )]
    #[expected_failure]
    fun test_deposit_after_freeze(
        aptos_framework: &signer,
        vault_manager: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, satay_coins_account, user);
        let vault_manager_cap = vault::test_get_vault_manager_cap(vault_manager, vault_cap);
        vault::test_freeze_vault(&vault_manager_cap);
        vault_cap = vault::test_destroy_vault_manager_cap(vault_manager_cap);
        vault_cap = user_deposit_base_coin(aptos_framework, user, vault_cap);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        vault_manager=@satay,
        satay_coins_account=@satay_coins,
        user=@0x46,
    )]
    fun test_deposit_after_unfreeze(
        aptos_framework: &signer,
        vault_manager: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, satay_coins_account, user);
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
        satay_coins_account=@satay_coins,
        user=@0x46,
    )]
    fun test_approve_strategy(
        aptos_framework: &signer,
        vault_manager: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault(aptos_framework, vault_manager, satay_coins_account, user);
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
        satay_coins_account=@satay_coins,
        user=@0x46,
    )]
    fun test_strategy_deposit_base_coin(
        aptos_framework: &signer,
        vault_manager: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, vault_manager, satay_coins_account, user);

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
        satay_coins_account=@satay_coins,
        token_admin=@satay,
        user=@0x46,
    )]
    #[expected_failure]
    fun test_strategy_deposit_incorrect_base_coin(
        aptos_framework: &signer,
        vault_manager: &signer,
        satay_coins_account: &signer,
        token_admin: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, vault_manager, satay_coins_account, user);

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
        satay_coins_account=@satay_coins,
        user=@0x46,
    )]
    fun test_strategy_withdraw_base_coin(
        aptos_framework: &signer,
        vault_manager: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, vault_manager, satay_coins_account, user);

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
        satay_coins_account=@satay_coins,
        user=@0x46,
    )]
    #[expected_failure]
    fun test_strategy_withdraw_base_coin_over_credit_availale(
        aptos_framework: &signer,
        vault_manager: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, vault_manager, satay_coins_account, user);

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
        satay_coins_account=@satay_coins,
        user=@0x46,
    )]
    #[expected_failure]
    fun test_strategy_withdraw_wrong_base_coin(
        aptos_framework: &signer,
        vault_manager: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, vault_manager, satay_coins_account, user);

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
        satay_coins_account=@satay_coins,
        user=@0x46,
    )]
    fun test_debt_payment(
        aptos_framework: &signer,
        keeper: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, keeper, satay_coins_account, user);
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
        satay_coins_account=@satay_coins,
        user=@0x46,
    )]
    fun test_deposit_profit(
        aptos_framework: &signer,
        keeper: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, keeper, satay_coins_account, user);
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
        satay_coins_account=@satay_coins,
        user=@0x46
    )]
    fun test_deposit_strategy_coin(
        aptos_framework: &signer,
        keeper: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, keeper, satay_coins_account, user);

        satay::new_strategy<TestStrategy, AptosCoin>(keeper, TestStrategy {});
        let amount = 100;
        let strategy_coins = satay::strategy_mint<TestStrategy, AptosCoin>(
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
        satay_coins_account=@satay_coins,
        user=@0x46
    )]
    fun test_withdraw_strategy_coin(
        aptos_framework: &signer,
        keeper: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, keeper, satay_coins_account, user);

        satay::new_strategy<TestStrategy, AptosCoin>(keeper, TestStrategy {});
        let amount = 100;
        let strategy_coins = satay::strategy_mint<TestStrategy, AptosCoin>(
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
        coin::register<StrategyCoin<TestStrategy, AptosCoin>>(user);
        coin::deposit(user_address, strategy_coins);
        assert!(coin::balance<StrategyCoin<TestStrategy, AptosCoin>>(user_address) == amount, ERR_STRATEGY_COIN_DEPOSIT_WITHDRAW);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        keeper=@satay,
        satay_coins_account=@satay_coins,
        user=@0x46
    )]
    fun test_withdraw_strategy_coin_over_balance(
        aptos_framework: &signer,
        keeper: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, keeper, satay_coins_account, user);

        satay::new_strategy<TestStrategy, AptosCoin>(keeper, TestStrategy {});
        let amount = 100;
        let strategy_coins = satay::strategy_mint<TestStrategy, AptosCoin>(
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

        vault_cap = vault::test_destroy_keeper_cap(keeper_cap);

        let user_address = signer::address_of(user);
        coin::register<StrategyCoin<TestStrategy, AptosCoin>>(user);
        coin::deposit(user_address, strategy_coins);
        assert!(coin::balance<StrategyCoin<TestStrategy, AptosCoin>>(user_address) == amount, ERR_STRATEGY_COIN_DEPOSIT_WITHDRAW);
        cleanup_tests(vault_cap);
    }

    #[test(
        aptos_framework=@aptos_framework,
        keeper=@satay,
        satay_coins_account=@satay_coins,
        user=@0x46
    )]
    #[expected_failure]
    fun test_withdraw_incorrect_strategy_coin(
        aptos_framework: &signer,
        keeper: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, keeper, satay_coins_account, user);

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
        satay_coins_account=@satay_coins,
        user=@0x46
    )]
    fun test_update_strategy_properties(
        aptos_framework: &signer,
        vault_manager: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, vault_manager, satay_coins_account, user);

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
        satay_coins_account=@satay_coins,
        user=@0x46
    )]
    #[expected_failure]
    fun test_update_strategy_debt_ratio_exceed_limit(
        aptos_framework: &signer,
        vault_manager: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, vault_manager, satay_coins_account, user);

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
        satay_coins_account=@satay_coins,
        user=@0x46
    )]
    fun test_reporting(
        aptos_framework: &signer,
        vault_manager: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, vault_manager, satay_coins_account, user);

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
        satay_coins_account=@satay_coins,
        user=@0x46
    )]
    fun test_assess_fees(
        aptos_framework: &signer,
        vault_manager: &signer,
        satay_coins_account: &signer,
        user: &signer
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, vault_manager, satay_coins_account, user);

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
        satay_coins_account = @satay_coins,
        user = @0x47
    )]
    fun test_prepare_return_profit(
        aptos_framework: &signer,
        satay: &signer,
        satay_coins_account: &signer,
        user: &signer,
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(aptos_framework, satay, satay_coins_account, user);

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
        satay_coins_account = @satay_coins,
        user = @0x47
    )]
    fun test_prepare_return_loss(
        aptos_framework: &signer,
        satay: &signer,
        satay_coins_account: &signer,
        user: &signer,
    ){
        let loss_amount = 50;

        let vault_cap = setup_tests_with_vault_and_strategy(
            aptos_framework,
            satay,
            satay_coins_account,
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
        satay_coins_account = @satay_coins,
        user = @0x47
    )]
    fun test_prepare_return_debt_payment(
        aptos_framework: &signer,
        satay: &signer,
        satay_coins_account: &signer,
        user: &signer,
    ){

        let vault_cap = setup_tests_with_vault_and_strategy(
            aptos_framework,
            satay,
            satay_coins_account,
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
        satay_coins_account = @satay_coins,
        user = @0x47
    )]
    fun test_user_liquidation(
        aptos_framework: &signer,
        satay: &signer,
        satay_coins_account: &signer,
        user: &signer,
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(
            aptos_framework,
            satay,
            satay_coins_account,
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
        satay_coins_account = @satay_coins,
        user = @0x47
    )]
    #[expected_failure]
    fun test_user_liquidation_insufficient(
        aptos_framework: &signer,
        satay: &signer,
        satay_coins_account: &signer,
        user: &signer,
    ){
        let vault_cap = setup_tests_with_vault_and_strategy(
            aptos_framework,
            satay,
            satay_coins_account,
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