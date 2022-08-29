module satay::vault {
    use std::signer;

    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::coin::{Self, Coin};

    const ERR_NO_PERMISSIONS: u64 = 201;

    struct CoinStore<phantom CoinType> has key {
        coin: Coin<CoinType>
    }

    public fun new(source: &signer, seed: vector<u8>): SignerCapability {
        let (_, signer_cap) = account::create_resource_account(source, seed);
        signer_cap

        // TODO: event
    }

    public fun add_coin<CoinType>(signer_cap: &SignerCapability) {
        let owner = account::create_signer_with_capability(signer_cap);
        move_to(
            &owner,
            CoinStore<CoinType> { coin: coin::zero() }
        );
        // TODO: event
    }

    public fun deposit<CoinType>(signer_cap: &SignerCapability, coin: Coin<CoinType>) acquires CoinStore {
        let owner = account::create_signer_with_capability(signer_cap);
        let owner_addr = signer::address_of(&owner);
        let store = borrow_global_mut<CoinStore<CoinType>>(owner_addr);
        coin::merge(&mut store.coin, coin);
        // TODO: event
    }

    public fun withdraw<CoinType>(signer_cap: &SignerCapability, amount: u64): Coin<CoinType> acquires CoinStore {
        let owner = account::create_signer_with_capability(signer_cap);
        let owner_addr = signer::address_of(&owner);
        let store = borrow_global_mut<CoinStore<CoinType>>(owner_addr);
        coin::extract(&mut store.coin, amount)
        // TODO: event
    }

    public fun balance<CoinType>(signer_cap: &SignerCapability): u64 acquires CoinStore {
        let owner = account::create_signer_with_capability(signer_cap);
        let owner_addr = signer::address_of(&owner);
        let store = borrow_global_mut<CoinStore<CoinType>>(owner_addr);
        coin::value(&store.coin)
    }
}
