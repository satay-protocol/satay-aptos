#[test_only]
module ditto_staking::test_ditto_staking {

    use std::signer;

    use aptos_framework::stake;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::{Self, AptosCoin};

    use ditto_staking::mock_ditto_staking::{Self, StakedAptos};

    const ERR_INCORRECT_STAPT_AMOUNT: u64 = 2;
    const ERR_INCORRECT_APT_AMOUNT: u64 = 3;

    fun setup_tests(
        aptos_framework: &signer,
        ditto: &signer,
        user: &signer
    ) {
        stake::initialize_for_test(aptos_framework);
        mock_ditto_staking::initialize_staked_aptos(ditto);

        let user_addr = signer::address_of(user);
        account::create_account_for_test(user_addr);

        coin::register<AptosCoin>(user);
        aptos_coin::mint(aptos_framework, user_addr, 1000);
    }

    #[test(
        ditto=@ditto_staking,
        aptos_framework=@aptos_framework,
        user=@0x11
    )]
    public fun test_initialize_staked_aptos(
        aptos_framework: &signer,
        ditto: &signer,
        user: &signer,
    ){
        setup_tests(aptos_framework, ditto, user);
    }

    #[test(
        ditto=@0x12,
        aptos_framework=@aptos_framework,
        user=@0x11
    )]
    #[expected_failure]
    public fun test_initialize_staked_aptos_reject(
        aptos_framework: &signer,
        ditto: &signer,
        user: &signer,
    ){
        setup_tests(aptos_framework, ditto, user);
    }

    #[test(
        ditto=@ditto_staking,
        aptos_framework=@aptos_framework,
        user=@0x11
    )]
    public fun test_stake_aptos(
        ditto: &signer,
        aptos_framework: &signer,
        user: &signer
    ) {
        setup_tests(aptos_framework, ditto, user);
        mock_ditto_staking::stake(user, 1000);
        assert!(coin::balance<StakedAptos>(signer::address_of(user)) == 1000, ERR_INCORRECT_STAPT_AMOUNT);
    }

    #[test(
        ditto=@ditto_staking,
        aptos_framework=@aptos_framework,
        user=@0x11
    )]
    public fun test_unstake_aptos(
        ditto: &signer,
        aptos_framework: &signer,
        user: &signer
    ) {
        setup_tests(aptos_framework, ditto, user);
        mock_ditto_staking::stake(user, 1000);
        mock_ditto_staking::unstake(user, 1000);
        assert!(coin::balance<AptosCoin>(signer::address_of(user)) == 1000, ERR_INCORRECT_APT_AMOUNT);
    }
}