module satay::base_strategy {

    use aptos_framework::coin::{Coin};
    use satay::staking_pool;
    // use std::signer;
    // use satay::satay;

    friend satay::vault;

    struct BaseStrategy has drop {}

    /**
     *  @notice
     *  This function adds underyling to 3rd party service to get yield
    */
    public(friend) fun apply_strategy<BaseCoin>(coins: Coin<BaseCoin>) {
        staking_pool::deposit(@staking_pool_manager, coins);
    }

    public(friend) fun liquidate_strategy<BaseCoin>(amount: u64) : Coin<BaseCoin> {
        staking_pool::withdraw<BaseCoin>(@staking_pool_manager, amount)
    }


}
