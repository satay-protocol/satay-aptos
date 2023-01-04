#[test_only]
module satay::test_dao_storage {

    use std::signer;

    use aptos_framework::coin;
    use aptos_framework::account;

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
