#[test_only]
module satay::test_vault {

    use std::signer;

    use aptos_framework::coin;
    use aptos_framework::genesis;

    use satay::vault;

    use test_helpers::test_account;

    use test_coins::coins::{
        Self,
        USDT
    };
    use satay::vault::VaultCoin;

    use satay::aptos_usdt_strategy::AptosUsdcLpStrategy;
    use aptos_std::type_info;

    const ERR_INCORRECT_AMOUNT: u64 = 1001;

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
        vault_manager=@satay
    )]
    fun test_create_vault(vault_manager : &signer) {
        let vault_cap = vault::new_test<USDT>(vault_manager, b"test_vault", 0);
        assert!(vault::vault_cap_has_id(&vault_cap, 0), 0);
        assert!(vault::has_coin<USDT>(&vault_cap), 0);
        assert!(vault::balance<USDT>(&vault_cap) == 0, 0);
    }

    #[test(
        vault_manager=@satay,
        coin_admin = @test_coins,
        user=@0x46,
    )]
    fun test_deposit(
        vault_manager : signer,
        coin_admin : signer,
        user : signer
    ){

        setup_tests(&coin_admin, &user);

        let vault_cap = vault::new_test<USDT>(&vault_manager, b"test_vault", 0);

        coins::mint_coin<USDT>(&coin_admin, signer::address_of(&user), 100);
        vault::deposit<USDT>(&vault_cap, coin::withdraw<USDT>(&user, 100));
        assert!(vault::balance<USDT>(&vault_cap) == 100, 0);
    }

    #[test(
        vault_manager=@satay,
        coin_admin = @test_coins,
        user=@0x46,
    )]
    fun test_withdraw(
        vault_manager : signer,
        coin_admin : signer,
        user : signer
    ){

        setup_tests(&coin_admin, &user);

        let vault_cap = vault::new_test<USDT>(&vault_manager, b"test_vault", 0);

        coins::mint_coin<USDT>(&coin_admin, signer::address_of(&user), 100);
        vault::deposit<USDT>(&vault_cap, coin::withdraw<USDT>(&user, 100));

        // withdraw from vault
        let coin = vault::withdraw<USDT>(&vault_cap, 100);
        coin::deposit<USDT>(signer::address_of(&user), coin);

        assert!(vault::balance<USDT>(&vault_cap) == 0, 0);
    }

    #[test(
        vault_manager=@satay,
        coin_admin = @test_coins,
        user=@0x46,
    )]
    fun test_deposit_as_user(
        vault_manager : signer,
        coin_admin : signer,
        user : signer
    ){

        setup_tests(&coin_admin, &user);

        let vault_cap = vault::new_test<USDT>(&vault_manager, b"test_vault", 0);

        coins::mint_coin<USDT>(&coin_admin, signer::address_of(&user), 100);
        vault::deposit_as_user<USDT>(&user, &vault_cap, coin::withdraw<USDT>(&user, 100));

        assert!(vault::balance<USDT>(&vault_cap) == 100, 0);
        assert!(vault::is_vault_coin_registered<USDT>(signer::address_of(&user)), 1);
        assert!(vault::vault_coin_balance<USDT>(signer::address_of(&user)) == 100, 1);
        assert!(coin::balance<VaultCoin<USDT>>(signer::address_of(&user)) > 0, 2);
    }

    #[test(
        vault_manager=@satay,
        coin_admin = @test_coins,
        user=@0x46,
    )]
    fun test_withdraw_as_user(
        vault_manager : signer,
        coin_admin : signer,
        user : signer
    ){

        setup_tests(&coin_admin, &user);

        let vault_cap = vault::new_test<USDT>(&vault_manager, b"test_vault", 0);

        coins::mint_coin<USDT>(&coin_admin, signer::address_of(&user), 100);
        vault::deposit_as_user<USDT>(&user, &vault_cap, coin::withdraw<USDT>(&user, 100));
        let base_coins = vault::withdraw_as_user(&user, &vault_cap, 100);
        coin::deposit<USDT>(signer::address_of(&user), base_coins);
        assert!(coin::balance<VaultCoin<USDT>>(signer::address_of(&user)) == 0, 2);
    }

    #[test(
        vault_manager=@satay,
        coin_admin = @test_coins,
        user=@0x46,
    )]
    fun test_withdraw_as_user_after_farm(
        vault_manager : signer,
        coin_admin : signer,
        user : signer
    ){

        setup_tests(&coin_admin, &user);

        let vault_cap = vault::new_test<USDT>(&vault_manager, b"test_vault", 0);

        coins::mint_coin<USDT>(&coin_admin, signer::address_of(&user), 1000);
        vault::deposit_as_user<USDT>(&user, &vault_cap, coin::withdraw<USDT>(&user, 500));
        vault::deposit<USDT>(&vault_cap, coin::withdraw<USDT>(&user, 500));

        assert!(coin::balance<VaultCoin<USDT>>(signer::address_of(&user)) == 500, 5);
        assert!(coin::balance<USDT>(signer::address_of(&user)) == 0, 4);

        let base_coins = vault::withdraw_as_user(&user, &vault_cap, 500);
        coin::deposit<USDT>(signer::address_of(&user), base_coins);

        assert!(coin::balance<VaultCoin<USDT>>(signer::address_of(&user)) == 0, 2);
        assert!(coin::balance<USDT>(signer::address_of(&user)) == 1000, 4)
    }

    #[test(
        vault_manager=@satay,
        coin_admin=@test_coins,
        user=@0x46
    )]
    fun test_approve_strategy(
        vault_manager : signer,
        coin_admin : signer,
        user : signer
    ){
        setup_tests(&coin_admin, &user);

        let vault_cap = vault::new_test<USDT>(&vault_manager, b"test_vault", 0);
        vault::approve_strategy<AptosUsdcLpStrategy>(&vault_cap, type_info::type_of<AptosUsdcLpStrategy>(), 1000);
        assert!(vault::has_strategy<AptosUsdcLpStrategy>(&vault_cap), 2);
    }

    // TODO: check share calculation is correct when non_USDT deposited
    #[test(
        vault_manager=@satay,
        coin_admin=@test_coins,
        userA=@0x46,
        userB=@0x047
    )]
    fun test_share_amount_calculation(
        vault_manager : signer,
        coin_admin : signer,
        userA : signer,
        userB : signer
    ){
        setup_tests(&coin_admin, &userA);
        test_account::create_account(&userB);
        coin::register<USDT>(&userB);

        // for the first depositor, should mint same amount
        let vault_cap = vault::new_test<USDT>(&vault_manager, b"test_vault", 0);
        coins::mint_coin<USDT>(&coin_admin, signer::address_of(&userA), 10000);
        coins::mint_coin<USDT>(&coin_admin, signer::address_of(&userB), 10000);
        vault::deposit_as_user<USDT>(&userA, &vault_cap, coin::withdraw<USDT>(&userA, 100));
        assert!(coin::balance<vault::VaultCoin<USDT>>(signer::address_of(&userA)) == 100, ERR_INCORRECT_AMOUNT);

        // userB deposit 1000 coins
        // @dev: userB should get 10x token than userA
        vault::deposit_as_user<USDT>(&userB, &vault_cap, coin::withdraw<USDT>(&userB, 1000));
        assert!(coin::balance<vault::VaultCoin<USDT>>(signer::address_of(&userB)) == 1000, ERR_INCORRECT_AMOUNT);

        // userA deposit 400 coins
        // userA should have 500 shares in total
        vault::deposit_as_user<USDT>(&userA, &vault_cap, coin::withdraw<USDT>(&userA, 400));
        assert!(coin::balance<vault::VaultCoin<USDT>>(signer::address_of(&userA)) == 500, ERR_INCORRECT_AMOUNT);

        vault::deposit(&vault_cap, coin::withdraw<USDT>(&userA, 300));
        // userA withdraw 500 shares
        // userA should withdraw (1500 + 300) / 1500 * 500
        let userA_prev_balance = coin::balance<USDT>(signer::address_of(&userA));
        let coins = vault::withdraw_as_user<USDT>(&userA, &vault_cap, 500);
        coin::deposit<USDT>(signer::address_of(&userA), coins);
        let userA_after_balance = coin::balance<USDT>(signer::address_of(&userA));
        assert!(userA_after_balance - userA_prev_balance == 600, ERR_INCORRECT_AMOUNT);
    }
}