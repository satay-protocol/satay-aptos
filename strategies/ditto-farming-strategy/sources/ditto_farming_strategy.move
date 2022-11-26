module satay_ditto_farming_strategy::ditto_farming_strategy {

    use std::signer;

    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::account::{Self, SignerCapability};

    use satay::base_strategy::{Self};
    use satay::vault::VaultCapability;

    use satay_ditto_farming::ditto_farming::{Self, DittoFarmingCoin};

    const ERR_NOT_AUTHORIZED: u64 = 1;

    // witness for the strategy
    // used for checking approval when locking and unlocking vault
    struct DittoStrategy has drop {}

    // needed to store residual aptos during harvest
    struct DittoStrategyAccount has key {
        signer_cap: SignerCapability
    }

    // create resource account to store residual aptos during harvest
    public entry fun create_ditto_strategy_account(
        satay_ditto_famring_strategy: &signer
    ) {
        assert!(signer::address_of(satay_ditto_famring_strategy) == @satay_ditto_farming_strategy, ERR_NOT_AUTHORIZED);
        let (strategy_account, signer_cap) = account::create_resource_account(
            satay_ditto_famring_strategy,
            b"ditto strategy account",
        );
        move_to(satay_ditto_famring_strategy, DittoStrategyAccount {
            signer_cap
        });
        coin::register<AptosCoin>(&strategy_account);
    }

    // initialize vault_id to accept strategy
    public entry fun initialize(
        governance: &signer,
        vault_id: u64,
        debt_ratio: u64
    ) {
        // initialize through base_strategy_module
        base_strategy::initialize<DittoStrategy, DittoFarmingCoin>(
            governance,
            vault_id,
            debt_ratio,
            DittoStrategy {}
        );
    }

    // harvests the Strategy, realizing any profits or losses and adjusting the Strategy's position.
    public entry fun harvest(
        keeper: &signer,
        vault_id: u64
    ) acquires DittoStrategyAccount {
        let (
            vault_cap,
            stop_handle
        ) = base_strategy::open_vault_for_harvest<DittoStrategy, AptosCoin>(
            keeper,
            vault_id,
            DittoStrategy {}
        );

        let ditto_strategy_cap = borrow_global_mut<DittoStrategyAccount>(@satay_ditto_farming_strategy);
        let ditto_strategy_signer = account::create_signer_with_capability(&ditto_strategy_cap.signer_cap);
        let ditto_strategy_addr = signer::address_of(&ditto_strategy_signer);

        // claim and reinvest rewards
        let (
            ditto_farming_coin,
            residual_aptos_coin
        ) = ditto_farming::reinvest_returns(keeper);
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
            &vault_cap,
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
            coin::merge(&mut to_return, liquidated_aptos_coins)
        };

        // deploy to_apply AptosCoin to ditto_farming structured product
        let (ditto_strategy_coins, residual) = ditto_farming::apply_position(
            to_apply,
            @satay_ditto_farming_strategy,
        );
        // store residual amount on strategy account
        coin::deposit(ditto_strategy_addr, residual);

        base_strategy::close_vault_for_harvest<DittoStrategy, AptosCoin, DittoFarmingCoin>(
            vault_cap,
            stop_handle,
            to_return,
            ditto_strategy_coins
        )
    }

    // provide a signal to the keeper that `harvest()` should be called
    public entry fun harvest_trigger(
        keeper: &signer,
        vault_id: u64
    ): bool {
        let (vault_cap, stop_handle) = base_strategy::open_vault_for_harvest<DittoStrategy, AptosCoin>(
            keeper,
            vault_id,
            DittoStrategy {}
        );

        let harvest_trigger = base_strategy::process_harvest_trigger<DittoStrategy, AptosCoin>(
            &vault_cap
        );

        base_strategy::close_vault_for_harvest_trigger<DittoStrategy>(
            vault_cap,
            stop_handle
        );

        harvest_trigger
    }

    // tend

    public entry fun tend(
        keeper: &signer,
        vault_id: u64
    ) acquires DittoStrategyAccount {
        let (vault_cap, stop_handle) = base_strategy::open_vault_for_tend<DittoStrategy, AptosCoin>(
            keeper,
            vault_id,
            DittoStrategy {}
        );

        let ditto_strategy_account = borrow_global_mut<DittoStrategyAccount>(@satay_ditto_farming_strategy);
        let ditto_strategy_addr = account::get_signer_capability_address(&ditto_strategy_account.signer_cap);

        let (
            ditto_farming_coin,
            residual_aptos_coin
        ) = ditto_farming::reinvest_returns(keeper);
        coin::deposit(ditto_strategy_addr, residual_aptos_coin);

        base_strategy::close_vault_for_tend<DittoStrategy, DittoFarmingCoin>(
            vault_cap,
            stop_handle,
            ditto_farming_coin
        )
    }

    // admin functions

    // called when vault does not have enough BaseCoin in reserves, and must reclaim funds from strategy
    public entry fun withdraw_for_user(
        user: &signer,
        vault_id: u64,
        share_amount: u64
    ) acquires DittoStrategyAccount {
        let (
            amount_aptos_needed,
            vault_cap,
            stop_handle
        ) = base_strategy::open_vault_for_user_withdraw<DittoStrategy, AptosCoin, DittoFarmingCoin>(
            user,
            vault_id,
            share_amount,
            DittoStrategy {}
        );

        let ditto_strategy_account = borrow_global_mut<DittoStrategyAccount>(@satay_ditto_farming_strategy);
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
            let lp_to_burn = ditto_farming::get_farming_coin_amount_for_apt_amount(amount_aptos_needed);
            let strategy_coins = base_strategy::withdraw_strategy_coin<DittoStrategy, DittoFarmingCoin>(
                &vault_cap,
                lp_to_burn,
                &stop_handle
            );
            coin::merge(
                &mut to_return,
                ditto_farming::liquidate_position(strategy_coins)
            );
        };

        base_strategy::close_vault_for_user_withdraw<DittoStrategy, AptosCoin>(
            vault_cap,
            stop_handle,
            to_return,
            amount_aptos_needed
        );
    }

    // update the strategy debt ratio
    public entry fun update_debt_ratio(
        vault_manager: &signer,
        vault_id: u64,
        debt_ratio: u64
    ) {
        base_strategy::update_debt_ratio<DittoStrategy, AptosCoin>(
            vault_manager,
            vault_id,
            debt_ratio
        );
    }

    // update the strategy credit threshold
    public entry fun update_credit_threshold(
        vault_manager: &signer,
        vault_id: u64,
        credit_threshold: u64
    ) {
        base_strategy::update_credit_threshold<DittoStrategy, AptosCoin>(
            vault_manager,
            vault_id,
            credit_threshold
        );
    }

    // set the strategy force harvest trigger once
    public entry fun set_force_harvest_trigger_once(
        vault_manager: &signer,
        vault_id: u64,
    ) {
        base_strategy::set_force_harvest_trigger_once<DittoStrategy, AptosCoin>(
            vault_manager,
            vault_id
        );
    }

    // update the strategy max report delay
    public entry fun update_max_report_delay(
        strategist: &signer,
        vault_id: u64,
        max_report_delay: u64
    ) {
        base_strategy::update_max_report_delay<DittoStrategy, AptosCoin>(
            strategist,
            vault_id,
            max_report_delay
        );
    }

    // revoke the strategy
    public entry fun revoke(
        governance: &signer,
        vault_id: u64
    ) {
        base_strategy::revoke<DittoStrategy>(
            governance,
            vault_id
        );
    }

    // get total AptosCoin balance for strategy
    fun get_strategy_aptos_balance(
        vault_cap: &VaultCapability,
        residual_aptos: &Coin<AptosCoin>
    ): u64 {
        // get strategy staked LP amount
        let ditto_staked_lp_amount = base_strategy::balance<DittoFarmingCoin>(vault_cap);
        // convert LP coin to aptos
        let deployed_balance = ditto_farming::get_apt_amount_for_farming_coin_amount(ditto_staked_lp_amount);
        coin::value(residual_aptos) + deployed_balance
    }

    public fun name() : vector<u8> {
        b"Ditto LP Farming Strategy"
    }

    public fun version() : vector<u8> {
        b"0.0.1"
    }
}