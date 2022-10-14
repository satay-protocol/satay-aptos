#[test_only]
module satay::test_dao_storage {
    use satay::dao_storage::{register, has_storage, deposit, get_coin_value, withdraw};
    use test_coin_admin::test_coins::{USDT};
    use test_helpers::test_account;
    use test_coin_admin::test_coins;
    use aptos_framework::coin;
    use std::signer;
    use satay::global_config;

    const ENO_STORAGE: u64 = 401;
    const ERR_DEPOSIT: u64 = 402;
    const ERR_WITHDRAW: u64 = 403;

    #[test(owner=@satay)]
    fun test_register(owner: &signer) {
        test_account::create_account(owner);
        register<USDT>(owner);
        assert!(has_storage<USDT>(owner) == true, ENO_STORAGE);
    }

    #[test]
    fun test_deposit() {
        let owner = test_coins::create_admin_with_coins();
        register<USDT>(&owner);

        let usdt_coins = test_coins::mint<USDT>(&owner, 100);
        deposit<USDT>(signer::address_of(&owner), usdt_coins);
        assert!(get_coin_value<USDT>(&owner) == 100, ERR_DEPOSIT);
    }

    #[test(dao_admin=@satay_dao_admin, satay=@satay)]
    fun test_withdraw(dao_admin: &signer, satay: &signer) {
        global_config::initialize(satay);
        let owner = test_coins::create_admin_with_coins();
        register<USDT>(&owner);

        let usdt_coins = test_coins::mint<USDT>(&owner, 1000);
        deposit<USDT>(signer::address_of(&owner), usdt_coins);

        let withdrawn_coin = withdraw<USDT>(dao_admin, signer::address_of(&owner), 200);
        assert!(coin::value(&withdrawn_coin) == 200, ERR_WITHDRAW);
        test_coins::burn(&owner, withdrawn_coin);
        assert!(get_coin_value<USDT>(&owner) == 800, ERR_WITHDRAW);

    }
}
