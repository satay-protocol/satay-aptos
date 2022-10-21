module satay::staking_pool {
    use aptos_framework::coin::{Self, Coin};
    use aptos_std::simple_map;
    use std::signer;

    const ERR_NOT_REGISTERED_USER: u64 = 501;

    struct CoinStore<phantom CoinType> has key {
        coin: Coin<CoinType>
    }

    struct PoolData has key {
        user_info: simple_map::SimpleMap<address, u64>
    }

    public fun initialize<CoinType>(account: signer) {
        move_to(&account, CoinStore<CoinType> {
            coin: coin::zero()
        })
    }

    public fun deposit<CoinType>(owner: &signer, coins: Coin<CoinType>) acquires CoinStore, PoolData {
        let coinStore = borrow_global_mut<CoinStore<CoinType>>(@staking_pool_manager);
        let pool_data = borrow_global_mut<PoolData>(@staking_pool_manager);
        if (simple_map::contains_key(&pool_data.user_info, &signer::address_of(owner))) {
            let user_amount = simple_map::borrow_mut(&mut pool_data.user_info, &signer::address_of(owner));
            *user_amount = *user_amount + coin::value(&coins);
        } else {
            simple_map::add(&mut pool_data.user_info, signer::address_of(owner), coin::value(&coins));
        };
        coin::merge(&mut coinStore.coin, coins);
    }

    public fun withdraw<CoinType>(owner: &signer, amount: u64) : Coin<CoinType> acquires CoinStore, PoolData {
        let coinStore = borrow_global_mut<CoinStore<CoinType>>(@staking_pool_manager);
        let pool_data = borrow_global_mut<PoolData>(@staking_pool_manager);
        assert!(simple_map::contains_key(&pool_data.user_info, &signer::address_of(owner)), ERR_NOT_REGISTERED_USER);
        let user_amount = simple_map::borrow_mut(&mut pool_data.user_info, &signer::address_of(owner));
        *user_amount = *user_amount - amount;
        coin::extract(&mut coinStore.coin, amount)
    }

    public fun claimRewards<CoinType>(manager_addr: address) : Coin<CoinType> acquires CoinStore {
        let coinStore = borrow_global_mut<CoinStore<CoinType>>(manager_addr);
        coin::extract(&mut coinStore.coin, 1)
    }

    public fun balanceOf(user_addr : address) : u64 acquires PoolData {
        let pool_data = borrow_global_mut<PoolData>(@staking_pool_manager);
        assert!(simple_map::contains_key(&pool_data.user_info, &user_addr), ERR_NOT_REGISTERED_USER);

        // for testing purpose!
        let pool_data = borrow_global_mut<PoolData>(@staking_pool_manager);
        assert!(simple_map::contains_key(&pool_data.user_info, &user_addr), ERR_NOT_REGISTERED_USER);
        *simple_map::borrow(&pool_data.user_info, &user_addr)
    }
}
