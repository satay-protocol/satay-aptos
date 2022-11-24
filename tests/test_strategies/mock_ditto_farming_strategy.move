#[test_only]
module satay::mock_ditto_farming_strategy {

    use std::signer;

    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::account::{Self, SignerCapability};

    use satay::satay;
    use satay::base_strategy::{Self};
    use satay::vault::VaultCapability;

    use satay_ditto_farming::mock_ditto_farming::{Self, DittoFarmingCoin};

    // witness for the strategy
    // used for checking approval when locking and unlocking vault
    struct DittoStrategy has drop {}

    // needed to store residual aptos during harvest
    struct DittoStrategyAccount has key {
        signer_cap: SignerCapability
    }

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

        // create resource account to store residual aptos during harvest
        let (strategy_account, signer_cap) = account::create_resource_account(
            manager,
            b"ditto strategy account",
        );
        move_to(manager, DittoStrategyAccount {
            signer_cap
        });
        coin::register<AptosCoin>(&strategy_account);

    }

    // harvests the Strategy, realizing any profits or losses and adjusting the Strategy's position.
    public entry fun harvest(
        manager: &signer,
        vault_id: u64
    ) acquires DittoStrategyAccount {
        let (
            vault_cap,
            stop_handle
        ) = base_strategy::open_vault_for_harvest<DittoStrategy>(
            manager,
            vault_id,
            DittoStrategy {}
        );

        let manager_addr = signer::address_of(manager);
        let ditto_strategy_cap = borrow_global_mut<DittoStrategyAccount>(manager_addr);
        let ditto_strategy_signer = account::create_signer_with_capability(&ditto_strategy_cap.signer_cap);
        let ditto_strategy_addr = signer::address_of(&ditto_strategy_signer);

        // claim and reinvest rewards
        let (
            ditto_farming_coin,
            residual_aptos_coin
        ) = mock_ditto_farming::reinvest_returns(manager);
        base_strategy::deposit_strategy_coin<DittoStrategy, DittoFarmingCoin>(
            &vault_cap,
            ditto_farming_coin,
            &stop_handle
        );
        coin::deposit(ditto_strategy_addr, residual_aptos_coin);

        // withdraw residual aptos
        let residual_aptos_balance = coin::balance<AptosCoin>(ditto_strategy_addr);
        let residual_aptos = coin::withdraw<AptosCoin>(
            &ditto_strategy_signer,
            residual_aptos_balance
        );
        // get strategy aptos balance and process harvest
        let strategy_aptos_balance = get_strategy_aptos_balance(
            &vault_cap,
            &residual_aptos
        );
        let (
            to_apply,
            amount_needed,
        ) = base_strategy::process_harvest<DittoStrategy, AptosCoin, DittoFarmingCoin>(
            &mut vault_cap,
            strategy_aptos_balance,
            &stop_handle,
        );

        let to_return = coin::zero<AptosCoin>();

        if(amount_needed > residual_aptos_balance){ // not enough aptos to fill amount needed
            coin::merge(
                &mut to_return,
                coin::extract<AptosCoin>(&mut residual_aptos, residual_aptos_balance)
            );
            amount_needed = amount_needed - residual_aptos_balance;
        } else { // enough aptos to fill amount needed
            coin::merge(
                &mut to_return,
                coin::extract<AptosCoin>(&mut residual_aptos, amount_needed)
            );
            amount_needed = 0;
            coin::merge(
                &mut to_apply,
                coin::extract_all<AptosCoin>(&mut residual_aptos)
            );
        };
        coin::destroy_zero(residual_aptos);

        // if amount is still needed, liquidate farming coins to return
        if(amount_needed > 0) {
            let lp_to_liquidate = mock_ditto_farming::get_farming_coin_amount_for_apt_amount(amount_needed);
            let strategy_coins = base_strategy::withdraw_strategy_coin<DittoStrategy, DittoFarmingCoin>(
                &vault_cap,
                lp_to_liquidate,
                &stop_handle
            );
            let liquidated_aptos_coins = mock_ditto_farming::liquidate_position(
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
            coin::merge(&mut to_return, liquidated_aptos_coins)
        };

        // deploy to_apply AptosCoin to ditto_farming structured product
        let (ditto_strategy_coins, residual) = mock_ditto_farming::apply_position(
            to_apply,
            manager_addr,
        );
        // store residual amount on strategy account
        coin::deposit(ditto_strategy_addr, residual);

        base_strategy::close_vault_for_harvest<DittoStrategy, AptosCoin, DittoFarmingCoin>(
            signer::address_of(manager),
            vault_cap,
            stop_handle,
            to_return,
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

    public entry fun tend(
        manager: &signer,
        vault_id: u64
    ) acquires DittoStrategyAccount {
        let (vault_cap, stop_handle) = base_strategy::open_vault_for_tend<DittoStrategy, AptosCoin>(
            manager,
            vault_id,
            DittoStrategy {}
        );

        let manager_addr = signer::address_of(manager);

        let ditto_strategy_account = borrow_global_mut<DittoStrategyAccount>(manager_addr);
        let ditto_strategy_addr = account::get_signer_capability_address(&ditto_strategy_account.signer_cap);

        let (
            ditto_farming_coin,
            residual_aptos_coin
        ) = mock_ditto_farming::reinvest_returns(manager);
        coin::deposit(ditto_strategy_addr, residual_aptos_coin);

        base_strategy::close_vault_for_tend<DittoStrategy, DittoFarmingCoin>(
            signer::address_of(manager),
            vault_cap,
            stop_handle,
            ditto_farming_coin
        )
    }

    // admin functions

    // called when vault does not have enough BaseCoin in reserves, and must reclaim funds from strategy
    public entry fun withdraw_for_user(
        user: &signer,
        manager_addr: address,
        vault_id: u64,
        share_amount: u64
    ) acquires DittoStrategyAccount {
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

        let ditto_strategy_account = borrow_global_mut<DittoStrategyAccount>(manager_addr);
        let ditto_strategy_signer = account::create_signer_with_capability(&ditto_strategy_account.signer_cap);
        let ditto_strategy_addr = signer::address_of(&ditto_strategy_signer);

        let to_return = coin::zero<AptosCoin>();
        let residual_aptos_balance = coin::balance<AptosCoin>(ditto_strategy_addr);
        if(residual_aptos_balance < amount_aptos_needed){
            coin::merge(
                &mut to_return,
                coin::withdraw<AptosCoin>(&ditto_strategy_signer, residual_aptos_balance)
            );
            amount_aptos_needed = amount_aptos_needed - residual_aptos_balance;
        } else {
            coin::merge(
                &mut to_return,
                coin::withdraw<AptosCoin>(&ditto_strategy_signer, amount_aptos_needed)
            );
            amount_aptos_needed = 0;
        };

        if(amount_aptos_needed > 0){
            let lp_to_burn = mock_ditto_farming::get_farming_coin_amount_for_apt_amount(amount_aptos_needed);
            let strategy_coins = base_strategy::withdraw_strategy_coin<DittoStrategy, DittoFarmingCoin>(
                &vault_cap,
                lp_to_burn,
                &stop_handle
            );
            coin::merge(
                &mut to_return,
                mock_ditto_farming::liquidate_position(strategy_coins)
            );
        };

        base_strategy::close_vault_for_user_withdraw<DittoStrategy, AptosCoin>(
            manager_addr,
            vault_cap,
            stop_handle,
            to_return,
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
    fun get_strategy_aptos_balance(
        vault_cap: &VaultCapability,
        residual_aptos: &Coin<AptosCoin>
    ): u64 {
        // get strategy staked LP amount
        let ditto_staked_lp_amount = base_strategy::balance<DittoFarmingCoin>(vault_cap);
        // convert LP coin to aptos
        let deployed_balance = mock_ditto_farming::get_apt_amount_for_farming_coin_amount(ditto_staked_lp_amount);
        coin::value(residual_aptos) + deployed_balance
    }

    public fun name() : vector<u8> {
        b"Ditto LP Farming Strategy"
    }

    public fun version() : vector<u8> {
        b"0.0.1"
    }
}
