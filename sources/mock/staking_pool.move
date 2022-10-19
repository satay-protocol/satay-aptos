module satay::staking_pool {
    use aptos_framework::coin::{Self, Coin};

    struct CoinStore<phantom CoinType> has key {
        coin: Coin<CoinType>
    }

    public fun initialize<CoinType>(account: signer) {
        move_to(&account, CoinStore<CoinType> {
            coin: coin::zero()
        })
    }

    public fun deposit<CoinType>(manager_addr: address, coins: Coin<CoinType>) acquires CoinStore {
        let coinStore = borrow_global_mut<CoinStore<CoinType>>(manager_addr);
        coin::merge(&mut coinStore.coin, coins);
    }

    public fun withdraw<CoinType>(manager_addr: address, amount: u64) : Coin<CoinType> acquires CoinStore {
        let coinStore = borrow_global_mut<CoinStore<CoinType>>(manager_addr);
        coin::extract(&mut coinStore.coin, amount)
    }

    public fun claimRewards<CoinType>(manager_addr: address) : Coin<CoinType> acquires CoinStore {
        let coinStore = borrow_global_mut<CoinStore<CoinType>>(manager_addr);
        coin::extract(&mut coinStore.coin, 1)
    }
}
