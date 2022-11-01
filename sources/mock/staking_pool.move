module satay::staking_pool {

    use aptos_framework::coin::{Self, Coin, BurnCapability, FreezeCapability, MintCapability};

    use std::signer;
    use std::string;

    const ERR_NOT_REGISTERED_USER: u64 = 501;

    struct CoinStore<phantom CoinType> has key {
        coin: Coin<CoinType>
    }

    struct StakingCoin {}

    struct StakingCoinCaps has key {
        burn_cap: BurnCapability<StakingCoin>,
        freeze_cap: FreezeCapability<StakingCoin>,
        mint_cap: MintCapability<StakingCoin>,
    }

    public fun initialize<BaseCoinType, RewardCoinType>(account: &signer) {
        // only staking pool manager can initialize
        assert!(signer::address_of(account) == @satay, 1);
        move_to(account, CoinStore<BaseCoinType> {
            coin: coin::zero()
        });
        move_to(account, CoinStore<RewardCoinType> {
            coin: coin::zero()
        });
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<StakingCoin>(
            account,
            string::utf8(b"Vault Token"),
            string::utf8(b"Vault"),
            8,
            true
        );
        move_to(
            account,
            StakingCoinCaps {
                burn_cap,
                freeze_cap,
                mint_cap
            }
        )
    }

    public fun deposit_rewards<CoinType>(owner: &signer, amount: u64) acquires CoinStore {
        let coins = coin::withdraw<CoinType>(owner, amount);
        let coinStore = borrow_global_mut<CoinStore<CoinType>>(@satay);
        coin::merge(&mut coinStore.coin, coins);
    }

    public fun deposit<CoinType>(coins: Coin<CoinType>) : Coin<StakingCoin> acquires CoinStore, StakingCoinCaps {
        let coinStore = borrow_global_mut<CoinStore<CoinType>>(@satay);
        let coin_caps = borrow_global_mut<StakingCoinCaps>(@satay);
        let amount = coin::value(&coins);
        coin::merge(&mut coinStore.coin, coins);
        coin::mint<StakingCoin>(amount, &coin_caps.mint_cap)
    }

    public fun withdraw<CoinType>(coins: Coin<StakingCoin>) : Coin<CoinType> acquires CoinStore, StakingCoinCaps {
        let coinStore = borrow_global_mut<CoinStore<CoinType>>(@satay);
        let coin_caps = borrow_global_mut<StakingCoinCaps>(@satay);
        let amount = coin::value(&coins);
        coin::burn(coins, &coin_caps.burn_cap);
        coin::extract(&mut coinStore.coin, amount)
    }

    public fun claimRewards<CoinType>() : Coin<CoinType> acquires CoinStore {
        let coinStore = borrow_global_mut<CoinStore<CoinType>>(@satay);
        coin::extract(&mut coinStore.coin, 10)
    }

    public fun get_base_coin_for_staking_coin(share_token_amount: u64) : u64 {
        share_token_amount
    }
}
