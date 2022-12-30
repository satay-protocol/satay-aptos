#[test_only]
module satay::test_mock_strategy {

    use std::signer;

    use aptos_framework::account;
    use aptos_framework::stake;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin;

    use satay::vault;
    use satay::satay;
    use satay::mock_strategy::{Self, MockStrategy};
    use satay::aptos_wrapper_product::{WrappedAptos};
    use satay::aptos_wrapper_product;

    const INITIAL_DEBT_RATIO: u64 = 10000;
    const MAX_DEBT_RATIO: u64 = 10000;
    const DEPOSIT_AMOUNT: u64 = 1000;

    const ERR_INITIALIZE: u64 = 1;
    const ERR_HARVEST: u64 = 2;
    const ERR_REVOKE: u64 = 3;

    fun initialize_vault_with_deposit(
        aptos_framework: &signer,
        satay: &signer,
        user: &signer,
    ) {
        stake::initialize_for_test(aptos_framework);
        satay::initialize(satay);
        satay::new_vault<AptosCoin>(
            satay,
            b"aptos_vault",
            0,
            0
        );

        account::create_account_for_test(signer::address_of(user));
        coin::register<AptosCoin>(user);
        aptos_coin::mint(aptos_framework, signer::address_of(user), DEPOSIT_AMOUNT);
        satay::deposit<AptosCoin>( user, 0, DEPOSIT_AMOUNT);
    }

    fun initialize_with_strategy(
        aptos_framework: &signer,
        satay: &signer,
        user: &signer,
    ) {
        initialize_vault_with_deposit(aptos_framework, satay, user);
        aptos_wrapper_product::initialize(satay);
        mock_strategy::initialize(
            satay,
            0,
            INITIAL_DEBT_RATIO
        );
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        user = @0x47
    )]
    fun test_initialize_strategy(aptos_framework: &signer, satay: &signer, user: &signer) {
        initialize_vault_with_deposit(aptos_framework, satay, user);
        mock_strategy::initialize(
            satay,
            0,
            INITIAL_DEBT_RATIO
        );

        let vault_cap = satay::open_vault(0);
        assert!(vault::has_strategy<MockStrategy>(&vault_cap), ERR_INITIALIZE);
        assert!(vault::has_coin<WrappedAptos>(&vault_cap), ERR_INITIALIZE);
        assert!(vault::credit_available<MockStrategy, AptosCoin>(&vault_cap) == DEPOSIT_AMOUNT, ERR_INITIALIZE);
        satay::close_vault(0, vault_cap);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        user = @0x47
    )]
    fun test_harvest(aptos_framework: &signer, satay: &signer, user: &signer) {
        initialize_with_strategy(aptos_framework, satay, user);
        mock_strategy::harvest(satay, 0);

        let vault_cap = satay::open_vault(0);
        assert!(vault::credit_available<MockStrategy, AptosCoin>(&vault_cap) == 0, ERR_HARVEST);
        assert!(vault::balance<AptosCoin>(&vault_cap) == 0, ERR_HARVEST);
        assert!(vault::balance<WrappedAptos>(&vault_cap) == DEPOSIT_AMOUNT, ERR_HARVEST);
        satay::close_vault(0, vault_cap);
    }

    #[test(
        aptos_framework = @aptos_framework,
        satay = @satay,
        user = @0x47
    )]
    fun test_revoke(aptos_framework: &signer, satay: &signer, user: &signer) {
        initialize_with_strategy(aptos_framework, satay, user);
        mock_strategy::harvest(satay, 0);
        mock_strategy::revoke(satay, 0);

        let vault_cap = satay::open_vault(0);
        assert!(vault::credit_available<MockStrategy, AptosCoin>(&vault_cap) == 0, ERR_REVOKE);
        assert!(vault::balance<AptosCoin>(&vault_cap) == DEPOSIT_AMOUNT, ERR_HARVEST);
        assert!(vault::balance<WrappedAptos>(&vault_cap) == 0, ERR_HARVEST);
        satay::close_vault(0, vault_cap);
    }
}
