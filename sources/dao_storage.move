module satay::dao_storage {
    use std::signer;

    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin};
    use aptos_std::event;
    use aptos_std::event::EventHandle;
    use satay::global_config::get_dao_admin;

    const ERR_NOT_REGISTERED: u64 = 301;
    const ERR_NOT_DAO_ADMIN: u64 = 302;

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

    public fun deposit<CoinType>(vault_addr: address, asset: Coin<CoinType>) acquires Storage, EventsStore {
        assert!(exists<Storage<CoinType>>(vault_addr), ERR_NOT_REGISTERED);
        let asset_amount = coin::value(&asset);
        let storage = borrow_global_mut<Storage<CoinType>>(vault_addr);

        coin::merge(&mut storage.coin, asset);
        let events_store = borrow_global_mut<EventsStore<CoinType>>(vault_addr);
        event::emit_event(
            &mut events_store.coin_deposited_handle,
            CoinDepositedEvent<CoinType> {amount: asset_amount}
        )
    }

    public fun withdraw<CoinType>(dao_admin: &signer, vault_addr: address, amount: u64): Coin<CoinType>
        acquires Storage, EventsStore {

        assert!(get_dao_admin() == signer::address_of(dao_admin), ERR_NOT_DAO_ADMIN);
        let storage = borrow_global_mut<Storage<CoinType>>(vault_addr);
        let asset = coin::extract(&mut storage.coin, amount);

        let event_store = borrow_global_mut<EventsStore<CoinType>>(vault_addr);
        event::emit_event(
            &mut event_store.coin_withdraw_handle,
            CoinWithdrawEvent<CoinType> {amount}
        );

        asset
    }
}
