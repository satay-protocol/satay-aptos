module satay::dao_storage {

    use std::signer;

    use aptos_std::event::EventHandle;

    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::event;

    use satay::global_config;

    const ERR_NOT_REGISTERED: u64 = 301;

    struct Storage<phantom CoinType> has key {
        coin: Coin<CoinType>
    }

    struct StorageCreatedEvent<phantom CoinType> has store, drop {}
    struct CoinDepositedEvent<phantom CoinType> has store, drop {
        amount: u64
    }
    struct CoinWithdrawEvent<phantom CoinType> has store, drop {
        amount: u64
    }

    struct EventsStore<phantom CoinType> has key {
        storage_registered_handle: EventHandle<StorageCreatedEvent<CoinType>>,
        coin_deposited_handle: EventHandle<CoinDepositedEvent<CoinType>>,
        coin_withdraw_handle: EventHandle<CoinWithdrawEvent<CoinType>>
    }

    // creates Storage for CoinType in signer's account
    // called by vaults
    public fun register<CoinType>(owner: &signer) {
        move_to(owner, Storage<CoinType>{coin: coin::zero()});

        let events_store = EventsStore {
            storage_registered_handle: account::new_event_handle(owner),
            coin_deposited_handle: account::new_event_handle(owner),
            coin_withdraw_handle: account::new_event_handle(owner)
        };
        event::emit_event(
            &mut events_store.storage_registered_handle,
            StorageCreatedEvent<CoinType> {}
        );

        move_to(owner, events_store);
    }

    // deposit CoinType into Storage for vault_addr
    public fun deposit<CoinType>(
        vault_addr: address,
        asset: Coin<CoinType>
    ) acquires Storage, EventsStore {
        // assert that Storage for CoinType exists for vault_address
        assert_has_storage<CoinType>(vault_addr);

        let asset_amount = coin::value(&asset);
        let storage = borrow_global_mut<Storage<CoinType>>(vault_addr);

        coin::merge(&mut storage.coin, asset);
        let events_store = borrow_global_mut<EventsStore<CoinType>>(vault_addr);
        event::emit_event(
            &mut events_store.coin_deposited_handle,
            CoinDepositedEvent<CoinType> {amount: asset_amount}
        )
    }

    // withdraw CoinType from DAO storage for vault_addr
    public entry fun withdraw<CoinType>(
        dao_admin: &signer,
        vault_addr: address,
        amount: u64
    ) acquires Storage, EventsStore {
        // assert that signer is the DAO admin
        global_config::assert_dao_admin(dao_admin);

        let storage = borrow_global_mut<Storage<CoinType>>(vault_addr);
        let asset = coin::extract(&mut storage.coin, amount);

        let event_store = borrow_global_mut<EventsStore<CoinType>>(vault_addr);
        event::emit_event(
            &mut event_store.coin_withdraw_handle,
            CoinWithdrawEvent<CoinType> {amount}
        );

        coin::deposit(signer::address_of(dao_admin), asset);
    }

    // gets the Storage balance for CoinType of a given vault_addr
    public fun balance<CoinType>(owner_addr: address): u64 acquires Storage {
        // assert that Storage for CoinType exists for vault_address
        assert_has_storage<CoinType>(owner_addr);
        let storage = borrow_global<Storage<CoinType>>(owner_addr);
        coin::value<CoinType>(&storage.coin)
    }

    public fun has_storage<CoinType>(owner_addr: address): bool {
        exists<Storage<CoinType>>(owner_addr)
    }

    fun assert_has_storage<CoinType>(owner_addr: address) {
        assert!(has_storage<CoinType>(owner_addr), ERR_NOT_REGISTERED);
    }
}
