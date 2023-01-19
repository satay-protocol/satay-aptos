#[test_only]
module satay::test_dao_storage {

    use std::signer;

    use aptos_framework::coin;
    use aptos_framework::account;

    use satay::vault_coin_account;
    use satay::satay;
    use satay::global_config;
    use satay::dao_storage;
    use satay::coins::{Self, USDT};

    const ENO_STORAGE: u64 = 401;
    const ERR_DEPOSIT: u64 = 402;
    const ERR_WITHDRAW: u64 = 403;

    fun setup_tests(
        satay: &signer,
        vault: &signer,
    ) {
        vault_coin_account::initialize_satay_account(
            satay,
            x"0e53617461795661756c74436f696e020000000000000000404442334638364131454231354432454538373446303132424334384439373142373336344135453630354646303432353235434633383145383930333445334587021f8b08000000000002ff2d90cd6ec3201084ef3c45e44b4eb621fea5524f3df714a997c8b216583b28365880dde6ed0b6d6e3b3bb3f3497bdb403e60c6811858f1f47e3a5f21c0f30bf6257c586dcee440e7b535c962052de899ecdbec40e1b8d945cb673432bdae7b00b16046c80d9472e83dfa81f8d4351ea96c94b12d65e90f6d8077bc6f812b5a3159376d87ac111def0436ace58cca498a9a356dc52e757fc149b6c0b8a45051c9eb3e41141eb9c20d8d422335fae2d31e780d6ad16220b30e89740f61f36f6519e57d1785b46b095bb03e5f40f8d728adc3220632e2f048472b6863306abf0ba55d5afd27d708282717bff46ddda34c32f77fc0ec173b2d8c9145010000010a7661756c745f636f696e5d1f8b08000000000002ff45c8310a80300c40d13da7c8398a38e81d5c4ba80585b6119308527a77dbc93f7d5ee6dd524421a5d73f64497de0b338f73f56c09ee86d41711bbe769eae838a72c685240e98b13668f00109fb6b9d5200000000000000",
            x"a11ceb0b05000000050100020202060708210829200a490500000001000100010a7661756c745f636f696e095661756c74436f696e0b64756d6d795f6669656c6405a97986a9d031c4567e15b797be516910cfcb4156312482efc6a19c0a30c948000201020100"
        );
        satay::initialize(satay);
        account::create_account_for_test(signer::address_of(satay));
        account::create_account_for_test(signer::address_of(vault));
        coins::register_coins(satay);
    }

    #[test(
        satay=@satay,
        vault=@0x64,
    )]
    fun test_register(
        satay: &signer,
        vault: &signer,
    ) {
        setup_tests(satay, vault);
        dao_storage::register<USDT>(satay);
        assert!(dao_storage::has_storage<USDT>(signer::address_of(satay)), ENO_STORAGE);
    }

    #[test(
        satay=@satay,
        vault=@0x64,
    )]
    fun test_deposit(
        satay: &signer,
        vault: &signer,
    ) {
        setup_tests(satay, vault);

        dao_storage::register<USDT>(vault);
        let vault_address = signer::address_of(vault);

        let amount = 100;
        let usdt_coins =  coins::mint<USDT>(satay, amount);
        dao_storage::deposit<USDT>(vault_address, usdt_coins);
        assert!(dao_storage::balance<USDT>(vault_address) == amount, ERR_DEPOSIT);
    }

    #[test(
        satay=@satay,
        vault=@0x63,
        dao_admin=@0x64
    )]
    fun test_withdraw(
        satay: &signer,
        vault: &signer,
        dao_admin: &signer
    ) {
        setup_tests(satay, vault);

        dao_storage::register<USDT>(vault);

        let vault_address = signer::address_of(vault);
        let amount = 100;
        let usdt_coins = coins::mint<USDT>(satay, amount);
        dao_storage::deposit<USDT>(vault_address, usdt_coins);

        account::create_account_for_test(signer::address_of(dao_admin));
        global_config::set_dao_admin(satay, signer::address_of(dao_admin));
        global_config::accept_dao_admin(dao_admin);

        coin::register<USDT>(dao_admin);
        let witdraw_amount = 40;
        dao_storage::withdraw<USDT>(dao_admin, vault_address, witdraw_amount);
        assert!(coin::balance<USDT>(signer::address_of(dao_admin)) == witdraw_amount, ERR_WITHDRAW);
        assert!(dao_storage::balance<USDT>(vault_address) == amount - witdraw_amount, ERR_WITHDRAW);
    }

    #[test(
        satay=@satay,
        vault=@0x63,
        dao_admin=@0x64
    )]
    #[expected_failure]
    fun test_withdraw_non_dao_admin(
        satay: &signer,
        vault: &signer,
        dao_admin: &signer
    ) {
        setup_tests(satay, vault);

        dao_storage::register<USDT>(vault);

        let vault_address = signer::address_of(vault);
        let amount = 100;
        let usdt_coins = coins::mint<USDT>(satay, amount);
        dao_storage::deposit<USDT>(vault_address, usdt_coins);

        account::create_account_for_test(signer::address_of(dao_admin));
        coin::register<USDT>(dao_admin);
        let witdraw_amount = 40;
        dao_storage::withdraw<USDT>(dao_admin, vault_address, witdraw_amount);
    }
}
