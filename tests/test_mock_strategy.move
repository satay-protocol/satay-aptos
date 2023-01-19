#[test_only]
module satay::test_mock_strategy {

    use std::signer;

    use aptos_framework::account;
    use aptos_framework::stake;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin;

    use satay::vault_coin_account;
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
        vault_coin_account::initialize_satay_account(
            satay,
            x"0e53617461795661756c74436f696e020000000000000000404442334638364131454231354432454538373446303132424334384439373142373336344135453630354646303432353235434633383145383930333445334587021f8b08000000000002ff2d90cd6ec3201084ef3c45e44b4eb621fea5524f3df714a997c8b216583b28365880dde6ed0b6d6e3b3bb3f3497bdb403e60c6811858f1f47e3a5f21c0f30bf6257c586dcee440e7b535c962052de899ecdbec40e1b8d945cb673432bdae7b00b16046c80d9472e83dfa81f8d4351ea96c94b12d65e90f6d8077bc6f812b5a3159376d87ac111def0436ace58cca498a9a356dc52e757fc149b6c0b8a45051c9eb3e41141eb9c20d8d422335fae2d31e780d6ad16220b30e89740f61f36f6519e57d1785b46b095bb03e5f40f8d728adc3220632e2f048472b6863306abf0ba55d5afd27d708282717bff46ddda34c32f77fc0ec173b2d8c9145010000010a7661756c745f636f696e5d1f8b08000000000002ff45c8310a80300c40d13da7c8398a38e81d5c4ba80585b6119308527a77dbc93f7d5ee6dd524421a5d73f64497de0b338f73f56c09ee86d41711bbe769eae838a72c685240e98b13668f00109fb6b9d5200000000000000",
            x"a11ceb0b05000000050100020202060708210829200a490500000001000100010a7661756c745f636f696e095661756c74436f696e0b64756d6d795f6669656c6405a97986a9d031c4567e15b797be516910cfcb4156312482efc6a19c0a30c948000201020100"
        );
        satay::initialize(satay);
        satay::new_vault<AptosCoin>(
            satay,
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
