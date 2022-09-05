#[test_only]
module satay::test_vault {

    use aptos_framework::coin;
    use aptos_framework::genesis;
    use aptos_framework::signer;

    use satay::vault;

    use test_helpers::test_account;

    use liquidswap_lp::coins::{
        Self,
        USDT
    };

    #[test_only]
    fun setup_tests(
        coin_admin : &signer,
        user : &signer,
    ) {

        genesis::setup();

        test_account::create_account(coin_admin);
        test_account::create_account(user);

        coins::register_coins(coin_admin);

        coin::register<USDT>(user);
    }

    #[test(
        vault_manager=@0x45
    )]
    fun test_create_vault(vault_manager : &signer) {
        let vault_cap = vault::new<USDT>(vault_manager, b"test_vault", 0);
        assert!(vault::vault_cap_has_id(&vault_cap, 0), 0);
        assert!(vault::has_coin<USDT>(&vault_cap), 0);
        assert!(vault::balance<USDT>(&vault_cap) == 0, 0);
    }

    #[test(
        vault_manager=@satay,
        coin_admin = @liquidswap_lp,
        user=@0x46,
    )]
    fun test_deposit(
        vault_manager : signer,
        coin_admin : signer,
        user : signer
    ){

        setup_tests(&coin_admin, &user);

        let vault_cap = vault::new<USDT>(&vault_manager, b"test_vault", 0);

        coins::mint_coin<USDT>(&coin_admin, signer::address_of(&user), 100);
        vault::deposit<USDT>(&vault_cap, coin::withdraw<USDT>(&user, 100));
        assert!(vault::balance<USDT>(&vault_cap) == 100, 0);
    }

    #[test(
        vault_manager=@satay,
        coin_admin = @liquidswap_lp,
        user=@0x46,
    )]
    fun test_withdraw(
        vault_manager : signer,
        coin_admin : signer,
        user : signer
    ){

        setup_tests(&coin_admin, &user);

        let vault_cap = vault::new<USDT>(&vault_manager, b"test_vault", 0);

        coins::mint_coin<USDT>(&coin_admin, signer::address_of(&user), 100);
        vault::deposit<USDT>(&vault_cap, coin::withdraw<USDT>(&user, 100));

        // withdraw from vault
        let coin = vault::withdraw<USDT>(&vault_cap, 100);
        coin::deposit<USDT>(signer::address_of(&user), coin);

        assert!(vault::balance<USDT>(&vault_cap) == 0, 0);
    }
}