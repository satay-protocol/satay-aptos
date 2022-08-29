module satay::vault {
    use std::signer;

    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::coin::{Self, Coin};
    use aptos_std::table::Table;
    use aptos_std::table;

    const ERR_NO_USER_POSITION: u64 = 101;
    const ERR_NOT_ENOUGH_USER_POSITION: u64 = 102;

    struct CoinStore<phantom CoinType> has key {
        coin: Coin<CoinType>
    }

    struct Vault has key {
        user_positions: Table<address, u64>
    }

    struct VaultCapability has drop, store {
        storage_cap: SignerCapability,
        // TODO: add vault_address to avoid two function calls everywhere?
        // TODO: add Vault id here to avoid creating the same VaultCapability somehow
    }

    public fun new(owner: &signer, seed: vector<u8>): VaultCapability {
        let (vault_acc, storage_cap) = account::create_resource_account(owner, seed);
        move_to(
            &vault_acc,
            Vault { user_positions: table::new() }
        );
        VaultCapability { storage_cap }
        // TODO: event
    }

    public fun add_coin<CoinType>(vault_cap: &VaultCapability) {
        let owner = account::create_signer_with_capability(&vault_cap.storage_cap);
        move_to(
            &owner,
            CoinStore<CoinType> { coin: coin::zero() }
        );
        // TODO: event
    }

    public fun deposit<CoinType>(vault_cap: &VaultCapability, coin: Coin<CoinType>) acquires CoinStore {
        let vault_acc = account::create_signer_with_capability(&vault_cap.storage_cap);
        let vault_addr = signer::address_of(&vault_acc);
        let store = borrow_global_mut<CoinStore<CoinType>>(vault_addr);
        coin::merge(&mut store.coin, coin);
        // TODO: event
    }

    public fun withdraw<CoinType>(vault_cap: &VaultCapability, amount: u64): Coin<CoinType> acquires CoinStore {
        let vault_acc = account::create_signer_with_capability(&vault_cap.storage_cap);
        let vault_addr = signer::address_of(&vault_acc);
        let store = borrow_global_mut<CoinStore<CoinType>>(vault_addr);
        coin::extract(&mut store.coin, amount)

        // TODO: event
    }

    public fun balance<CoinType>(vault_cap: &VaultCapability): u64 acquires CoinStore {
        let vault_acc = account::create_signer_with_capability(&vault_cap.storage_cap);
        let vault_addr = signer::address_of(&vault_acc);
        let store = borrow_global_mut<CoinStore<CoinType>>(vault_addr);
        coin::value(&store.coin)
    }

    public fun add_user_position(vault_cap: &VaultCapability, user_addr: address, amount: u64) acquires Vault {
        let vault_acc = account::create_signer_with_capability(&vault_cap.storage_cap);
        let vault_addr = signer::address_of(&vault_acc);
        let vault = borrow_global_mut<Vault>(vault_addr);
        let user_position =
            table::borrow_mut_with_default(&mut vault.user_positions, user_addr, 0);
        *user_position = *user_position + amount;
        // TODO: event
    }

    public fun remove_user_position(vault_cap: &VaultCapability, user_addr: address, amount: u64) acquires Vault {
        let vault_acc = account::create_signer_with_capability(&vault_cap.storage_cap);
        let vault_addr = signer::address_of(&vault_acc);

        let vault = borrow_global_mut<Vault>(vault_addr);
        assert!(
            table::contains(&vault.user_positions, user_addr),
            ERR_NO_USER_POSITION
        );

        let user_position = table::borrow_mut(&mut vault.user_positions, user_addr);
        assert!(*user_position >= amount, ERR_NOT_ENOUGH_USER_POSITION);

        *user_position = *user_position - amount;
        // TODO: event
    }
}
















