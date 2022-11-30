#[test_only]
module satay::test_global_config {

    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::stake;

    use satay::satay;
    use satay::mock_strategy::{Self, MockStrategy};
    use satay::global_config;
    use std::signer;

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
            b"aptos_vault",
            0,
            0
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
        satay=@satay
    )]
    fun test_initialize(
        aptos_framework: &signer,
        satay: &signer,
    ) {
        initialize(aptos_framework, satay);
    }

    #[test(
        aptos_framework=@aptos_framework,
        non_satay=@0x1
    )]
    #[expected_failure]
    fun test_initialize_reject(
        aptos_framework: &signer,
        non_satay: &signer,
    ) {
        initialize(aptos_framework, non_satay);
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
        new_dao_admin=@0x1
    )]
    fun test_set_dao_admin(
        aptos_framework: &signer,
        satay: &signer,
        new_dao_admin: &signer,
    ) {
        initialize(aptos_framework, satay);
        let new_dao_admin_address = signer::address_of(new_dao_admin);
        global_config::set_dao_admin(satay, new_dao_admin_address);
        global_config::assert_dao_admin(satay);
        global_config::accept_dao_admin(new_dao_admin);
        global_config::assert_dao_admin(new_dao_admin);
    }

    #[test(
        aptos_framework=@aptos_framework,
        satay=@satay,
        non_dao_admin=@0x1
    )]
    #[expected_failure]
    fun test_set_dao_admin_reject(
        aptos_framework: &signer,
        satay: &signer,
        non_dao_admin: &signer,
    ) {
        initialize(aptos_framework, satay);
        let new_dao_admin_address = signer::address_of(non_dao_admin);
        global_config::set_dao_admin(non_dao_admin, new_dao_admin_address);
    }

    #[test(
        aptos_framework=@aptos_framework,
        satay=@satay,
        non_dao_admin=@0x1
    )]
    #[expected_failure]
    fun test_accept_dao_admin_reject(
        aptos_framework: &signer,
        satay: &signer,
        non_dao_admin: &signer,
    ) {
        initialize(aptos_framework, satay);
        global_config::accept_dao_admin(non_dao_admin);
    }

    #[test(
        aptos_framework=@aptos_framework,
        satay=@satay,
        new_governance=@0x1
    )]
    fun test_set_governance(
        aptos_framework: &signer,
        satay: &signer,
        new_governance: &signer,
    ) {
        initialize(aptos_framework, satay);
        let new_governance_address = signer::address_of(new_governance);
        global_config::set_governance(satay, new_governance_address);
        global_config::assert_governance(satay);
        global_config::accept_governance(new_governance);
        global_config::assert_governance(new_governance);
    }

    #[test(
        aptos_framework=@aptos_framework,
        satay=@satay,
        non_governance=@0x1
    )]
    #[expected_failure]
    fun test_set_governance_reject(
        aptos_framework: &signer,
        satay: &signer,
        non_governance: &signer,
    ) {
        initialize(aptos_framework, satay);
        let new_governance_address = signer::address_of(non_governance);
        global_config::set_governance(non_governance, new_governance_address);
    }

    #[test(
        aptos_framework=@aptos_framework,
        satay=@satay,
        non_governance=@0x1
    )]
    #[expected_failure]
    fun test_accept_governance_reject(
        aptos_framework: &signer,
        satay: &signer,
        non_governance: &signer,
    ) {
        initialize(aptos_framework, satay);
        global_config::accept_governance(non_governance);
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
        let new_vault_manager_address = signer::address_of(new_vault_manager);
        global_config::set_vault_manager<AptosCoin>(satay, new_vault_manager_address);
        global_config::assert_vault_manager<AptosCoin>(satay);
        global_config::accept_vault_manager<AptosCoin>(new_vault_manager);
        global_config::assert_vault_manager<AptosCoin>(new_vault_manager);
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
        let new_vault_manager_address = signer::address_of(non_vault_manager);
        global_config::set_vault_manager<AptosCoin>(non_vault_manager, new_vault_manager_address);
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
        global_config::accept_vault_manager<AptosCoin>(non_vault_manager);
    }

    #[test(
        aptos_framework=@aptos_framework,
        satay=@satay,
        new_strategist=@0x1
    )]
    fun test_set_strategist(
        aptos_framework: &signer,
        satay: &signer,
        new_strategist: &signer,
    ) {
        initialize_with_vault_and_strategy(aptos_framework, satay);
        let new_strategist_address = signer::address_of(new_strategist);
        global_config::set_strategist<MockStrategy, AptosCoin>(satay, new_strategist_address);
        global_config::assert_strategist<MockStrategy, AptosCoin>(satay);
        global_config::accept_strategist<MockStrategy>(new_strategist);
        global_config::assert_strategist<MockStrategy, AptosCoin>(new_strategist);
    }

    #[test(
        aptos_framework=@aptos_framework,
        satay=@satay,
        non_strategist=@0x1
    )]
    #[expected_failure]
    fun test_set_strategist_reject(
        aptos_framework: &signer,
        satay: &signer,
        non_strategist: &signer,
    ) {
        initialize_with_vault_and_strategy(aptos_framework, satay);
        let new_strategist_address = signer::address_of(non_strategist);
        global_config::set_strategist<MockStrategy, AptosCoin>(non_strategist, new_strategist_address);
    }

    #[test(
        aptos_framework=@aptos_framework,
        satay=@satay,
        non_strategist=@0x1
    )]
    #[expected_failure]
    fun test_accept_strategist_reject(
        aptos_framework: &signer,
        satay: &signer,
        non_strategist: &signer,
    ) {
        initialize_with_vault_and_strategy(aptos_framework, satay);
        global_config::accept_strategist<MockStrategy>(non_strategist);
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
        let new_keeper_address = signer::address_of(new_keeper);
        global_config::set_keeper<MockStrategy, AptosCoin>(satay, new_keeper_address);
        global_config::assert_keeper<MockStrategy, AptosCoin>(satay);
        global_config::accept_keeper<MockStrategy>(new_keeper);
        global_config::assert_keeper<MockStrategy, AptosCoin>(new_keeper);
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
        let new_keeper_address = signer::address_of(non_keeper);
        global_config::set_keeper<MockStrategy, AptosCoin>(non_keeper, new_keeper_address);
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
        global_config::accept_keeper<MockStrategy>(non_keeper);
    }

    // #[test(
    //     aptos_framework=@aptos_framework,
    //     satay=@satay,
    //     new_governance=@0x1
    // )]
    // fun test_new_vault_after_governance_change(
    //     aptos_framework: &signer,
    //     satay: &signer,
    //     new_governance: &signer,
    // ) {
    //     initialize(aptos_framework, satay);
    //     let new_governance_address = signer::address_of(new_governance);
    //     global_config::set_governance(satay, new_governance_address);
    //     global_config::accept_governance(new_governance);
    //     create_vault(new_governance);
    //     global_config::assert_vault_manager<AptosCoin>(new_governance);
    // }
}
