module satay::base_strategy {

    // use std::signer;

    use aptos_framework::coin::{Self, Coin};

    use satay::vault::{Self, VaultCapability, VaultCoin, UserCapability};
    use satay::satay::{Self, VaultCapLock};

    const ERR_NOT_ENOUGH_FUND: u64 = 301;
    const ERR_ENOUGH_BALANCE_ON_VAULT: u64 = 302;
    const ERR_LOSS: u64 = 303;
    const ERR_DEBT_OUT_STANDING: u64 = 304;
    const ERR_HARVEST: u64 = 305;
    const ERR_INSUFFICIENT_USER_RETURN: u64 = 306;

    struct UserWithdrawLock<StrategyType: drop, phantom BaseCoin> {
        vault_cap_lock: VaultCapLock<StrategyType>,
        amount_needed: u64,
        vault_coins: Coin<VaultCoin<BaseCoin>>
    }

    struct HarvestLock<StrategyType: drop> {
        vault_cap_lock: VaultCapLock<StrategyType>,
        profit: u64,
        debt_payment: u64,
    }

    struct TendLock<StrategyType: drop> {
        vault_cap_lock: VaultCapLock<StrategyType>,
    }

    // initialize vault_id to accept strategy
    public fun initialize<StrategyType: drop, StrategyCoin>(
        governance: &signer,
        vault_id: u64,
        debt_ratio: u64,
        witness: StrategyType
    ) {

        // approve strategy on vault
        satay::approve_strategy<StrategyType, StrategyCoin>(
            governance,
            vault_id,
            debt_ratio,
            &witness
        );
    }

    // strategy coin deposit and withdraw
    public fun deposit_strategy_coin<StrategyType: drop, StrategyCoin>(
        vault_cap: &VaultCapability,
        strategy_coins: Coin<StrategyCoin>,
        stop_handle: &VaultCapLock<StrategyType>
    ) {
        vault::deposit_strategy_coin<StrategyType, StrategyCoin>(
            vault_cap,
            strategy_coins,
            satay::get_strategy_witness(stop_handle)
        );
    }

    public fun withdraw_strategy_coin<StrategyType: drop, StrategyCoin>(
        vault_cap: &VaultCapability,
        amount: u64,
        stop_handle: &VaultCapLock<StrategyType>
    ): Coin<StrategyCoin> {
        vault::withdraw_strategy_coin<StrategyType, StrategyCoin>(
            vault_cap,
            amount,
            satay::get_strategy_witness(stop_handle),
        )
    }

    public fun withdraw_strategy_coin_for_liquidation<StrategyType: drop, StrategyCoin, BaseCoin>(
        user_cap: &UserCapability,
        amount: u64,
        stop_handle: &VaultCapLock<StrategyType>
    ): Coin<StrategyCoin> {
        vault::withdraw_strategy_coin_for_liquidation<StrategyType, StrategyCoin, BaseCoin>(
            user_cap,
            amount,
            satay::get_strategy_witness(stop_handle),
        )
    }

    // for harvest

    public fun open_vault_for_harvest<StrategyType: drop, BaseCoin>(
        _keeper: &signer,
        vault_id: u64,
        witness: StrategyType,
    ) : (VaultCapability, VaultCapLock<StrategyType>) {
        open_vault<StrategyType>(
            vault_id,
            witness
        )
    }

    public fun process_harvest<StrategyType: drop, BaseCoin, StrategyCoin>(
        vault_cap: &VaultCapability,
        strategy_balance: u64,
        vault_cap_lock: VaultCapLock<StrategyType>,
    ) : (Coin<BaseCoin>, HarvestLock<StrategyType>) {

        let witness = satay::get_strategy_witness(&vault_cap_lock);

        let (profit, loss, debt_payment) = prepare_return<StrategyType, BaseCoin>(
            vault_cap,
            strategy_balance
        );

        // loss to report, do it before the rest of the calculation
        if (loss > 0) {
            let total_debt = vault::total_debt<StrategyType>(vault_cap);
            assert!(total_debt >= loss, ERR_LOSS);
            vault::report_loss<StrategyType>(vault_cap, loss, witness);
        };

        let debt = vault::debt_out_standing<StrategyType, BaseCoin>(vault_cap);
        if (debt_payment > debt) {
            debt_payment = debt;
        };

        let credit = vault::credit_available<StrategyType, BaseCoin>(vault_cap);
        let to_apply= coin::zero<BaseCoin>();
        if(credit > 0){
            coin::merge(
                &mut to_apply,
                vault::withdraw_base_coin<StrategyType, BaseCoin>(
                    vault_cap,
                    credit,
                    witness
                )
            );
        };


        (to_apply, HarvestLock {
            vault_cap_lock,
            profit,
            debt_payment,
        })
    }

    public fun close_vault_for_harvest<StrategyType: drop, BaseCoin, StrategyCoin>(
        vault_cap: VaultCapability,
        harvest_lock: HarvestLock<StrategyType>,
        debt_payment: Coin<BaseCoin>,
        profit: Coin<BaseCoin>,
        strategy_coins: Coin<StrategyCoin>
    ) {
        let HarvestLock<StrategyType> {
            vault_cap_lock,
            profit: profit_expected,
            debt_payment: debt_payment_expected,
        } = harvest_lock;

        assert!(coin::value(&profit) == profit_expected, ERR_HARVEST);
        assert!(coin::value(&debt_payment) == debt_payment_expected, ERR_HARVEST);

        let witness = satay::get_strategy_witness(&vault_cap_lock);

        vault::deposit_profit<StrategyType, BaseCoin>(
            &vault_cap,
            profit,
            witness
        );
        vault::debt_payment<StrategyType, BaseCoin>(
            &vault_cap,
            debt_payment,
            witness
        );
        vault::deposit_strategy_coin<StrategyType, StrategyCoin>(
            &vault_cap,
            strategy_coins,
            witness
        );
        vault::report_timestamp<StrategyType>(&vault_cap, witness);
        close_vault<StrategyType>(
            vault_cap,
            vault_cap_lock
        );
    }

    // for tend

    public fun open_vault_for_tend<StrategyType: drop, BaseCoin>(
        _keeper: &signer,
        vault_id: u64,
        witness: StrategyType,
    ): (VaultCapability, TendLock<StrategyType>) {
        let (vault_cap, vault_cap_lock) = open_vault<StrategyType>(
            vault_id,
            witness
        );
        let debt_out_standing = vault::debt_out_standing<StrategyType, BaseCoin>(&vault_cap);
        assert!(debt_out_standing == 0, ERR_DEBT_OUT_STANDING);

        (vault_cap, TendLock<StrategyType> {
            vault_cap_lock
        })
    }

    public fun close_vault_for_tend<StrategyType: drop, StrategyCoin>(
        vault_cap: VaultCapability,
        tend_lock: TendLock<StrategyType>,
        strategy_coins: Coin<StrategyCoin>
    ) {
        let TendLock<StrategyType> {
            vault_cap_lock
        } = tend_lock;
        deposit_strategy_coin<StrategyType, StrategyCoin>(
            &vault_cap,
            strategy_coins,
            &vault_cap_lock
        );
        close_vault<StrategyType>(
            vault_cap,
            vault_cap_lock
        );
    }

    // for user withdraw

    // called when vault does not have enough BaseCoin in reserves to support share_amount withdraw
    // vault must withdraw from strategy
    public fun open_vault_for_user_withdraw<StrategyType: drop, BaseCoin, StrategyCoin>(
        user: &signer,
        vault_id: u64,
        vault_coins: Coin<VaultCoin<BaseCoin>>,
        witness: StrategyType
    ): (UserCapability, UserWithdrawLock<StrategyType, BaseCoin>) {
        let (vault_cap, vault_cap_lock) = open_vault<StrategyType>(
            vault_id,
            witness
        );

        // check if vault has enough balance
        let vault_coin_amount = coin::value(&vault_coins);
        let vault_balance = vault::balance<BaseCoin>(&vault_cap);
        let value = vault::calculate_base_coin_amount_from_vault_coin_amount<BaseCoin>(
            &vault_cap,
            vault_coin_amount
        );
        assert!(vault_balance < value, ERR_ENOUGH_BALANCE_ON_VAULT);

        let amount_needed = value - vault_balance;
        let total_debt = vault::total_debt<StrategyType>(&vault_cap);
        assert!(total_debt >= amount_needed, ERR_INSUFFICIENT_USER_RETURN);

        let user_cap = vault::get_user_capability(
            user,
            vault_cap,
        );

        (user_cap, UserWithdrawLock<StrategyType, BaseCoin> {
            vault_cap_lock,
            amount_needed,
            vault_coins
        })
    }

    public fun close_vault_for_user_withdraw<StrategyType: drop, BaseCoin>(
        user_cap: UserCapability,
        user_withdraw_lock: UserWithdrawLock<StrategyType, BaseCoin>,
        coins: Coin<BaseCoin>,
    ) {
        let UserWithdrawLock<StrategyType, BaseCoin> {
            vault_cap_lock,
            amount_needed,
            vault_coins
        } = user_withdraw_lock;


        assert!(coin::value(&coins) >= amount_needed, ERR_INSUFFICIENT_USER_RETURN);

        let witness = satay::get_strategy_witness(&vault_cap_lock);
        let vault_cap = vault::user_liquidation(
            user_cap,
            coins,
            vault_coins,
            witness
        );

        close_vault<StrategyType>(vault_cap, vault_cap_lock);
    }

    // admin functions

    // update the strategy debt ratio
    public fun update_debt_ratio<StrategyType: drop>(
        vault_manager: &signer,
        vault_id: u64,
        debt_ratio: u64,
        witness: StrategyType
    ) {
        satay::update_strategy_debt_ratio<StrategyType>(
            vault_manager,
            vault_id,
            debt_ratio,
            &witness
        );
    }

    // revoke the strategy
    public fun revoke_strategy<StrategyType: drop>(
        vault_manager: &signer,
        vault_id: u64,
        witness: StrategyType
    ) {
        update_debt_ratio<StrategyType>(
            vault_manager,
            vault_id,
            0,
            witness
        );
    }

    public fun balance<CoinType>(vault_cap: &VaultCapability) : u64 {
        vault::balance<CoinType>(vault_cap)
    }

    public fun get_harvest_vault_cap_lock<StrategyType: drop>(harvest_lock: &HarvestLock<StrategyType>): &VaultCapLock<StrategyType> {
        &harvest_lock.vault_cap_lock
    }

    public fun get_harvest_profit<StrategyType: drop>(harvest_lock: &HarvestLock<StrategyType>): u64 {
        harvest_lock.profit
    }

    public fun get_harvest_debt_payment<StrategyType: drop>(harvest_lock: &HarvestLock<StrategyType>): u64 {
        harvest_lock.debt_payment
    }

    public fun get_user_withdraw_vault_cap_lock<StrategyType: drop, BaseCoin>(
        user_withdraw_lock: &UserWithdrawLock<StrategyType, BaseCoin>
    ): &VaultCapLock<StrategyType> {
        &user_withdraw_lock.vault_cap_lock
    }

    public fun get_user_withdraw_amount_needed<StrategyType: drop, BaseCoin>(
        user_withdraw_lock: &UserWithdrawLock<StrategyType, BaseCoin>
    ): u64 {
        user_withdraw_lock.amount_needed
    }

    fun open_vault<StrategyType: drop>(
        vault_id: u64,
        witness: StrategyType
    ): (VaultCapability, VaultCapLock<StrategyType>) {
        satay::lock_vault<StrategyType>(vault_id, witness)
    }

    fun close_vault<StrategyType: drop>(
        vault_cap: VaultCapability,
        stop_handle: VaultCapLock<StrategyType>
    ) {
        satay::unlock_vault<StrategyType>(vault_cap, stop_handle);
    }

    // returns any realized profits, realized losses incurred, and debt payments to be made
    // called by harvest
    fun prepare_return<StrategyType: drop, BaseCoin>(
        vault_cap: &VaultCapability,
        strategy_balance: u64
    ): (u64, u64, u64) {

        // get amount of strategy debt over limit
        let debt_out_standing = vault::debt_out_standing<StrategyType, BaseCoin>(vault_cap);
        let debt_payment: u64;
        if (strategy_balance > debt_out_standing) {
            debt_payment = debt_out_standing;
            strategy_balance = strategy_balance - debt_payment;
        } else {
            debt_payment = strategy_balance;
            strategy_balance = 0;
        };

        // calculate profit and loss
        let profit = 0;
        let loss = 0;

        // strategy's total debt
        let total_debt = vault::total_debt<StrategyType>(vault_cap);

        total_debt = total_debt - debt_payment;

        if (strategy_balance > total_debt) {
            profit = strategy_balance - total_debt;
        } else {
            loss = total_debt - strategy_balance;
        };

        (profit, loss, debt_payment)
    }

    #[test_only]
    public fun test_prepare_return<StrategyType: drop, BaseCoin>(
        vault_cap: &VaultCapability,
        strategy_balance: u64
    ): (u64, u64, u64) {
        prepare_return<StrategyType, BaseCoin>(vault_cap, strategy_balance)
    }
}