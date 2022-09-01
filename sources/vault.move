module satay::vault {
    use std::signer;

    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin::{Self, Coin};
    use aptos_std::table::{Self, Table};
    use liquidswap::router;
    use liquidswap_lp::coins_extended::USDC;
    use liquidswap_lp::lp::LP;

    const ERR_POSITIONS: u64 = 1;
    const ERR_NOT_ENOUGH_POSITION: u64 = 2;

    struct VaultPositions has key {
        items: Table<address, u64>
    }

    struct Vault has key {
        usdc_coins: Coin<USDC>,
        aptos_coins: Coin<AptosCoin>,
    }

    // create vault and initialize holdings to zero
    public fun register(vault_owner: &signer) {
        let vault = Vault {
            usdc_coins: coin::zero(),
            aptos_coins: coin::zero()
        };
        move_to(vault_owner, vault);
    }

    // deposit 
    public fun deposit(user: &signer, vault_address: address, coin: Coin<USDC>) acquires Vault, VaultPositions {
        let user_address = signer::address_of(user);
        if (!exists<VaultPositions>(user_address)) {
            move_to(user, VaultPositions { items: table::new() });
        };

        let vault_positions = borrow_global_mut<VaultPositions>(user_address);
        let position = table::borrow_mut_with_default(&mut vault_positions.items, vault_address, 0);
        *position = *position + get_position_amount(coin::value(&coin));

        let vault = borrow_global_mut<Vault>(vault_address);
        apply_strategy(vault, coin);
    }

    public fun withdraw(user: &signer, vault_address: address, position_amount: u64) acquires Vault, VaultPositions {
        let user_address = signer::address_of(user);

        assert!(exists<VaultPositions>(user_address), ERR_POSITIONS);
        let vault_positions = borrow_global_mut<VaultPositions>(user_address);

        let user_position = table::borrow_mut_with_default(&mut vault_positions.items, vault_address, 0);
        assert!(*user_position >= position_amount, ERR_NOT_ENOUGH_POSITION);
        *user_position = *user_position - position_amount;

        let _vault = borrow_global_mut<Vault>(vault_address);
        let _usdc_coins_amount = get_usdc_amount(position_amount);
        // somehow convert positions in Vault into USDC
        // get to user
    }

    fun get_position_amount(usdc_amount: u64): u64 {
        // get price of one position token in USDC, let's assume it 1-to-1 for now
        usdc_amount
    }

    fun get_usdc_amount(position_amount: u64): u64 {
        // get price of one position token in USDC, let's assume it 1-to-1 for now
        position_amount
    }

    fun apply_strategy(vault: &mut Vault, usdc_coins: Coin<USDC>) {
        let coins_amount = coin::value(&usdc_coins);

        let to_usdc = coins_amount / 2;
        coin::merge(
            &mut vault.usdc_coins,
            coin::extract(&mut usdc_coins, to_usdc)
        );

        let aptos_coins = swap_usdc_to_aptos(usdc_coins);
        coin::merge(&mut vault.aptos_coins, aptos_coins);
    }

    fun swap_usdc_to_aptos(coins: Coin<USDC>): Coin<AptosCoin> {
        // swap on AMM
        let aptos_coins =
            router::swap_exact_coin_for_coin<USDC, AptosCoin, LP<USDC, AptosCoin>>(@liquidswap_lp, coins, 1);
        aptos_coins
    }
}





















