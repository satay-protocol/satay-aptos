module satay::base_strategy {

    use aptos_framework::coin::{Coin};
    use satay::staking_pool::{Self, claimRewards};
    use liquidswap::router;
    use liquidswap::curves::Uncorrelated;
    // use std::signer;
    // use satay::satay;

    friend satay::vault;

    struct BaseStrategy has drop {}

    /**
     *  @notice
     *  This function adds underyling to 3rd party service to get yield
    */
    public(friend) fun apply_position<BaseCoin>(coins: Coin<BaseCoin>) {
        staking_pool::deposit(@staking_pool_manager, coins);
    }

    public(friend) fun liquidate_position<BaseCoin>(amount: u64) : Coin<BaseCoin> {
        staking_pool::withdraw<BaseCoin>(@staking_pool_manager, amount)
    }

    /**
    *   @notice
    *   It is for harvest
    */
    public entry fun harvest<CoinType, BaseCoin>() {
        let coins = claimRewards<CoinType>(@staking_pool_manager);
        let want_coins = swap_to_want_token<CoinType, BaseCoin>(coins);

        // re-invest
        staking_pool::deposit(@staking_pool_manager, want_coins);
    }

    public entry fun name() : vector<u8> {
        b"strategy-name"
    }

    public entry fun version() : vector<u8> {
        b"0.0.1"
    }

    fun swap_to_want_token<CoinType, BaseCoin>(coins: Coin<CoinType>) : Coin<BaseCoin> {
        // swap on liquidswap AMM
        router::swap_exact_coin_for_coin<CoinType, BaseCoin, Uncorrelated>(
            coins,
            0
        )
    }
}
