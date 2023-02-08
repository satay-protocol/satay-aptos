#[test_only]
module satay::test_global_config {

    use std::signer;

    use aptos_framework::stake;
    use aptos_framework::aptos_coin::AptosCoin;

    use satay::satay_account;
    use satay::satay;
    use satay::global_config;

    fun initialize(
        aptos_framework: &signer,
        satay: &signer
    ) {
        stake::initialize_for_test(aptos_framework);
        satay_account::initialize_satay_account(
            satay,
            x"0a5361746179436f696e73020000000000000000403130333837434146364441363631433033364236443031384642423035433530433231374130373745453136413043344338353633373844393938454533414297021f8b08000000000002ff2d903f6fc32010c5773e45e425536c30d8984a9d3a77ca184511704782621b0bb0db7cfb9ab6dbfd79ef774f7759b47dea3b5ec9ac273cbc1f8e679df5eb23f8391dc98631f9309731ab694d8f645dee5103de96307afbda17959fa6356b336245c84503444c09d395a4c2b9d9022a32facd1ce5928343c1ac108a1a66a5b14ab79c0288ce7568a1730cd5c006cd5bca15db0d52236b1903c50b1f703b012e3803ced663aa3fc386e70ca3375772f7b95c7ae4bca4b7a6d9dbc76a6a1ba6462f39a4d3a84dfa2f6d8858ef828a44dc8a093a6994341aa9e985e9991c7ae55ae7da1ea550d8513e8861107d45d26ac0c7e2f9434d7b82c6c5fd7b5f213e9bd29ed26fa2ea0739f85a445d010000020d73747261746567795f636f696ebf011f8b08000000000002ff4d8f410ec2201045f79c620e60d23d312ef4081ab7cd0863db4881c060429ade5d2068246c18fe7fffcf300c303ba323f04c103924c590226978ba00570ec834e58b5b2c94db34c898c1a37ae14462287e4ddeb85c2c8fdc1481a24b4111a0522e590615a860742534b7946f4c864755b0631789d5e9643abefd442963cf6f6fd8049453136bcabd225ab1892c8545f5f64dd417f9ef7ff4335a76eb6f78cb9e0ef09d9e3152959d60dbc52e3ebb49a3451801000000000a7661756c745f636f696eaf011f8b08000000000002ff4d8f310ec2300c45f79cc237c88e1003307002d6cab8a6ad48e32a7190aaaa77278922c0f2643fffff6dad859bb83e828e0c5143228514b987a704b863727a91c943ee0aa0e20a0bd20b0736361f5f7971b266feb156227094148801892479050a8c9af759a15e1f0eefa2da5196ed1a6466e9936bf27513ff31d80ce42a76c5e2976a60cf61a296bb42ed852f735c46f42a339c3172199c60dbcd6e3e1cb58cd7f900000000000000",
            vector[
                x"a11ceb0b0500000005010002020208070a270831200a5105000000010002000100010d73747261746567795f636f696e0c5374726174656779436f696e0b64756d6d795f6669656c641f0373dfe41c4490b1c7bc9a230dd45f5ecd5f1e9818a3203910377ae1211d93000201020100",
                x"a11ceb0b05000000050100020202060708210829200a490500000001000100010a7661756c745f636f696e095661756c74436f696e0b64756d6d795f6669656c641f0373dfe41c4490b1c7bc9a230dd45f5ecd5f1e9818a3203910377ae1211d93000201020100"
            ],

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
