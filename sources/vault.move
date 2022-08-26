module satay::vault {
    use std::signer;

    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin::{Self, Coin};
    use aptos_std::table::{Self, Table};
    use liquidswap::router;
    use liquidswap_lp::coins_extended::USDC;
    use liquidswap_lp::lp::LP;
    use aptos_std::type_info::TypeInfo;

    const ERR_POSITIONS: u64 = 1;
    const ERR_NOT_INITIALIZED: u64 = 3;
    const ERR_NOT_ENOUGH_POSITION: u64 = 2;

    struct VaultUserPositions has key {
        items: Table<address, u64>
    }

    struct VaultCoinStorage<phantom CoinType> has key {
        coin: Coin<CoinType>
    }

    struct Vault has key {
        items: Table<TypeInfo, u64>
    }

    public fun register(vault_owner: &signer) {
        move_to(vault_owner, Vault { items: table::new() });
        move_to(vault_owner, VaultCoinStorage<USDC> { coin: coin::zero() });
        move_to(vault_owner, VaultCoinStorage<AptosCoin> { coin: coin::zero() });
        move_to(vault_owner, VaultUserPositions { items: table::new() });
    }

    public fun deposit(user: &signer, vault_address: address, coin: Coin<USDC>) acquires VaultUserPositions, VaultCoinStorage {
        assert_vault_exists(vault_address);

        let user_address = signer::address_of(user);
        let vault_positions = borrow_global_mut<VaultUserPositions>(user_address);
        let position = table::borrow_mut_with_default(&mut vault_positions.items, vault_address, 0);
        *position = *position + get_position_amount(coin::value(&coin));

        apply_strategy(vault_address, coin);
    }

    public fun withdraw(user: &signer, vault_address: address, position_amount: u64) acquires VaultUserPositions {
        assert_vault_exists(vault_address);

        let user_address = signer::address_of(user);
        let vault_positions = borrow_global_mut<VaultUserPositions>(user_address);

        let user_position = table::borrow_mut_with_default(&mut vault_positions.items, vault_address, 0);
        assert!(*user_position >= position_amount, ERR_NOT_ENOUGH_POSITION);
        *user_position = *user_position - position_amount;

        let usdc_coins_amount = get_usdc_amount(position_amount);
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

    fun apply_strategy(vault_address: address, usdc_coins: Coin<USDC>) acquires VaultCoinStorage {
        let coins_amount = coin::value(&usdc_coins);

        let to_usdc = coins_amount / 2;
        let usdc_storage = borrow_global_mut<VaultCoinStorage<USDC>>(vault_address);
        coin::merge(
            &mut usdc_storage.coin,
            coin::extract(&mut usdc_coins, to_usdc)
        );

        let aptos_storage = borrow_global_mut<VaultCoinStorage<AptosCoin>>(vault_address);
        let aptos_coins = swap_usdc_to_aptos(usdc_coins);
        coin::merge(&mut aptos_storage.coin, aptos_coins);
    }

    fun swap_usdc_to_aptos(coins: Coin<USDC>): Coin<AptosCoin> {
        // swap on AMM
        let aptos_coins =
            router::swap_exact_coin_for_coin<USDC, AptosCoin, LP<USDC, AptosCoin>>(@liquidswap_lp, coins, 1);
        aptos_coins
    }

    fun assert_vault_exists(vault_address: address) {
        assert!(
            exists<Vault>(vault_address),
            ERR_NOT_INITIALIZED
        );
    }
}





















