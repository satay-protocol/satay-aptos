#[test_only]
module satay_ditto_farming::test_ditto_farming {

    use std::signer;

    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::aptos_coin;
    use aptos_framework::stake;

    use test_helpers::test_account;

    use liquidswap::router_v2;
    use liquidswap::lp_account;
    use liquidswap::liquidity_pool;
    use liquidswap::curves::{Stable};
    use liquidswap_lp::lp_coin::{LP};

    use ditto_staking::mock_ditto_staking::{Self, StakedAptos};
    use satay_ditto_farming::mock_ditto_farming::{Self, DittoFarmingCoin};
    use liquidswap::router;

    const INITIAL_LIQUIDITY: u64 = 10000000000;
    const DEPOSIT_AMOUNT: u64 = 1000000;

    #[test_only]
    fun setup_tests(
        aptos_framework: &signer,
        pool_owner: &signer,
        ditto_farming: &signer,
        ditto_staking: &signer,
        user: &signer
    ) {
        stake::initialize_for_test(aptos_framework);
        mock_ditto_staking::initialize_staked_aptos(ditto_staking);

        test_account::create_account(user);
        test_account::create_account(pool_owner);

        lp_account::initialize_lp_account(
            pool_owner,
            x"064c50436f696e010000000000000000403239383333374145433830334331323945313337414344443138463135393936323344464146453735324143373738443344354437453231454133443142454389021f8b08000000000002ff2d90c16ec3201044ef7c45e44b4eb13160c0957aeab5952af51845d1b22c8995c45860bbfdfce2b4b79dd59b9dd11e27c01b5ce8c44678d0ee75b77fff7c8bc3b8672ba53cc4715bb535aff99eb123789f2867ca27769fce58b83320c6659c0b56f19f36980e21f4beb5207a05c48d54285b4784ad7306a5e8831460add6ce486dc98014aed78e2b521d5525c3d37af034d1e869c48172fd1157fa9afd7d702776199e49d7799ef24bd314795d5c8df1d1c034c77cb883cbff23c64475012a9668dd4c3668a91c7a41caa2ea8db0da7ace3be965274550c1680ed4f615cb8bf343da3c7fa71ea541135279d0774cb7669387fc6c54b15fb48937414101000001076c705f636f696e5c1f8b08000000000002ff35c8b10980301046e13e53fc0338411027b0b0d42a84535048ee82de5521bb6b615ef5f8b2ec960ea412482e0e91488cd5fb1f501dbe1ebd8d14f3329633b24ac63aa0ef36a136d7dc0b3946fd604b00000000000000",
            x"a11ceb0b050000000501000202020a070c170823200a4305000000010003000100010001076c705f636f696e024c500b64756d6d795f6669656c6435e1873b2a1ae8c609598114c527b57d31ff5274f646ea3ff6ecad86c56d2cf8000201020100"
        );
        liquidity_pool::initialize(pool_owner);
        liquidity_pool::register<AptosCoin, StakedAptos, Stable>(pool_owner);

        let user_address = signer::address_of(user);
        coin::register<AptosCoin>(user);
        coin::register<StakedAptos>(user);


        aptos_coin::mint(aptos_framework, user_address, INITIAL_LIQUIDITY);

        let apt = coin::withdraw<AptosCoin>(user, INITIAL_LIQUIDITY);
        let stapt = mock_ditto_staking::mint_staked_aptos(INITIAL_LIQUIDITY);

        let lp = liquidity_pool::mint<AptosCoin, StakedAptos, Stable>(
            apt,
            stapt
        );
        coin::register<LP<AptosCoin, StakedAptos, Stable>>(user);
        coin::deposit(user_address, lp);

        aptos_coin::mint(aptos_framework, user_address, DEPOSIT_AMOUNT);

        mock_ditto_farming::initialize(ditto_farming);
    }

    #[test(
        aptos_framework = @aptos_framework,
        pool_owner = @liquidswap,
        ditto_farming = @satay_ditto_farming,
        ditto_staking = @ditto_staking,
        user = @0x99
    )]
    public fun test_deposit(
        aptos_framework: &signer,
        pool_owner: &signer,
        ditto_farming: &signer,
        ditto_staking: &signer,
        user: &signer
    ) {
        setup_tests(aptos_framework, pool_owner, ditto_farming, ditto_staking, user);
        mock_ditto_farming::deposit(user, DEPOSIT_AMOUNT);

        let user_farming_coin_balance = coin::balance<DittoFarmingCoin>(signer::address_of(user));
        let farming_account_lp_balance = mock_ditto_farming::get_lp_reserves_amount();

        assert!(user_farming_coin_balance > 0, 1);
        assert!(farming_account_lp_balance > 0, 2);
        assert!(farming_account_lp_balance == user_farming_coin_balance, 3);

        let (apt_reserves, stapt_reserves) = router_v2::get_reserves_size<AptosCoin, StakedAptos, Stable>();

        assert!(apt_reserves == INITIAL_LIQUIDITY + DEPOSIT_AMOUNT / 2, 2);
        assert!(stapt_reserves == INITIAL_LIQUIDITY + DEPOSIT_AMOUNT / 2, 3);
    }

    #[test(
        aptos_framework = @aptos_framework,
        pool_owner = @liquidswap,
        ditto_farming = @satay_ditto_farming,
        ditto_staking = @ditto_staking,
        user = @0x99
    )]
    public fun test_deposit_zero(
        aptos_framework: &signer,
        pool_owner: &signer,
        ditto_farming: &signer,
        ditto_staking: &signer,
        user: &signer
    ) {
        setup_tests(aptos_framework, pool_owner, ditto_farming, ditto_staking, user);
        mock_ditto_farming::deposit(user, 0);

        let user_farming_coin_balance = coin::balance<DittoFarmingCoin>(signer::address_of(user));
        let farming_account_lp_balance = mock_ditto_farming::get_lp_reserves_amount();

        assert!(user_farming_coin_balance == 0, 1);
        assert!(farming_account_lp_balance == 0, 2);
    }

    #[test(
        aptos_framework = @aptos_framework,
        pool_owner = @liquidswap,
        ditto_farming = @satay_ditto_farming,
        ditto_staking = @ditto_staking,
        user = @0x99
    )]
    public fun test_withdraw(
        aptos_framework: &signer,
        pool_owner: &signer,
        ditto_farming: &signer,
        ditto_staking: &signer,
        user: &signer
    ) {
        setup_tests(aptos_framework, pool_owner, ditto_farming, ditto_staking, user);
        mock_ditto_farming::deposit(user, DEPOSIT_AMOUNT);

        let user_farming_coin_balance = coin::balance<DittoFarmingCoin>(signer::address_of(user));
        let (
            apt_returned,
            stapt_returned
        ) = router_v2::get_reserves_for_lp_coins<AptosCoin, StakedAptos, Stable>(user_farming_coin_balance);
        let resultant_aptos_balance = apt_returned + router::get_amount_out<StakedAptos, AptosCoin, Stable>(stapt_returned);

        mock_ditto_farming::withdraw(user, user_farming_coin_balance);

        let user_aptos_balance = coin::balance<AptosCoin>(signer::address_of(user));
        assert!(user_aptos_balance == resultant_aptos_balance, 1);

    }

}
