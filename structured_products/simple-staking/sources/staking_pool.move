module satay_simple_staking::staking_pool {

    use std::signer;
    use std::string;

    use aptos_framework::coin::{Self, Coin, BurnCapability, FreezeCapability, MintCapability};

    use liquidswap::router;
    use liquidswap::curves::Uncorrelated;

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
        assert!(signer::address_of(account) == @satay_simple_staking, 1);
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
        let coinStore = borrow_global_mut<CoinStore<CoinType>>(@satay_simple_staking);
        coin::merge(&mut coinStore.coin, coins);
    }

    public fun apply_position<CoinType>(
        coins: Coin<CoinType>
    ) : Coin<StakingCoin> acquires CoinStore, StakingCoinCaps {
        deposit(coins)
    }

    public fun liquidate_position<CoinType>(
        coins: Coin<StakingCoin>
    ): Coin<CoinType> acquires CoinStore, StakingCoinCaps {
        withdraw(coins)
    }

    public fun reinvest_returns<RewardCoin, BaseCoin>(): Coin<StakingCoin> acquires CoinStore, StakingCoinCaps {
        let reward_coins = claimRewards<RewardCoin>();
        let base_coins = swap_to_want_token<RewardCoin, BaseCoin>(reward_coins);
        apply_position(base_coins)
    }

    fun deposit<CoinType>(coins: Coin<CoinType>) : Coin<StakingCoin> acquires CoinStore, StakingCoinCaps {
        let coinStore = borrow_global_mut<CoinStore<CoinType>>(@satay_simple_staking);
        let coin_caps = borrow_global_mut<StakingCoinCaps>(@satay_simple_staking);
        let amount = coin::value(&coins);
        coin::merge(&mut coinStore.coin, coins);
        coin::mint<StakingCoin>(amount, &coin_caps.mint_cap)
    }

    fun withdraw<CoinType>(coins: Coin<StakingCoin>) : Coin<CoinType> acquires CoinStore, StakingCoinCaps {
        let coinStore = borrow_global_mut<CoinStore<CoinType>>(@satay_simple_staking);
        let coin_caps = borrow_global_mut<StakingCoinCaps>(@satay_simple_staking);
        let amount = coin::value(&coins);
        coin::burn(coins, &coin_caps.burn_cap);
        coin::extract(&mut coinStore.coin, amount)
    }

    fun claimRewards<CoinType>() : Coin<CoinType> acquires CoinStore {
        let coinStore = borrow_global_mut<CoinStore<CoinType>>(@satay_simple_staking);
        coin::extract(&mut coinStore.coin, 10)
    }

    public fun get_base_coin_for_staking_coin(share_token_amount: u64) : u64 {
        share_token_amount
    }

    public fun get_staking_coin_for_base_coin(base_token_amount: u64) : u64 {
        base_token_amount
    }

    // simple swap from CoinType to BaseCoin on Liquidswap
    fun swap_to_want_token<CoinType, BaseCoin>(coins: Coin<CoinType>) : Coin<BaseCoin> {
        // swap on liquidswap AMM
        router::swap_exact_coin_for_coin<CoinType, BaseCoin, Uncorrelated>(
            coins,
            0
        )
    }
}
