module satay::simple_staking_strategy {

    use aptos_framework::coin::{Self, Coin};
    use satay::staking_pool::{Self, StakingCoin};
    use liquidswap::router;
    use liquidswap::curves::Uncorrelated;
    use std::signer;
    use satay::vault;
    use satay::vault::{VaultCapability};
    use satay::base_strategy;
    use satay::base_strategy::open_vault_for_harvest;

    // witness for the strategy
    // used for checking approval when locking and unlocking vault
    struct SimpleStakingStrategy has drop {}

    // To be replaced by the PositionCoin which will be returned by the strategy
    struct PoolBaseCoin has store {}

    const ERR_NOT_ENOUGH_FUND: u64 = 301;
    const ERR_ENOUGH_BALANCE_ON_VAULT: u64 = 302;
    const ERR_LOSS: u64 = 303;

    // initialize vault_id to accept strategy
    public entry fun initialize(
        manager: &signer,
        vault_id: u64,
        debt_ratio: u64
    ) {
        base_strategy::initialize<SimpleStakingStrategy, StakingCoin>(
            manager,
            vault_id,
            debt_ratio,
            SimpleStakingStrategy{}
        );
    }

    // called when vault does not have enough BaseCoin in reserves, and must reclaim funds from strategy
    public entry fun withdraw_for_user<BaseCoin>(
        user: &signer,
        manager_addr: address,
        vault_id: u64,
        share_amount: u64
    ) {
        let (user_amount, vault_cap, stop_handle) = base_strategy::open_vault_for_user_withdraw<SimpleStakingStrategy, BaseCoin>(
            user,
            manager_addr,
            vault_id,
            share_amount,
            SimpleStakingStrategy {}
        );
        let staking_coins = vault::withdraw<StakingCoin>(&vault_cap, user_amount);
        let coins = liquidate_position<BaseCoin>(staking_coins);
        base_strategy::close_vault_for_user_withdraw<SimpleStakingStrategy, BaseCoin>(
            manager_addr,
            vault_cap,
            stop_handle,
            coins
        );
    }

    // harvests the Strategy, realizing any profits or losses and adjusting the Strategy's position.
    public entry fun harvest<CoinType, BaseCoin>(manager: &signer, vault_id: u64) {
        let (vault_cap, stop_handle) = open_vault_for_harvest<SimpleStakingStrategy, BaseCoin>(
            manager,
            vault_id,
            SimpleStakingStrategy {}
        );

        // claim rewards and swap them into BaseCoin
        let coins = staking_pool::claimRewards<CoinType>();
        let want_coins = swap_to_want_token<CoinType, BaseCoin>(coins);
        let strategy_coins = apply_position<BaseCoin>(want_coins);

        base_strategy::deposit_strategy_coin<StakingCoin>(&mut vault_cap, strategy_coins);

        let strategy_balance = vault::balance<StakingCoin>(&vault_cap);
        let (to_apply, to_liquidate) = base_strategy::process_harvest<SimpleStakingStrategy, BaseCoin, StakingCoin>(
            &mut vault_cap,
            strategy_balance,
            SimpleStakingStrategy {}
        );

        let base_coins = liquidate_position<BaseCoin>(to_liquidate);
        let staking_coins = apply_position<BaseCoin>(to_apply);

        base_strategy::close_vault_for_harvest<SimpleStakingStrategy, BaseCoin, StakingCoin>(
            signer::address_of(manager),
            vault_cap,
            stop_handle,
            base_coins,
            staking_coins
        )
    }

    // adds BaseCoin to 3rd party protocol to get yield
    // if 3rd party protocol returns a coin, it should be sent to the vault
    fun apply_position<BaseCoin>(coins: Coin<BaseCoin>) : Coin<StakingCoin> {
        staking_pool::deposit(coins)
    }

    // removes BaseCoin from 3rd party protocol to get yield
    fun liquidate_position<BaseCoin>(coins: Coin<StakingCoin>): Coin<BaseCoin> {
        if(coin::value(&coins) > 0) {
            staking_pool::withdraw<BaseCoin>(coins)
        } else {
            coin::destroy_zero(coins);
            coin::zero<BaseCoin>()
        }
    }

    // calls a vault's assess_fees function for a specified gain amount
    fun assess_fees<BaseCoin>(gain: u64, vault_cap: &VaultCapability) {
        vault::assess_fees<SimpleStakingStrategy, BaseCoin>(
            gain,
            0,
            vault_cap,
            SimpleStakingStrategy {}
        );
    }

    public fun name() : vector<u8> {
        b"strategy-name"
    }

    public fun version() : vector<u8> {
        b"0.0.1"
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
