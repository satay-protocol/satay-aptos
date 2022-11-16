#[test_only]
module satay_ditto_rewards::test_ditto_rewards {
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use test_helpers::test_account;
    use aptos_framework::stake;
    use std::signer;
    use aptos_framework::coin;
    use satay_ditto_rewards::ditto_rewards_product;

    fun setup_tests(
        aptos_framework: &signer,
        user: &signer,
        admin: &signer
    ) {
        test_account::create_account(user);
        test_account::create_account(admin);
        stake::initialize_for_test(aptos_framework);

        let user_address = signer::address_of(user);
        coin::register<AptosCoin>(user);

        aptos_coin::mint(aptos_framework, user_address, 100000);
        ditto_rewards_product::init_fee_structure(admin, 300);
    }

    #[test(
        aptos_framework = @aptos_framework,
        user = @0x12,
        admin = @0x11
    )]
    fun test_fee_on_deposit(
        aptos_framework: &signer,
        user: &signer,
        admin: &signer
    ) {
        setup_tests(aptos_framework, user, admin);
        let coins = coin::withdraw<AptosCoin>(user, 2000);
        let reduced_coins = ditto_rewards_product::charge_fee_test(coins);
        assert!(coin::value(&reduced_coins) == 2000 / 100 * (100-3), 0);
        coin::deposit(signer::address_of(user), reduced_coins);
    }
}
