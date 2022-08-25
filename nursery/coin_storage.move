module satay::coin_storage {
    use std::signer;

    use aptos_framework::coin::{Self, Coin};
    use aptos_std::table::{Self, Table};
    use aptos_std::type_info::{Self, TypeInfo};

    const ERR_NO_VAULT: u64 = 100;
    const ERR_STORAGE_DOES_NOT_EXIST: u64 = 101;
    const ERR_STORAGE_ALREADY_EXISTS: u64 = 102;
    const ERR_NOT_ENOUGH_COINS: u64 = 103;

    struct Balances has key {
        items: Table<TypeInfo, u64>,
    }

    struct CoinStorage<phantom CoinType> has key {
        coin: Coin<CoinType>
    }

    // TODO: pass vector<TypeInfo> to restrict types of coins in Vault?
    public fun register_vault(vault_owner: &signer) {
        // only one Vault per address
        move_to(vault_owner, Balances { items: table::new() });
    }

    public fun register_coin_storage<CoinType>(vault_owner: &signer) acquires Balances {
        let vault_address = signer::address_of(vault_owner);
        assert!(!exists<Balances>(vault_address), ERR_NO_VAULT);
        assert!(
            !exists<CoinStorage<CoinType>>(vault_address),
            ERR_STORAGE_ALREADY_EXISTS
        );

        let vault = borrow_global_mut<Balances>(vault_address);
        let coin_type = type_info::type_of<CoinType>();
        table::add(&mut vault.items, coin_type, 0);

        move_to(vault_owner, CoinStorage<CoinType> { coin: coin::zero() });
    }

    // public entry fun deposit_coins<CoinType>(user: &signer, vault_address: address, amount: u64) acquires Vault, VaultStorage {
    //     assert!(exists<Vault>(vault_address), ERR_NO_VAULT);
    //     assert!(
    //         exists<VaultStorage<CoinType>>(vault_address),
    //         ERR_STORAGE_DOES_NOT_EXIST
    //     );
    //     let vault = borrow_global_mut<Vault>(vault_address);
    //     let balance = table::borrow_mut(&mut vault.balances, type_info::type_of<CoinType>());
    //     *balance = *balance + coin::value(&coins);
    //
    //     let vault_storage = borrow_global_mut<VaultStorage<CoinType>>(vault_address);
    //     coin::merge(&mut vault_storage.coin, coins);
    // }

    // public entry fun withdraw_coins<CoinType>(user: &signer, vault_address: address, amount: u64)
    // acquires Vault, VaultStorage {
    //     assert!(exists<Vault>(vault_address), ERR_NO_VAULT);
    //     assert!(
    //         exists<VaultStorage<CoinType>>(vault_address),
    //         ERR_STORAGE_DOES_NOT_EXIST
    //     );
    //     let vault = borrow_global_mut<Vault>(vault_address);
    //     let balance = table::borrow_mut(&mut vault.balances, type_info::type_of<CoinType>());
    //     assert!(balance >= balance, ERR_STORAGE_DOES_NOT_EXIST);
    //     *balance = *balance - amount;
    //
    //     let vault_storage = borrow_global_mut<VaultStorage<CoinType>>(vault_address);
    //     coin::extract(&mut vault_storage.coin, amount)
    // }
}
