module satay::usdc_aptos {
    use std::signer;

    use aptos_framework::account::SignerCapability;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin::{Self, Coin};
    use aptos_std::table::{Self, Table};
    use liquidswap::router;
    use liquidswap_lp::coins_extended::USDC;
    use liquidswap_lp::lp::LP;

    use satay::vault;

    #[test_only]
    use aptos_std::iterable_table::{Self, IterableTable};
    #[test_only]
    use std::string::String;

    const ERR_NO_PERMISSIONS: u64 = 201;
    const ERR_INITIALIZE: u64 = 202;
    const ERR_NO_POSITION: u64 = 203;
    const ERR_NOT_ENOUGH_POSITION: u64 = 204;

    struct Capability has key {
        vault_cap: SignerCapability
    }

    struct UserPositions has key {
        items: Table<address, u64>
    }

    public fun initialize(owner: &signer) {
        assert!(
            signer::address_of(owner) == @satay,
            ERR_NO_PERMISSIONS
        );
        assert!(!exists<Capability>(@satay), ERR_INITIALIZE);

        let vault_cap = vault::new(owner, b"usdc_aptos_strategy");
        vault::add_coin<USDC>(&vault_cap);
        vault::add_coin<AptosCoin>(&vault_cap);
        move_to(owner, Capability { vault_cap });


        let user_positions = UserPositions { items: table::new() };
        move_to(owner, user_positions);
    }

    public entry fun deposit(user: &signer, usdc_amount: u64) acquires Capability, UserPositions {
        assert!(exists<Capability>(@satay), ERR_INITIALIZE);

        let vault_cap = &borrow_global<Capability>(@satay).vault_cap;
        let usdc_coin = coin::withdraw<USDC>(user, usdc_amount);
        apply_strategy(vault_cap, usdc_coin);

        let user_positions = borrow_global_mut<UserPositions>(@satay);
        let position =
            table::borrow_mut_with_default(&mut user_positions.items, signer::address_of(user), 0);
        *position = *position + usdc_amount;
    }

    public entry fun withdraw(user: &signer, amount: u64) acquires Capability, UserPositions {
        assert!(exists<Capability>(@satay), ERR_INITIALIZE);

        let user_address = signer::address_of(user);
        let user_positions = borrow_global_mut<UserPositions>(@satay);
        assert!(
            table::contains(&user_positions.items, user_address),
            ERR_NO_POSITION
        );

        let position = table::borrow_mut(&mut user_positions.items, signer::address_of(user));
        assert!(*position >= amount, ERR_NOT_ENOUGH_POSITION);

        *position = *position - amount;

        let vault_cap = &borrow_global<Capability>(@satay).vault_cap;
        let usdc_coin = get_user_position(vault_cap, amount);
        coin::deposit(signer::address_of(user), usdc_coin);
    }

    fun apply_strategy(vault_cap: &SignerCapability, usdc_coins: Coin<USDC>) {
        let coins_amount = coin::value(&usdc_coins);

        let to_usdc = coins_amount / 2;
        vault::deposit(
            vault_cap,
            coin::extract(&mut usdc_coins, to_usdc)
        );

        let aptos_coins = swap<USDC, AptosCoin>(usdc_coins);
        vault::deposit(vault_cap, aptos_coins);
    }

    fun get_user_position(vault_cap: &SignerCapability, position_amount: u64): Coin<USDC> {
        // split position in half, extract first one from USDC, and second from AptosCoin
        let usdc_position = position_amount / 2;
        let usdc_coin = vault::withdraw<USDC>(vault_cap, usdc_position);

        let aptos_position = position_amount - usdc_position;
        let aptos_coin = vault::withdraw<AptosCoin>(vault_cap, aptos_position);
        let swapped_usdc_coin = swap<AptosCoin, USDC>(aptos_coin);
        coin::merge(&mut usdc_coin, swapped_usdc_coin);
        usdc_coin
    }

    fun swap<From, To>(coins: Coin<From>): Coin<To> {
        // swap on AMM
        router::swap_exact_coin_for_coin<From, To, LP<USDC, AptosCoin>>(
            @liquidswap_lp,
            coins,
            1
        )
    }

    #[test_only]
    public fun positions(): IterableTable<String, u64> acquires Capability {
        assert!(exists<Capability>(@satay), ERR_INITIALIZE);

        let vault_cap = &borrow_global<Capability>(@satay).vault_cap;

        let positions = iterable_table::new();
        iterable_table::add(&mut positions, coin::symbol<USDC>(), vault::balance<USDC>(vault_cap));
        iterable_table::add(&mut positions, coin::symbol<AptosCoin>(), vault::balance<AptosCoin>(vault_cap));
        positions
    }
}
