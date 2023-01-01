#[test_only]
module satay_simple_staking::test_simple_staking_strategy {

    use std::signer;

    use aptos_framework::coin;
    use aptos_framework::stake;
    use aptos_framework::aptos_coin::{Self, AptosCoin};

    use liquidswap::lp_account;
    use liquidswap::liquidity_pool;
    use liquidswap::curves::Uncorrelated;

    use liquidswap_lp::lp_coin::{LP};

    use satay::satay;
    use satay::vault;

    use satay_simple_staking::staking_pool::{Self, StakingCoin};
    use satay_simple_staking::mock_simple_staking_strategy::{Self, SimpleStakingStrategy};

    use test_helpers::test_account;
    use test_coin_admin::test_coins::{Self, USDT};

    const MAX_DEBT_RATIO_BPS: u64 = 10000; // 100%

    const INITIAL_LIQUIDITY: u64 = 10000000000;
    const DEPOSIT_AMOUNT: u64 = 1000000;

    const MANAGEMENT_FEE: u64 = 200;
    const PERFOAMANCE_FEE: u64 = 500;
    const DEBT_RATIO: u64 = 5000;

    const USER_DEPOSIT_AMOUNT: u64 = 1000000;
    const REWARDS_AMOUNT: u64 = 1000000;

    const ERR_HARVEST: u64 = 1;
    const ERR_TEND: u64 = 2;

    fun setup_liquidity_pool(
        aptos_framework: &signer,
        coins_manager: &signer,
        pool_owner: &signer,
        pool_account: &signer,
    ) {
        test_coins::register_coins(coins_manager);

        test_account::create_account(pool_owner);

        lp_account::initialize_lp_account(
            pool_owner,
            x"064c50436f696e010000000000000000403239383333374145433830334331323945313337414344443138463135393936323344464146453735324143373738443344354437453231454133443142454389021f8b08000000000002ff2d90c16ec3201044ef7c45e44b4eb13160c0957aeab5952af51845d1b22c8995c45860bbfdfce2b4b79dd59b9dd11e27c01b5ce8c44678d0ee75b77fff7c8bc3b8672ba53cc4715bb535aff99eb123789f2867ca27769fce58b83320c6659c0b56f19f36980e21f4beb5207a05c48d54285b4784ad7306a5e8831460add6ce486dc98014aed78e2b521d5525c3d37af034d1e869c48172fd1157fa9afd7d702776199e49d7799ef24bd314795d5c8df1d1c034c77cb883cbff23c64475012a9668dd4c3668a91c7a41caa2ea8db0da7ace3be965274550c1680ed4f615cb8bf343da3c7fa71ea541135279d0774cb7669387fc6c54b15fb48937414101000001076c705f636f696e5c1f8b08000000000002ff35c8b10980301046e13e53fc0338411027b0b0d42a84535048ee82de5521bb6b615ef5f8b2ec960ea412482e0e91488cd5fb1f501dbe1ebd8d14f3329633b24ac63aa0ef36a136d7dc0b3946fd604b00000000000000",
            x"a11ceb0b050000000501000202020a070c170823200a4305000000010003000100010001076c705f636f696e024c500b64756d6d795f6669656c6435e1873b2a1ae8c609598114c527b57d31ff5274f646ea3ff6ecad86c56d2cf8000201020100"
        );
        liquidity_pool::initialize(pool_owner);
        liquidity_pool::register<USDT, AptosCoin, Uncorrelated>(
            pool_owner,
        );

        let pool_account_address = signer::address_of(pool_account);
        coin::register<USDT>(pool_account);
        coin::register<AptosCoin>(pool_account);

        aptos_coin::mint(aptos_framework, pool_account_address, INITIAL_LIQUIDITY);
        let usdt = test_coins::mint<USDT>(coins_manager, INITIAL_LIQUIDITY);

        let apt = coin::withdraw<AptosCoin>(pool_account, INITIAL_LIQUIDITY);
        let lp = liquidity_pool::mint<USDT, AptosCoin, Uncorrelated>(
            usdt,
            apt
        );
        coin::register<LP<USDT, AptosCoin, Uncorrelated>>(pool_account);
        coin::deposit(pool_account_address, lp);
    }

    fun setup_simple_staking_product(
        aptos_framework: &signer,
        staking_pool_admin: &signer,
    ) {
        test_account::create_account(staking_pool_admin);
        staking_pool::initialize<USDT, AptosCoin>(staking_pool_admin);
        coin::register<AptosCoin>(staking_pool_admin);
        aptos_coin::mint(aptos_framework, signer::address_of(staking_pool_admin), REWARDS_AMOUNT);
        staking_pool::deposit_rewards<AptosCoin>(staking_pool_admin, REWARDS_AMOUNT);
    }

    fun setup_vault_with_strategy(
        manager_acc: &signer,
    ) {
        satay::initialize(manager_acc);
        satay::new_vault<USDT>(
            manager_acc,
            MANAGEMENT_FEE,
            PERFOAMANCE_FEE
        );
        mock_simple_staking_strategy::initialize(
            manager_acc,
            0,
            DEBT_RATIO
        );
    }

    fun user_deposit(
        coins_admin: &signer,
        user: &signer,
    ) {
        test_account::create_account(user);
        coin::register<USDT>(user);
        let usdt = test_coins::mint<USDT>(coins_admin, DEPOSIT_AMOUNT);
        coin::deposit(signer::address_of(user), usdt);
        satay::deposit<USDT>(user, 0, DEPOSIT_AMOUNT);
    }

    #[test_only]
    fun setup_tests(
        aptos_framework: &signer,
        pool_owner: &signer,
        pool_account: &signer,
        coins_admin: &signer,
        staking_pool_admin: &signer,
        manager_acc: &signer,
        user: &signer
    ) {
        stake::initialize_for_test(aptos_framework);
        setup_liquidity_pool(aptos_framework, coins_admin, pool_owner, pool_account);
        setup_simple_staking_product(aptos_framework, staking_pool_admin);
        setup_vault_with_strategy(manager_acc);
        user_deposit(coins_admin, user);
    }

    #[test(
        aptos_framework = @aptos_framework,
        pool_owner = @liquidswap,
        pool_account = @liquidswap_pool_account,
        coins_admin = @test_coin_admin,
        manager_acc = @satay,
        staking_pool_admin = @satay_simple_staking,
        user = @0x45
    )]
    fun test_harvest(
        aptos_framework: &signer,
        pool_owner: &signer,
        pool_account: &signer,
        coins_admin: &signer,
        staking_pool_admin: &signer,
        manager_acc: &signer,
        user: &signer
    ) {
        setup_tests(
            aptos_framework,
            pool_owner,
            pool_account,
            coins_admin,
            staking_pool_admin,
            manager_acc,
            user
        );
        mock_simple_staking_strategy::harvest<AptosCoin, USDT>(manager_acc, 0);

        let vault_cap = satay::open_vault(0);
        let expected_debt = DEPOSIT_AMOUNT * DEBT_RATIO / MAX_DEBT_RATIO_BPS;
        assert!(vault::total_debt<SimpleStakingStrategy>(&vault_cap) == expected_debt, ERR_HARVEST);
        assert!(vault::balance<StakingCoin>(&vault_cap) == expected_debt, ERR_HARVEST);

        let profit_amount = 9;
        let expected_credit = profit_amount * DEBT_RATIO / MAX_DEBT_RATIO_BPS;
        assert!(vault::balance<USDT>(&vault_cap) == DEPOSIT_AMOUNT - expected_debt + profit_amount, ERR_HARVEST);
        assert!(vault::credit_available<SimpleStakingStrategy, USDT>(&vault_cap) == expected_credit, ERR_HARVEST);

        satay::close_vault(0, vault_cap);
    }

    #[test(
        aptos_framework = @aptos_framework,
        pool_owner = @liquidswap,
        pool_account = @liquidswap_pool_account,
        coins_admin = @test_coin_admin,
        manager_acc = @satay,
        staking_pool_admin = @satay_simple_staking,
        user = @0x45
    )]
    fun test_tend(
        aptos_framework: &signer,
        pool_owner: &signer,
        pool_account: &signer,
        coins_admin: &signer,
        staking_pool_admin: &signer,
        manager_acc: &signer,
        user: &signer
    ) {
        setup_tests(
            aptos_framework,
            pool_owner,
            pool_account,
            coins_admin,
            staking_pool_admin,
            manager_acc,
            user
        );
        mock_simple_staking_strategy::tend<AptosCoin, USDT>(manager_acc, 0);

        let vault_cap = satay::open_vault(0);

        let profit_amount = 9;
        let expected_credit = DEPOSIT_AMOUNT * DEBT_RATIO / MAX_DEBT_RATIO_BPS;
        assert!(vault::total_debt<SimpleStakingStrategy>(&vault_cap) == 0, ERR_HARVEST);
        assert!(vault::balance<StakingCoin>(&vault_cap) == profit_amount, ERR_HARVEST);
        assert!(vault::credit_available<SimpleStakingStrategy, USDT>(&vault_cap) == expected_credit, ERR_HARVEST);

        satay::close_vault(0, vault_cap);
    }

    #[test(
        aptos_framework = @aptos_framework,
        pool_owner = @liquidswap,
        pool_account = @liquidswap_pool_account,
        coins_admin = @test_coin_admin,
        manager_acc = @satay,
        staking_pool_admin = @satay_simple_staking,
        user = @0x45
    )]
    fun test_revoke(
        aptos_framework: &signer,
        pool_owner: &signer,
        pool_account: &signer,
        coins_admin: &signer,
        staking_pool_admin: &signer,
        manager_acc: &signer,
        user: &signer
    ) {
        setup_tests(
            aptos_framework,
            pool_owner,
            pool_account,
            coins_admin,
            staking_pool_admin,
            manager_acc,
            user
        );
        mock_simple_staking_strategy::harvest<AptosCoin, USDT>(manager_acc, 0);
        mock_simple_staking_strategy::revoke<AptosCoin, USDT>(manager_acc, 0);

        let vault_cap = satay::open_vault(0);

        assert!(vault::total_debt<SimpleStakingStrategy>(&vault_cap) == 0, ERR_HARVEST);
        assert!(vault::balance<StakingCoin>(&vault_cap) == 0, ERR_HARVEST);
        assert!(vault::credit_available<SimpleStakingStrategy, USDT>(&vault_cap) == 0, ERR_HARVEST);

        satay::close_vault(0, vault_cap);
    }
}

