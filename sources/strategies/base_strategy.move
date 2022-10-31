module satay::base_strategy {

    use aptos_framework::coin::{Coin};
    use std::signer;
    use satay::satay;
    use aptos_std::type_info;
    use satay::vault::{Self, VaultCapability};
    use aptos_framework::coin;
    use satay::satay::VaultCapLock;

    const ERR_NOT_ENOUGH_FUND: u64 = 301;
    const ERR_ENOUGH_BALANCE_ON_VAULT: u64 = 302;
    const ERR_LOSS: u64 = 303;

    // initialize vault_id to accept strategy
    public fun initialize<StrategyType: drop, StrategyCoin>(manager: &signer, vault_id: u64, debt_ratio: u64, witness: StrategyType) {
        // approve strategy on vault
        satay::approve_strategy<StrategyType>(manager, vault_id, type_info::type_of<StrategyCoin>(), debt_ratio);

        // add a CoinStore for the StrategyCoin
        let manager_addr = signer::address_of(manager);
        let (vault_cap, stop_handle) = satay::lock_vault<StrategyType>(manager_addr, vault_id, witness);
        if (!vault::has_coin<StrategyCoin>(&vault_cap)) {
            vault::add_coin<StrategyCoin>(&vault_cap);
        };
        satay::unlock_vault<StrategyType>(manager_addr, vault_cap, stop_handle);
    }

    // for withdraw_for_user
    // reclaim funds from StrategyType when vault does not have enough BaseCoin given a share_amount

    // open vault, returing StrategyCoin to liquidate, VaultCapability, and VaultCapLock
    public fun open_vault_for_user_withdraw<StrategyType: drop, BaseCoin, StrategyCoin>(
        user: &signer,
        manager_addr: address,
        vault_id: u64,
        share_amount: u64,
        witness: StrategyType
    ) : (Coin<StrategyCoin>, VaultCapability, VaultCapLock) {
        let (vault_cap, stop_handle) = open_vault<StrategyType>(manager_addr, vault_id, witness);

        // check if user is eligible to withdraw
        let user_share_amount = coin::balance<vault::VaultCoin<BaseCoin>>(signer::address_of(user));
        assert!(user_share_amount >= share_amount, ERR_NOT_ENOUGH_FUND);

        // check if vault has enough balance
        let user_amount = vault::calculate_base_coin_amount_from_share<BaseCoin>(&vault_cap, share_amount);
        assert!(vault::balance<BaseCoin>(&vault_cap) < user_amount, ERR_ENOUGH_BALANCE_ON_VAULT);

        let strategy_coins_amount = vault::calculate_strategy_coin_amount_from_share<BaseCoin, StrategyCoin>(
            &vault_cap,
            share_amount
        );
        let strategy_coins_to_liquidate = vault::withdraw<StrategyCoin>(
            &vault_cap,
            strategy_coins_amount
        );

        (strategy_coins_to_liquidate, vault_cap, stop_handle)
    }


    public fun close_vault_for_user_withdraw<StrategyType: drop, BaseCoin>(
        manager_addr: address,
        vault_cap: VaultCapability,
        stop_handle: VaultCapLock,
        coins: Coin<BaseCoin>,
    ) {
        vault::update_total_debt<StrategyType>(&mut vault_cap, 0, coin::value(&coins));
        vault::deposit<BaseCoin>(&vault_cap, coins);
        close_vault<StrategyType>(manager_addr, vault_cap, stop_handle);
    }

    // for harvest

    public fun open_vault_for_harvest<StrategyType: drop, BaseCoin>(
        manager: &signer,
        vault_id: u64,
        witness: StrategyType,
    ) :  (VaultCapability, VaultCapLock) {
        open_vault<StrategyType>(
            signer::address_of(manager),
            vault_id,
            witness
        )
    }

    public fun deposit_strategy_coin<StrategyCoin>(
        vault_cap: &VaultCapability,
        strategy_coins: Coin<StrategyCoin>
    ) {
        vault::deposit<StrategyCoin>(vault_cap, strategy_coins);
    }

    public fun process_harvest<StrategyType: drop, BaseCoin, StrategyCoin>(
        vault_cap: &mut VaultCapability,
        witness: StrategyType
    ) : (Coin<BaseCoin>, Coin<StrategyCoin>) {

        let strategy_balance = vault_balance<StrategyCoin>(vault_cap);
        let (profit, loss, debt_payment) = prepare_return<StrategyType, BaseCoin>(vault_cap, strategy_balance);

        // loss to report, do it before the rest of the calculation
        if (loss > 0) {
            let total_debt = vault::total_debt<StrategyType>(vault_cap);
            assert!(total_debt >= loss, ERR_LOSS);
            vault::report_loss<StrategyType>(vault_cap, loss);
        };

        let credit = vault::credit_available<StrategyType, BaseCoin>(vault_cap);
        let debt = vault::debt_out_standing<StrategyType, BaseCoin>(vault_cap);
        if (debt_payment > debt) {
            debt_payment = debt;
        };

        if (credit > 0 || debt_payment > 0) {
            vault::update_total_debt<StrategyType>(vault_cap, credit, debt_payment);
        };

        let total_available = profit + debt_payment;

        if (profit > 0) {
            assess_fees<StrategyType, BaseCoin>(profit, vault_cap, witness);
        };

        let to_apply= coin::zero<BaseCoin>();
        let to_liquidate = coin::zero<StrategyCoin>();
        if (total_available < credit) { // credit surplus, give to Strategy
            coin::merge(
                &mut to_apply,
                vault::withdraw<BaseCoin>(vault_cap, credit - total_available)
            );
            vault::update_total_debt<StrategyType>(
                vault_cap,
                credit - total_available,
                0
            )
        } else { // credit deficit, take from Strategy
            coin::merge(
                &mut to_liquidate,
                vault::withdraw<StrategyCoin>(vault_cap, total_available - credit)
            );
        };

        (to_apply, to_liquidate)
    }

    public fun close_vault_for_harvest<StrategyType: drop, BaseCoin, StrategyCoin>(
        manager_addr: address,
        vault_cap: VaultCapability,
        stop_handle: VaultCapLock,
        base_coins: Coin<BaseCoin>,
        strategy_coins: Coin<StrategyCoin>
    ) {
        if(coin::value(&base_coins) > 0){
            vault::update_total_debt<StrategyType>(
                &mut vault_cap,
                0,
                coin::value(&base_coins)
            );
        };
        vault::deposit(&vault_cap, base_coins);
        vault::deposit(&vault_cap, strategy_coins);
        close_vault<StrategyType>(
            manager_addr,
            vault_cap,
            stop_handle
        );
    }

    // returns any realized profits, realized losses incurred, and debt payments to be made
    // called by harvest
    public fun prepare_return<StrategyType: drop, BaseCoin>(
        vault_cap: &VaultCapability,
        strategy_balance: u64
    ) : (u64, u64, u64) {

        // get amount of strategy debt over limit
        let debt_out_standing = vault::debt_out_standing<StrategyType, BaseCoin>(vault_cap);
        // strategy's total debt
        let total_debt = vault::total_debt<StrategyType>(vault_cap);

        let profit = 0;
        let loss = 0;
        let debt_payment: u64;
        // staking pool has more BaseCoin than outstanding debt
        if (strategy_balance > debt_out_standing) {
            // amount to return = outstanding debt
            debt_payment = debt_out_standing;
            // amount in staking pool decreases by debt payment
            strategy_balance = strategy_balance - debt_payment;
        } else {
            // amount to return = all assets
            debt_payment = strategy_balance;
            strategy_balance = 0;
        };
        total_debt = total_debt - debt_payment;

        if (strategy_balance > total_debt) {
            profit = strategy_balance - total_debt;
        } else {
            loss = total_debt - strategy_balance;
        };

        (profit, loss, debt_payment)
    }

    public fun vault_balance<CoinType>(
        vault_cap: &VaultCapability
    ) : u64 {
        vault::balance<CoinType>(vault_cap)
    }

    // calls a vault's assess_fees function for a specified gain amount
    fun assess_fees<StrategyType: drop, BaseCoin>(gain: u64, vault_cap: &VaultCapability, witness: StrategyType) {
        vault::assess_fees<StrategyType, BaseCoin>(gain, 0, vault_cap, witness);
    }

    fun open_vault<StrategyType: drop>(
        manager_addr: address,
        vault_id: u64,
        witness: StrategyType
    ) : (VaultCapability, VaultCapLock) {
        satay::lock_vault<StrategyType>(manager_addr, vault_id, witness)
    }

    fun close_vault<StrategyType: drop>(
        manager_addr: address,
        vault_cap: VaultCapability,
        stop_handle: VaultCapLock
    ) {
        satay::unlock_vault<StrategyType>(manager_addr, vault_cap, stop_handle);
    }

    // #[test_only]
    // public fun test_prepare_return<CoinType, BaseCoin>(manager_addr: address, vault_id: u64): (u64, u64, u64) acquires StrategyCapability {
    //     let _witness = BaseStrategy {};
    //     let (vault_cap, stop_handle) = satay::lock_vault<BaseStrategy>(manager_addr, vault_id, _witness);
    //
    //     let coins = staking_pool::claimRewards<CoinType>(@staking_pool_manager);
    //     let want_coins = swap_to_want_token<CoinType, BaseCoin>(coins);
    //     apply_position<BaseCoin>(manager_addr, want_coins);
    //
    //     let (profit, loss, debt_payment) = prepare_return<BaseCoin>(&vault_cap, manager_addr);
    //
    //     satay::unlock_vault<BaseStrategy>(manager_addr, vault_cap, stop_handle);
    //
    //     (profit, loss, debt_payment)
    // }
    //
    // #[test_only]
    // public entry fun test_harvest<CoinType, BaseCoin>(manager_addr: address, vault_id: u64): (u64, u64) acquires StrategyCapability {
    //     let _witness = BaseStrategy {};
    //     let (vault_cap, stop_handle) = satay::lock_vault<BaseStrategy>(manager_addr, vault_id, _witness);
    //
    //     let coins = staking_pool::claimRewards<CoinType>(@staking_pool_manager);
    //     let want_coins = swap_to_want_token<CoinType, BaseCoin>(coins);
    //     apply_position<BaseCoin>(manager_addr, want_coins);
    //
    //     let (profit, loss, debt_payment) = prepare_return<BaseCoin>(&vault_cap, manager_addr);
    //
    //     // profit to report
    //     if (profit > 0) {
    //         vault::report_gain<BaseStrategy>(&mut vault_cap, profit);
    //     };
    //
    //     // loss to report, do it before the rest of the calculation
    //     if (loss > 0) {
    //         let total_debt = vault::total_debt<BaseStrategy>(&vault_cap);
    //         assert!(total_debt >= loss, ERR_LOSS);
    //         vault::report_loss<BaseStrategy>(&mut vault_cap, loss);
    //     };
    //
    //     let credit = vault::credit_available<BaseStrategy, BaseCoin>(&vault_cap);
    //     let debt = vault::debt_out_standing<BaseStrategy, BaseCoin>(&vault_cap);
    //     if (debt_payment > debt) {
    //         debt_payment = debt;
    //     };
    //
    //     if (credit > 0 || debt_payment > 0) {
    //         vault::update_total_debt<BaseStrategy>(&mut vault_cap, credit, debt_payment);
    //         // debt = debt - debt_payment;
    //     };
    //
    //     let total_available = profit + debt_payment;
    //
    //     if (total_available < credit) { // credit surplus, give to Strategy
    //         let coins =  vault::withdraw<BaseCoin>(&vault_cap, credit - total_available);
    //         apply_position<BaseCoin>(manager_addr, coins);
    //     } else { // credit deficit, take from Strategy
    //         let coins = liquidate_position<BaseCoin>(manager_addr, total_available - credit);
    //         vault::deposit<BaseCoin>(&vault_cap, coins);
    //     };
    //
    //     satay::unlock_vault<BaseStrategy>(manager_addr, vault_cap, stop_handle);
    //
    //     (total_available, credit)
    // }
}
