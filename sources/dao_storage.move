module satay::dao_storage {

    use std::signer;

    use aptos_std::event::EventHandle;

    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::event;

    use satay::global_config;

    const ERR_NOT_REGISTERED: u64 = 301;

    struct CoinStore<phantom CoinType> has key {
        coin: Coin<CoinType>,
        deposit_events: EventHandle<DepositEvent<CoinType>>,
        withdraw_events: EventHandle<WithdrawEvent<CoinType>>,
    }

    // events

    struct DepositEvent<phantom CoinType> has store, drop {
        amount: u64
    }
    struct WithdrawEvent<phantom CoinType> has store, drop {
        amount: u64,
        recipient: address,
    }

    // creates Storage for CoinType in signer's account
    // called by vaults
    public fun register<CoinType>(vault_acc: &signer) {
        move_to(vault_acc, CoinStore<CoinType>{
            coin: coin::zero(),
            deposit_events: account::new_event_handle(vault_acc),
            withdraw_events: account::new_event_handle(vault_acc)
        });
    }

    // deposit CoinType into Storage for vault_addr
    public fun deposit<CoinType>(
        vault_addr: address,
        asset: Coin<CoinType>
    ) acquires CoinStore {
        // assert that Storage for CoinType exists for vault_address
        assert_has_storage<CoinType>(vault_addr);

        let amount = coin::value(&asset);
        let coin_store = borrow_global_mut<CoinStore<CoinType>>(vault_addr);

        coin::merge(&mut coin_store.coin, asset);
        event::emit_event(&mut coin_store.deposit_events, DepositEvent<CoinType> {
            amount
        })
    }

    // withdraw CoinType from DAO storage for vault_addr
    public entry fun withdraw<CoinType>(
        dao_admin: &signer,
        vault_addr: address,
        amount: u64
    ) acquires CoinStore {
        // assert that signer is the DAO admin
        global_config::assert_dao_admin(dao_admin);
        let dao_admin_addr = signer::address_of(dao_admin);

        let coin_store = borrow_global_mut<CoinStore<CoinType>>(vault_addr);
        let asset = coin::extract(&mut coin_store.coin, amount);

        event::emit_event(&mut coin_store.withdraw_events, WithdrawEvent<CoinType> {
            amount,
            recipient: dao_admin_addr
        });

        coin::deposit(dao_admin_addr, asset);
    }

    // gets the Storage balance for CoinType of a given vault_addr
    public fun balance<CoinType>(owner_addr: address): u64 acquires CoinStore {
        // assert that Storage for CoinType exists for vault_address
        assert_has_storage<CoinType>(owner_addr);
        let storage = borrow_global<CoinStore<CoinType>>(owner_addr);
        coin::value<CoinType>(&storage.coin)
    }

    public fun has_storage<CoinType>(owner_addr: address): bool {
        exists<CoinStore<CoinType>>(owner_addr)
    }

    fun assert_has_storage<CoinType>(owner_addr: address) {
        assert!(has_storage<CoinType>(owner_addr), ERR_NOT_REGISTERED);
    }
}
