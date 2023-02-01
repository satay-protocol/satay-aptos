#[test_only]
module satay::test_global_config {

    use std::signer;

    use aptos_framework::stake;

    use satay::vault_coin_account;
    use satay::satay;
    use satay::global_config;
    use aptos_framework::aptos_coin::AptosCoin;

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
        new_governance=@0x1
    )]
    fun test_new_vault_after_governance_change(
        aptos_framework: &signer,
        satay: &signer,
        new_governance: &signer,
    ) {
        initialize(aptos_framework, satay);
        let new_governance_address = signer::address_of(new_governance);
        global_config::set_governance(satay, new_governance_address);
        global_config::accept_governance(new_governance);

        satay::new_vault<AptosCoin>(new_governance, 0, 0);

    }


}
