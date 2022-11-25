#[test_only]
module satay::test_dao_storage {

    use std::signer;

    use aptos_framework::coin;

    use test_coin_admin::test_coins::{USDT};
    use test_helpers::test_account;
    use test_coin_admin::test_coins;

    use satay::satay;
    use satay::global_config;
    use satay::dao_storage;

    const ENO_STORAGE: u64 = 401;
    const ERR_DEPOSIT: u64 = 402;
    const ERR_WITHDRAW: u64 = 403;

    #[test(owner=@satay)]
    fun test_register(owner: &signer) {
        test_account::create_account(owner);
        dao_storage::register<USDT>(owner);
        assert!(dao_storage::has_storage<USDT>(signer::address_of(owner)) == true, ENO_STORAGE);
    }

    #[test]
    fun test_deposit() {
        let owner = test_coins::create_admin_with_coins();
        dao_storage::register<USDT>(&owner);

        let owner_address = signer::address_of(&owner);

        let usdt_coins = test_coins::mint<USDT>(&owner, 100);
        dao_storage::deposit<USDT>(owner_address, usdt_coins);
        assert!(dao_storage::balance<USDT>(owner_address) == 100, ERR_DEPOSIT);
    }

    #[test(dao_admin=@0x64, satay=@satay)]
    fun test_withdraw(dao_admin: &signer, satay: &signer) {
        satay::initialize(satay);
        test_account::create_account(dao_admin);

        let owner = test_coins::create_admin_with_coins();
        dao_storage::register<USDT>(&owner);

        let owner_address = signer::address_of(&owner);

        let usdt_coins = test_coins::mint<USDT>(&owner, 1000);
        dao_storage::deposit<USDT>(owner_address, usdt_coins);

        global_config::set_dao_admin(satay, signer::address_of(dao_admin));
        global_config::accept_dao_admin(dao_admin);

        coin::register<USDT>(dao_admin);
        dao_storage::withdraw<USDT>(dao_admin, signer::address_of(&owner), 200);
        assert!(coin::balance<USDT>(signer::address_of(dao_admin)) == 200, ERR_WITHDRAW);
        assert!(dao_storage::balance<USDT>(owner_address) == 800, ERR_WITHDRAW);
    }
}
