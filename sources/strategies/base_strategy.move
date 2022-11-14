module satay::base_strategy {

    use aptos_framework::coin::{Coin};
    use std::signer;
    use satay::satay;
    use aptos_std::type_info;
    use satay::vault::{Self, VaultCapability};
    use aptos_framework::coin;
    use satay::satay::VaultCapLock;
    use aptos_std::type_info::type_of;

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

    // update the strategy debt ratio
    public entry fun update_debt_ratio<StrategyType: drop>(manager: &signer, vault_id: u64, debt_ratio: u64) {
        satay::update_strategy_debt_ratio<StrategyType>(manager, vault_id, debt_ratio);
    }

    // revoke the strategy
    public entry fun revoke<StrategyType: drop>(manager: &signer, vault_id: u64) {
        satay::update_strategy_debt_ratio<StrategyType>(manager, vault_id, 0);
    }

    // migrate to new strategy
    public entry fun migrate_from<OldStrategy: drop, NewStrategy: drop, NewStrategyCoin>(manager: &signer, vault_id: u64, witness: NewStrategy) {
        let debt_ratio = satay::update_strategy_debt_ratio<OldStrategy>(manager, vault_id, 0);
        initialize<NewStrategy, NewStrategyCoin>(manager, vault_id, debt_ratio, witness);
    }


    // called when vault does not have enough BaseCoin in reserves, and must reclaim funds from strategy
    // @dev: could be called when vault keeps StrategyCoin
    public fun open_vault_for_user_withdraw<StrategyType: drop, BaseCoin, StrategyCoin>(
        user: &signer,
        manager_addr: address,
        vault_id: u64,
        share_amount: u64,
        witness: StrategyType
    ) : (u64, VaultCapability, VaultCapLock) {
        let (vault_cap, stop_handle) = open_vault<StrategyType>(manager_addr, vault_id, witness);

        // check if user is eligible to withdraw
        let user_share_amount = coin::balance<vault::VaultCoin<BaseCoin>>(signer::address_of(user));
        assert!(user_share_amount >= share_amount, ERR_NOT_ENOUGH_FUND);

        // check if vault has enough balance
        let vault_balance = vault::balance<BaseCoin>(&vault_cap);
        let value = vault::calculate_base_coin_amount_from_share<BaseCoin>(&vault_cap, share_amount);
        assert!(vault_balance < value, ERR_ENOUGH_BALANCE_ON_VAULT);

        let amount_needed = value - vault_balance;
        let total_debt = vault::total_debt<StrategyType>(&vault_cap);
        if (amount_needed > total_debt) {
            amount_needed = total_debt;
        };

        (amount_needed, vault_cap, stop_handle)
    }

    public fun withdraw_strategy_coin<StrategyType: drop, StrategyCoin>(vault_cap: &VaultCapability, amount: u64) : Coin<StrategyCoin> {
        let strategy_coin_type = vault::get_strategy_coin_type<StrategyType>(vault_cap);
        assert!(type_of<StrategyCoin>() == strategy_coin_type, 0);

        let withdraw_amount = amount;
        let strategy_coin_balance = vault::balance<StrategyCoin>(vault_cap);
        if (amount > strategy_coin_balance) {
            withdraw_amount = strategy_coin_balance;
        };

        vault::withdraw<StrategyCoin>(
            vault_cap,
            withdraw_amount
        )
    }

    public fun close_vault_for_user_withdraw<StrategyType: drop, BaseCoin>(
        manager_addr: address,
        vault_cap: VaultCapability,
        stop_handle: VaultCapLock,
        coins: Coin<BaseCoin>,
        amount_needed: u64,
    ) {
        let value = coin::value(&coins);

        if (amount_needed > value) {
            vault::report_loss<StrategyType>(&mut vault_cap, amount_needed - value);
        };

        vault::update_total_debt<StrategyType>(&mut vault_cap, 0, value);
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
        strategy_balance: u64,
        witness: StrategyType
    ) : (Coin<BaseCoin>, u64) {

        let (profit, loss, debt_payment) = prepare_return<StrategyType, BaseCoin>(vault_cap, strategy_balance);

        // profit to report
        if (profit > 0) {
            vault::report_gain<StrategyType>(vault_cap, profit);
        };

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
        let amount_needed = 0;
        if (total_available < credit) { // credit surplus, give to Strategy
            coin::merge(
                &mut to_apply,
                vault::withdraw<BaseCoin>(vault_cap, credit - total_available)
            );
        } else { // credit deficit, take from Strategy
            amount_needed = total_available - credit;
        };

        vault::report<StrategyType>(vault_cap);

        (to_apply, amount_needed)
    }

    public fun close_vault_for_harvest<StrategyType: drop, BaseCoin, StrategyCoin>(
        manager_addr: address,
        vault_cap: VaultCapability,
        stop_handle: VaultCapLock,
        base_coins: Coin<BaseCoin>,
        strategy_coins: Coin<StrategyCoin>
    ) {
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

    // for tend

    public fun open_vault_for_tend<StrategyType: drop, BaseCoin>(
        manager: &signer,
        vault_id: u64,
        witness: StrategyType,
    ) :  (VaultCapability, VaultCapLock, u64) {
        let (vault_cap, stop_handle) = open_vault<StrategyType>(
            signer::address_of(manager),
            vault_id,
            witness
        );
        let debt_out_standing = vault::debt_out_standing<StrategyType, BaseCoin>(&vault_cap);

        (vault_cap, stop_handle, debt_out_standing)
    }

    public fun close_vault_for_tend<StrategyType: drop, StrategyCoin>(
        manager_addr: address,
        vault_cap: VaultCapability,
        stop_handle: VaultCapLock,
        strategy_coins: Coin<StrategyCoin>
    ) {
        vault::deposit(&vault_cap, strategy_coins);
        close_vault<StrategyType>(
            manager_addr,
            vault_cap,
            stop_handle
        );
    }

    public fun get_vault_address(vault_cap: &VaultCapability) : address {
        vault::get_vault_addr(vault_cap)
    }

    public fun balance<CoinType>(vault_cap: &VaultCapability) : u64 {
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
}
