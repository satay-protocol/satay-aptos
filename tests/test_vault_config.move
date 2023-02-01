#[test_only]
module satay::test_vault_config {

    use std::signer;

    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::stake;

    use satay::vault_coin_account;
    use satay::satay;
    use satay::vault_config;

    fun initialize(
        aptos_framework: &signer,
        satay: &signer
    ) {
        stake::initialize_for_test(aptos_framework);
        vault_coin_account::initialize_satay_account(
            satay,
            x"0e53617461795661756c74436f696e020000000000000000404442334638364131454231354432454538373446303132424334384439373142373336344135453630354646303432353235434633383145383930333445334587021f8b08000000000002ff2d90cd6ec3201084ef3c45e44b4eb621fea5524f3df714a997c8b216583b28365880dde6ed0b6d6e3b3bb3f3497bdb403e60c6811858f1f47e3a5f21c0f30bf6257c586dcee440e7b535c962052de899ecdbec40e1b8d945cb673432bdae7b00b16046c80d9472e83dfa81f8d4351ea96c94b12d65e90f6d8077bc6f812b5a3159376d87ac111def0436ace58cca498a9a356dc52e757fc149b6c0b8a45051c9eb3e41141eb9c20d8d422335fae2d31e780d6ad16220b30e89740f61f36f6519e57d1785b46b095bb03e5f40f8d728adc3220632e2f048472b6863306abf0ba55d5afd27d708282717bff46ddda34c32f77fc0ec173b2d8c9145010000010a7661756c745f636f696e5d1f8b08000000000002ff45c8310a80300c40d13da7c8398a38e81d5c4ba80585b6119308527a77dbc93f7d5ee6dd524421a5d73f64497de0b338f73f56c09ee86d41711bbe769eae838a72c685240e98b13668f00109fb6b9d5200000000000000",
            x"a11ceb0b05000000050100020202060708210829200a490500000001000100010a7661756c745f636f696e095661756c74436f696e0b64756d6d795f6669656c6405a97986a9d031c4567e15b797be516910cfcb4156312482efc6a19c0a30c948000201020100"
        );
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
