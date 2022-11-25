#[test_only]
module satay::mock_simple_staking_strategy {

    use aptos_framework::coin;

    use satay::base_strategy;
    use satay::vault::VaultCapability;

    use satay::staking_pool::{Self, StakingCoin};

    // witness for the strategy
    // used for checking approval when locking and unlocking vault
    struct SimpleStakingStrategy has drop {}

    // initialize vault_id to accept strategy
    public entry fun initialize(
        governance: &signer,
        vault_id: u64,
        debt_ratio: u64
    ) {
        base_strategy::initialize<SimpleStakingStrategy, StakingCoin>(
            governance,
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
        let (
            amount_needed,
            vault_cap,
            stop_handle
        ) = base_strategy::open_vault_for_user_withdraw<SimpleStakingStrategy, BaseCoin, StakingCoin>(
            user,
            manager_addr,
            vault_id,
            share_amount,
            SimpleStakingStrategy {}
        );


        let staking_coins_needed = get_staking_coin_for_base_coin<BaseCoin>(amount_needed);
        let staking_coins = base_strategy::withdraw_strategy_coin<SimpleStakingStrategy, StakingCoin>(
            &vault_cap,
            staking_coins_needed,
            &stop_handle
        );
        let coins = staking_pool::liquidate_position<BaseCoin>(staking_coins);

        base_strategy::close_vault_for_user_withdraw<SimpleStakingStrategy, BaseCoin>(
            manager_addr,
            vault_cap,
            stop_handle,
            coins,
            amount_needed
        );
    }


    // provide a signal to the keepr that `harvest()` should be called
    public entry fun harvest_trigger<BaseCoin>(
        keeper: &signer,
        manager_addr: address,
        vault_id: u64
    ) : bool {
        let (vault_cap, stop_handle) = base_strategy::open_vault_for_harvest<SimpleStakingStrategy, BaseCoin>(
            keeper,
            manager_addr,
            vault_id,
            SimpleStakingStrategy {}
        );

        let harvest_trigger = base_strategy::process_harvest_trigger<SimpleStakingStrategy, BaseCoin>(
            &vault_cap
        );

        base_strategy::close_vault_for_harvest_trigger<SimpleStakingStrategy>(
            manager_addr,
            vault_cap,
            stop_handle
        );

        harvest_trigger
    }

    // harvests the Strategy, realizing any profits or losses and adjusting the Strategy's position.
    public entry fun harvest<CoinType, BaseCoin>(
        keeper: &signer,
        manager_addr: address,
        vault_id: u64
    ) {
        let (vault_cap, stop_handle) = base_strategy::open_vault_for_harvest<SimpleStakingStrategy, BaseCoin>(
            keeper,
            manager_addr,
            vault_id,
            SimpleStakingStrategy {}
        );

        // claim rewards and swap them into BaseCoin
        let staking_coins = staking_pool::reinvest_returns<CoinType, BaseCoin>();
        base_strategy::deposit_strategy_coin<SimpleStakingStrategy, StakingCoin>(
            &mut vault_cap,
            staking_coins,
            &stop_handle
        );

        let strategy_base_coin_balance = get_strategy_base_coin_balance<StakingCoin>(&vault_cap);
        let (to_apply, amount_needed) = base_strategy::process_harvest<SimpleStakingStrategy, BaseCoin, StakingCoin>(
            &mut vault_cap,
            strategy_base_coin_balance,
            &stop_handle
        );

        let staking_coins = staking_pool::apply_position<BaseCoin>(to_apply);
        let base_coins = coin::zero<BaseCoin>();
        if(amount_needed > 0){
            let staking_coins_needed = get_staking_coin_for_base_coin<BaseCoin>(amount_needed);
            let staking_coins = base_strategy::withdraw_strategy_coin<SimpleStakingStrategy, StakingCoin>(
                &vault_cap,
                staking_coins_needed,
                &stop_handle
            );
            coin::merge(
                &mut base_coins,
                staking_pool::liquidate_position<BaseCoin>(staking_coins)
            );
        };

        base_strategy::close_vault_for_harvest<SimpleStakingStrategy, BaseCoin, StakingCoin>(
            manager_addr,
            vault_cap,
            stop_handle,
            base_coins,
            staking_coins
        )
    }

    // adjust the Strategy's position. The purpose of tending isn't to realize gains, but to maximize yield by reinvesting any returns
    public entry fun tend<CoinType, BaseCoin>(
        keeper: &signer,
        manager_addr: address,
        vault_id: u64
    ) {
        let (vault_cap, stop_handle) = base_strategy::open_vault_for_tend<SimpleStakingStrategy, BaseCoin>(
            keeper,
            manager_addr,
            vault_id,
            SimpleStakingStrategy {}
        );

        // claim rewards and swap them into BaseCoin
        let staking_coins = staking_pool::reinvest_returns<CoinType, BaseCoin>();

        base_strategy::close_vault_for_tend<SimpleStakingStrategy, StakingCoin>(
            manager_addr,
            vault_cap,
            stop_handle,
            staking_coins
        )
    }

    fun get_strategy_base_coin_balance<StrategyCoin>(vault_cap: &VaultCapability) : u64 {
        let strategy_coin_balance = base_strategy::balance<StrategyCoin>(vault_cap);
        staking_pool::get_base_coin_for_staking_coin(strategy_coin_balance)
    }

    fun get_staking_coin_for_base_coin<BaseCoin>(base_coin_amount: u64): u64 {
        base_coin_amount
    }

    public fun name() : vector<u8> {
        b"strategy-name"
    }

    public fun version() : vector<u8> {
        b"0.0.1"
    }
}
