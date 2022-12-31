#[test_only]
module satay::test_vault_config {

    use std::signer;

    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::stake;

    use satay::satay;
    use satay::vault_config;

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
            0
        )
    }

    fun initialize_with_vault(
        aptos_framework: &signer,
        satay: &signer,
    ) {
        initialize(aptos_framework, satay);
        create_vault(satay)
    }

    #[test(
        aptos_framework=@aptos_framework,
        satay=@satay,
    )]
    fun test_create_vault(
        aptos_framework: &signer,
        satay: &signer,
    ) {
        initialize_with_vault(aptos_framework, satay);
    }

    #[test(
        aptos_framework=@aptos_framework,
        satay=@satay,
        non_governance=@0x1
    )]
    #[expected_failure]
    fun test_create_vault_reject(
        aptos_framework: &signer,
        satay: &signer,
        non_governance: &signer,
    ) {
        initialize(aptos_framework, satay);
        create_vault(non_governance);
    }

    #[test(
        aptos_framework=@aptos_framework,
        satay=@satay,
        new_vault_manager=@0x1
    )]
    fun test_set_vault_manager(
        aptos_framework: &signer,
        satay: &signer,
        new_vault_manager: &signer,
    ) {
        initialize_with_vault(aptos_framework, satay);
        let vault_addr = satay::get_vault_address_by_id(0);
        let new_vault_manager_address = signer::address_of(new_vault_manager);
        vault_config::set_vault_manager(satay, vault_addr, new_vault_manager_address);
        vault_config::assert_vault_manager(satay, vault_addr);
        vault_config::accept_vault_manager(new_vault_manager, vault_addr);
        vault_config::assert_vault_manager(new_vault_manager, vault_addr);
    }

    #[test(
        aptos_framework=@aptos_framework,
        satay=@satay,
        non_vault_manager=@0x1
    )]
    #[expected_failure]
    fun test_set_vault_manager_reject(
        aptos_framework: &signer,
        satay: &signer,
        non_vault_manager: &signer,
    ) {
        initialize_with_vault(aptos_framework, satay);
        let vault_addr = satay::get_vault_address_by_id(0);
        let new_vault_manager_address = signer::address_of(non_vault_manager);
        vault_config::set_vault_manager(non_vault_manager, vault_addr, new_vault_manager_address);
    }

    #[test(
        aptos_framework=@aptos_framework,
        satay=@satay,
        non_vault_manager=@0x1
    )]
    #[expected_failure]
    fun test_accept_vault_manager_reject(
        aptos_framework: &signer,
        satay: &signer,
        non_vault_manager: &signer,
    ) {
        initialize_with_vault(aptos_framework, satay);
        let vault_addr = satay::get_vault_address_by_id(0);
        vault_config::accept_vault_manager(non_vault_manager, vault_addr);
    }
}
