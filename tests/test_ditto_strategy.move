#[test_only]
module satay::test_ditto_strategy {

    use std::signer;

    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin;
    use aptos_framework::stake;

    // use liquidswap::lp_account;
    // use liquidswap::liquidity_pool;

    use test_helpers::test_account;

    use satay::satay;
    use satay::global_config;
    use satay::ditto_strategy;
    // use ditto_staking::staked_coin::StakedAptos;
    // use liquidswap::curves::Stable;
    // use liquidswap_lp::lp_coin::LP;

    fun setup_tests(
        aptos_framework: &signer,
        manager_acc: &signer,
        pool_owner: &signer,
        user: &signer
    ) {
        global_config::initialize(manager_acc);
        stake::initialize_for_test(aptos_framework);

        test_account::create_account(user);
        test_account::create_account(manager_acc);
        test_account::create_account(pool_owner);

        // lp_account::initialize_lp_account(
        //     pool_owner,
        //     x"064c50436f696e010000000000000000403239383333374145433830334331323945313337414344443138463135393936323344464146453735324143373738443344354437453231454133443142454389021f8b08000000000002ff2d90c16ec3201044ef7c45e44b4eb13160c0957aeab5952af51845d1b22c8995c45860bbfdfce2b4b79dd59b9dd11e27c01b5ce8c44678d0ee75b77fff7c8bc3b8672ba53cc4715bb535aff99eb123789f2867ca27769fce58b83320c6659c0b56f19f36980e21f4beb5207a05c48d54285b4784ad7306a5e8831460add6ce486dc98014aed78e2b521d5525c3d37af034d1e869c48172fd1157fa9afd7d702776199e49d7799ef24bd314795d5c8df1d1c034c77cb883cbff23c64475012a9668dd4c3668a91c7a41caa2ea8db0da7ace3be965274550c1680ed4f615cb8bf343da3c7fa71ea541135279d0774cb7669387fc6c54b15fb48937414101000001076c705f636f696e5c1f8b08000000000002ff35c8b10980301046e13e53fc0338411027b0b0d42a84535048ee82de5521bb6b615ef5f8b2ec960ea412482e0e91488cd5fb1f501dbe1ebd8d14f3329633b24ac63aa0ef36a136d7dc0b3946fd604b00000000000000",
        //     x"a11ceb0b050000000501000202020a070c170823200a4305000000010003000100010001076c705f636f696e024c500b64756d6d795f6669656c6435e1873b2a1ae8c609598114c527b57d31ff5274f646ea3ff6ecad86c56d2cf8000201020100"
        // );
        // liquidity_pool::initialize(pool_owner);
        // liquidity_pool::register<AptosCoin, StakedAptos, Stable>(
        //     pool_owner,
        // );

        let user_address = signer::address_of(user);
        coin::register<AptosCoin>(user);
        // coin::register<StakedAptos>(user);

        aptos_coin::mint(aptos_framework, user_address, 100000);

        // let aptos = coin::withdraw<AptosCoin>(user, 100000);
        // let st_apt = coin::withdraw<StakedAptos>(user, 10000);
        // let lp = liquidity_pool::mint<AptosCoin, StakedAptos, Stable>(
        //     aptos,
        //     st_apt
        // );
        // coin::register<LP<AptosCoin, StakedAptos, Stable>>(user);
        // coin::deposit(user_address, lp);
        //
        // aptos_coin::mint(aptos_framework, user_address, 100000);
    }

    #[test_only]
    fun setup_strategy_vault(
        aptos_framework: &signer,
        manager_acc: &signer,
        pool_owner: &signer,
        user: &signer
    ) {
        setup_tests(aptos_framework, manager_acc, pool_owner, user);
        satay::initialize(manager_acc);
        satay::new_vault<AptosCoin>(manager_acc, b"aptos_vault", 200, 5000);
        ditto_strategy::initialize(manager_acc, 0,  1000);
        satay::deposit<AptosCoin>(user, signer::address_of(manager_acc), 0, 1000);
    }

    #[test(
        aptos_framework = @aptos_framework,
        manager_acc = @satay,
        pool_owner = @liquidswap,
        user = @0x45
    )]
    fun test_harvest(
        aptos_framework: &signer,
        manager_acc: &signer,
        pool_owner: &signer,
        user: &signer
    ) {
        setup_strategy_vault(aptos_framework, manager_acc, pool_owner, user);
        // ditto_strategy::harvest(manager_acc, 0);
    }
}

