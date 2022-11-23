module satay::ditto_farming_strategy {

    use std::signer;

    use aptos_framework::coin::{Self};
    use aptos_framework::aptos_coin::AptosCoin;

    use satay::satay;
    use satay::base_strategy::{Self};
    use satay::vault::VaultCapability;

    use satay_ditto_farming::ditto_farming::{Self, DittoFarmingCoin};

    // witness for the strategy
    // used for checking approval when locking and unlocking vault
    struct DittoStrategy has drop {}

    // initialize vault_id to accept strategy
    public entry fun initialize(
        manager: &signer,
        vault_id: u64,
        debt_ratio: u64
    ) {
        // initialize through base_strategy_module
        base_strategy::initialize<DittoStrategy, DittoFarmingCoin>(
            manager,
            vault_id,
            debt_ratio,
            DittoStrategy {}
        );
    }

    // harvests the Strategy, realizing any profits or losses and adjusting the Strategy's position.
    public entry fun harvest(
        manager: &signer,
        vault_id: u64
    ) {
        let (
            vault_cap,
            stop_handle
        ) = base_strategy::open_vault_for_harvest<DittoStrategy>(
            manager,
            vault_id,
            DittoStrategy {}
        );
        let manager_addr = signer::address_of(manager);

        // TODO: add reinvest_returns once ditto farming is implemented
        // claim rewards and swap them into BaseCoin
        // let (
        //     ditto_farming_coin,
        //     aptos_coins
        // ) = ditto_farming::reinvest_returns(manager);
        // base_strategy::deposit_strategy_coin<DittoFarmingCoin>(&vault_cap, ditto_farming_coin);


        let strategy_aptos_balance = get_strategy_aptos_balance(&vault_cap);
        let (
            to_apply,
            amount_needed,
        ) = base_strategy::process_harvest<DittoStrategy, AptosCoin, DittoFarmingCoin>(
            &mut vault_cap,
            strategy_aptos_balance,
            &stop_handle,
        );

        // TODO: once reinvest returns is implemented, this will be replaced by the returned aptos
        let aptos_coins = coin::zero<AptosCoin>();
        // let residual_apt_amount = coin::value(&aptos_coins);
        // if(amount_needed > residual_apt_amount){
        //     amount_needed = amount_needed - residual_apt_amount;
        // };

        if(amount_needed > 0) {
            let lp_to_liquidate = ditto_farming::get_farming_coin_amount_for_apt_amount(amount_needed);
            let strategy_coins = base_strategy::withdraw_strategy_coin<DittoStrategy, DittoFarmingCoin>(
                &vault_cap,
                lp_to_liquidate,
                &stop_handle
            );
            let liquidated_aptos_coins = ditto_farming::liquidate_position(
                strategy_coins,
            );
            let liquidated_aptos_coins_amount = coin::value<AptosCoin>(&liquidated_aptos_coins);

            if (liquidated_aptos_coins_amount > amount_needed) {
                coin::merge(
                    &mut to_apply,
                    coin::extract(
                        &mut liquidated_aptos_coins,
                        liquidated_aptos_coins_amount - amount_needed
                    )
                );
            };
            coin::merge(&mut aptos_coins, liquidated_aptos_coins)
        };

        let (ditto_strategy_coins, residual_apt) = ditto_farming::apply_position(
            to_apply,
            manager_addr,
        );
        coin::merge(&mut aptos_coins, residual_apt);

        base_strategy::close_vault_for_harvest<DittoStrategy, AptosCoin, DittoFarmingCoin>(
            signer::address_of(manager),
            vault_cap,
            stop_handle,
            aptos_coins,
            ditto_strategy_coins
        )
    }

    // provide a signal to the keeper that `harvest()` should be called
    public entry fun harvest_trigger(
        manager: &signer,
        vault_id: u64
    ): bool {
        let (vault_cap, stop_handle) = base_strategy::open_vault_for_harvest<DittoStrategy>(
            manager,
            vault_id,
            DittoStrategy {}
        );

        let harvest_trigger = base_strategy::process_harvest_trigger<DittoStrategy, AptosCoin>(
            &vault_cap
        );

        base_strategy::close_vault_for_harvest_trigger<DittoStrategy>(
            signer::address_of(manager),
            vault_cap,
            stop_handle
        );

        harvest_trigger
    }

    // tend

    // admin functions

    // called when vault does not have enough BaseCoin in reserves, and must reclaim funds from strategy
    public entry fun withdraw_for_user(
        user: &signer,
        manager_addr: address,
        vault_id: u64,
        share_amount: u64
    ) {
        let (
            amount_aptos_needed,
            vault_cap,
            stop_handle
        ) = base_strategy::open_vault_for_user_withdraw<DittoStrategy, AptosCoin, DittoFarmingCoin>(
            user,
            manager_addr,
            vault_id,
            share_amount,
            DittoStrategy {}
        );

        let lp_to_burn = ditto_farming::get_farming_coin_amount_for_apt_amount(amount_aptos_needed);
        let strategy_coins = base_strategy::withdraw_strategy_coin<DittoStrategy, DittoFarmingCoin>(
            &vault_cap,
            lp_to_burn,
            &stop_handle
        );
        let coins = ditto_farming::liquidate_position(strategy_coins);

        base_strategy::close_vault_for_user_withdraw<DittoStrategy, AptosCoin>(
            manager_addr,
            vault_cap,
            stop_handle,
            coins,
            amount_aptos_needed
        );
    }

    // update the strategy debt ratio
    public entry fun update_debt_ratio(
        manager: &signer,
        vault_id: u64,
        debt_ratio: u64
    ) {
        satay::update_strategy_debt_ratio<DittoStrategy>(
            manager,
            vault_id,
            debt_ratio
        );
    }

    // update the strategy max report delay
    public entry fun update_max_report_delay(
        manager: &signer,
        vault_id: u64,
        max_report_delay: u64
    ) {
        satay::update_strategy_max_report_delay<DittoStrategy>(
            manager,
            vault_id,
            max_report_delay
        );
    }

    // update the strategy credit threshold
    public entry fun update_credit_threshold(
        manager: &signer,
        vault_id: u64,
        credit_threshold: u64
    ) {
        satay::update_strategy_credit_threshold<DittoStrategy>(
            manager,
            vault_id,
            credit_threshold
        );
    }

    // set the strategy force harvest trigger once
    public entry fun set_force_harvest_trigger_once(
        manager: &signer,
        vault_id: u64,
    ) {
        satay::set_strategy_force_harvest_trigger_once<DittoStrategy>(
            manager,
            vault_id
        );
    }

    // revoke the strategy
    public entry fun revoke(manager: &signer, vault_id: u64) {
        satay::update_strategy_debt_ratio<DittoStrategy>(manager, vault_id, 0);
    }

    // get total AptosCoin balance for strategy
    fun get_strategy_aptos_balance(vault_cap: &VaultCapability) : u64 {
        // 1. get user staked LP amount to ditto LP layer (interface missing from Ditto)
        let ditto_staked_lp_amount = base_strategy::balance<DittoFarmingCoin>(vault_cap);
        // 2. convert LP coin to aptos
        ditto_farming::get_apt_amount_for_farming_coin_amount(ditto_staked_lp_amount)
    }

    public fun name() : vector<u8> {
        b"Ditto LP Farming Strategy"
    }

    public fun version() : vector<u8> {
        b"0.0.1"
    }
}
