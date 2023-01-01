#[test_only]
module satay::test_strategy_config {

    use std::signer;

    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::stake;

    use satay::satay;
    use satay::mock_strategy::{Self, MockStrategy};
    use satay::strategy_config;

    fun initialize(
        aptos_framework: &signer,
        satay: &signer
    ) {
        stake::initialize_for_test(aptos_framework);
        satay::initialize(satay);
    }

    fun create_vault(
        governance: &signer,
    ) {
        satay::new_vault<AptosCoin>(
            governance,
            0,
            0,
        );
    }

    fun initialize_with_vault(
        aptos_framework: &signer,
        satay: &signer,
    ) {
        initialize(aptos_framework, satay);
        create_vault(satay);
    }

    fun initialize_strategy(
        governance: &signer
    ) {
        mock_strategy::initialize(
            governance,
            0,
            0
        );
    }

    fun initialize_with_vault_and_strategy(
        aptos_framework: &signer,
        satay: &signer,
    ) {
        initialize_with_vault(aptos_framework, satay);
        mock_strategy::initialize(
            satay,
            0,
            0
        );
    }


    #[test(
        aptos_framework=@aptos_framework,
        satay=@satay,
    )]
    fun test_initialize_strategy(
        aptos_framework: &signer,
        satay: &signer,
    ) {
        initialize_with_vault_and_strategy(aptos_framework, satay);
    }

    #[test(
        aptos_framework=@aptos_framework,
        satay=@satay,
        non_governance=@0x1
    )]
    #[expected_failure]
    fun test_initialize_strategy_reject(
        aptos_framework: &signer,
        satay: &signer,
        non_governance: &signer,
    ) {
        initialize_with_vault(aptos_framework, satay);
        initialize_strategy(non_governance);
    }


    #[test(
        aptos_framework=@aptos_framework,
        satay=@satay,
        new_keeper=@0x1
    )]
    fun test_set_keeper(
        aptos_framework: &signer,
        satay: &signer,
        new_keeper: &signer,
    ) {
        initialize_with_vault_and_strategy(aptos_framework, satay);
        let vault_addr = satay::get_vault_address_by_id(0);
        let new_keeper_address = signer::address_of(new_keeper);
        strategy_config::set_keeper<MockStrategy>(satay, vault_addr, new_keeper_address);
        strategy_config::assert_keeper<MockStrategy>(satay, vault_addr);
        strategy_config::accept_keeper<MockStrategy>(new_keeper, vault_addr);
        strategy_config::assert_keeper<MockStrategy>(new_keeper, vault_addr);
    }

    #[test(
        aptos_framework=@aptos_framework,
        satay=@satay,
        non_keeper=@0x1
    )]
    #[expected_failure]
    fun test_set_keeper_reject(
        aptos_framework: &signer,
        satay: &signer,
        non_keeper: &signer,
    ) {
        initialize_with_vault_and_strategy(aptos_framework, satay);
        let vault_addr = satay::get_vault_address_by_id(0);
        let new_keeper_address = signer::address_of(non_keeper);
        strategy_config::set_keeper<MockStrategy>(non_keeper, new_keeper_address, vault_addr);
    }

    #[test(
        aptos_framework=@aptos_framework,
        satay=@satay,
        non_keeper=@0x1
    )]
    #[expected_failure]
    fun test_accept_keeper_reject(
        aptos_framework: &signer,
        satay: &signer,
        non_keeper: &signer,
    ) {
        initialize_with_vault_and_strategy(aptos_framework, satay);
        let vault_addr = satay::get_vault_address_by_id(0);
        strategy_config::accept_keeper<MockStrategy>(non_keeper, vault_addr);
    }
}
