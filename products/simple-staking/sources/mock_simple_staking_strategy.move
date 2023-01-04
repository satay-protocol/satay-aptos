#[test_only]
module satay_simple_staking::mock_simple_staking_strategy {

    use aptos_framework::coin;

    use satay::base_strategy;
    use satay::vault::VaultCapability;

    use satay_simple_staking::staking_pool::{Self, StakingCoin};

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
        vault_id: u64,
        share_amount: u64
    ) {
        let (
            vault_cap,
            user_withdaw_lock
        ) = base_strategy::open_vault_for_user_withdraw<SimpleStakingStrategy, BaseCoin, StakingCoin>(
            user,
            vault_id,
            share_amount,
            SimpleStakingStrategy {}
        );

        let amount_needed = base_strategy::get_user_withdraw_amount_needed(&user_withdaw_lock);
        let staking_coins_needed = get_staking_coin_for_base_coin<BaseCoin>(amount_needed);
        let staking_coins = base_strategy::withdraw_strategy_coin<SimpleStakingStrategy, StakingCoin>(
            &vault_cap,
            staking_coins_needed,
            base_strategy::get_user_withdraw_vault_cap_lock(&user_withdaw_lock)
        );
        let debt_payment = staking_pool::liquidate_position<BaseCoin>(staking_coins);

        base_strategy::close_vault_for_user_withdraw<SimpleStakingStrategy, BaseCoin>(
            vault_cap,
            user_withdaw_lock,
            debt_payment
        );
    }

    // harvests the Strategy, realizing any profits or losses and adjusting the Strategy's position.
    public entry fun harvest<CoinType, BaseCoin>(
        keeper: &signer,
        vault_id: u64
    ) {
        let (vault_cap, vault_cap_lock) = base_strategy::open_vault_for_harvest<SimpleStakingStrategy, BaseCoin>(
            keeper,
            vault_id,
            SimpleStakingStrategy {}
        );

        // claim rewards and swap them into BaseCoin
        let staking_coins = staking_pool::reinvest_returns<CoinType, BaseCoin>();
        base_strategy::deposit_strategy_coin<SimpleStakingStrategy, StakingCoin>(
            &mut vault_cap,
            staking_coins,
            &vault_cap_lock
        );

        let strategy_base_coin_balance = get_strategy_base_coin_balance<StakingCoin>(&vault_cap);
        let (to_apply, harvest_lock) = base_strategy::process_harvest<SimpleStakingStrategy, BaseCoin, StakingCoin>(
            &mut vault_cap,
            strategy_base_coin_balance,
            vault_cap_lock
        );

        let debt_payment_amount = base_strategy::get_harvest_debt_payment(&harvest_lock);
        let profit_amount = base_strategy::get_harvest_profit(&harvest_lock);

        let debt_payment = coin::zero<BaseCoin>();
        let profit = coin::zero<BaseCoin>();

        if(debt_payment_amount > 0){
            let staking_coins_needed = get_staking_coin_for_base_coin<BaseCoin>(debt_payment_amount);
            let staking_coins = base_strategy::withdraw_strategy_coin<SimpleStakingStrategy, StakingCoin>(
                &vault_cap,
                staking_coins_needed,
                base_strategy::get_harvest_vault_cap_lock(&harvest_lock)
            );
            coin::merge(
                &mut debt_payment,
                staking_pool::liquidate_position<BaseCoin>(staking_coins)
            );
        };
        if(profit_amount > 0){
            let staking_coins_needed = get_staking_coin_for_base_coin<BaseCoin>(profit_amount);
            let staking_coins = base_strategy::withdraw_strategy_coin<SimpleStakingStrategy, StakingCoin>(
                &vault_cap,
                staking_coins_needed,
                base_strategy::get_harvest_vault_cap_lock(&harvest_lock)
            );
            coin::merge(
                &mut profit,
                staking_pool::liquidate_position<BaseCoin>(staking_coins)
            );
        };

        let staking_coins = staking_pool::apply_position<BaseCoin>(to_apply);

        base_strategy::close_vault_for_harvest<SimpleStakingStrategy, BaseCoin, StakingCoin>(
            vault_cap,
            harvest_lock,
            debt_payment,
            profit,
            staking_coins
        )
    }

    // adjust the Strategy's position. The purpose of tending isn't to realize gains, but to maximize yield by reinvesting any returns
    public entry fun tend<CoinType, BaseCoin>(
        keeper: &signer,
        vault_id: u64
    ) {
        let (vault_cap, tend_lock) = base_strategy::open_vault_for_tend<SimpleStakingStrategy, BaseCoin>(
            keeper,
            vault_id,
            SimpleStakingStrategy {}
        );

        // claim rewards and swap them into BaseCoin
        let staking_coins = staking_pool::reinvest_returns<CoinType, BaseCoin>();

        base_strategy::close_vault_for_tend<SimpleStakingStrategy, StakingCoin>(
            vault_cap,
            tend_lock,
            staking_coins
        )
    }

    // update the strategy debt ratio
    public entry fun update_debt_ratio<BaseCoin>(
        vault_manager: &signer,
        vault_id: u64,
        debt_ratio: u64
    ) {
        base_strategy::update_debt_ratio<SimpleStakingStrategy, BaseCoin>(
            vault_manager,
            vault_id,
            debt_ratio,
            SimpleStakingStrategy {}
        );
    }

    // revoke the strategy
    public entry fun revoke<CoinType, BaseCoin>(
        vault_manager: &signer,
        vault_id: u64
    ) {
        base_strategy::revoke_strategy<SimpleStakingStrategy, BaseCoin>(
            vault_manager,
            vault_id,
            SimpleStakingStrategy {}
        );
        harvest<CoinType, BaseCoin>(vault_manager, vault_id);
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
