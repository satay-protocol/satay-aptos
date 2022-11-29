module satay::tortuga_leveraged_farming_strategy {

    use std::signer;

    use aptos_framework::aptos_coin::AptosCoin;

    use satay::satay;
    use satay::base_strategy::{Self};
    use satay::vault::VaultCapability;
    use satay_tortuga_farming::tortuga_farming::TortugaFarmingCoin;
    use satay_tortuga_farming::tortuga_farming;
    use aptos_framework::coin;

    // witness for the strategy
    // used for checking approval when locking and unlocking vault
    struct TortugaStrategy has drop {}

    // initialize vault_id to accept strategy
    public entry fun initialize(
        manager: &signer,
        vault_id: u64,
        debt_ratio: u64
    ) {
        // initialize through base_strategy_module
        base_strategy::initialize<TortugaStrategy, TortugaFarmingCoin>(
            manager,
            vault_id,
            debt_ratio,
            TortugaStrategy {}
        );
    }

    // harvests the Strategy, realizing any profits or losses and adjusting the Strategy's position.
    public entry fun harvest(
        manager: &signer,
        vault_id: u64
    ) {
        let (vault_cap, stop_handle) = base_strategy::open_vault_for_harvest<TortugaStrategy>(
            manager,
            vault_id,
            TortugaStrategy {}
        );

        let manager_addr = signer::address_of(manager);
        let strategy_aptos_balance = get_strategy_aptos_balance(&vault_cap);

        let (
            to_apply,
            amount_needed,
        ) = base_strategy::process_harvest<TortugaStrategy, AptosCoin, TortugaFarmingCoin>(
            &mut vault_cap,
            strategy_aptos_balance,
            TortugaStrategy {}
        );

        let aptos_coins = coin::zero<AptosCoin>();

        if(amount_needed > 0) {
            let tapt_to_liquidate = tortuga_farming::get_farming_coin_amount_for_apt_amount(amount_needed);
            let strategy_coins = base_strategy::withdraw_strategy_coin<TortugaStrategy, TortugaFarmingCoin>(
                &vault_cap,
                tapt_to_liquidate,
                TortugaStrategy {}
            );
            let liquidated_aptos_coins = tortuga_farming::liquidate_position(
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

        let (ditto_strategy_coins, residual_apt) = tortuga_farming::apply_position(
            to_apply,
            manager_addr,
        );
        coin::merge(&mut aptos_coins, residual_apt);

        base_strategy::close_vault_for_harvest<TortugaStrategy, AptosCoin, TortugaFarmingCoin>(
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
        let (vault_cap, stop_handle) = base_strategy::open_vault_for_harvest<TortugaStrategy>(
            manager,
            vault_id,
            TortugaStrategy {}
        );

        let harvest_trigger = base_strategy::process_harvest_trigger<TortugaStrategy, AptosCoin>(
            &vault_cap
        );

        base_strategy::close_vault_for_harvest_trigger<TortugaStrategy>(
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
        ) = base_strategy::open_vault_for_user_withdraw<TortugaStrategy, AptosCoin, TortugaFarmingCoin>(
            user,
            manager_addr,
            vault_id,
            share_amount,
            TortugaStrategy {}
        );

        let tapt_amount = tortuga_farming::get_farming_coin_amount_for_apt_amount(amount_aptos_needed);
        let strategy_coins = base_strategy::withdraw_strategy_coin<TortugaStrategy, TortugaFarmingCoin>(
            &vault_cap,
            tapt_amount,
            TortugaStrategy {}
        );
        let coins = tortuga_farming::liquidate_position(strategy_coins);

        base_strategy::close_vault_for_user_withdraw<TortugaStrategy, AptosCoin>(
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
        satay::update_strategy_debt_ratio<TortugaStrategy>(
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
        satay::update_strategy_max_report_delay<TortugaStrategy>(
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
        satay::update_strategy_credit_threshold<TortugaStrategy>(
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
        satay::set_strategy_force_harvest_trigger_once<TortugaStrategy>(
            manager,
            vault_id
        );
    }

    // revoke the strategy
    public entry fun revoke(manager: &signer, vault_id: u64) {
        satay::update_strategy_debt_ratio<TortugaStrategy>(manager, vault_id, 0);
    }

    // get total AptosCoin balance for strategy
    fun get_strategy_aptos_balance(_vault_cap: &VaultCapability) : u64 {
        0
    }

    public fun name() : vector<u8> {
        b"Tortuga Leveraged Farming Strategy"
    }

    public fun version() : vector<u8> {
        b"0.0.1"
    }
}
