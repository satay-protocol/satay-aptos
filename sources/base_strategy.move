/// facilitates interaction between vaults and structured products
module satay::base_strategy {

    use aptos_framework::coin::{Coin};

    use satay_coins::vault_coin::VaultCoin;
    use satay_coins::strategy_coin::StrategyCoin;

    use satay::vault::{Self, UserCapability, KeeperCapability, UserLiquidationLock, HarvestInfo};
    use satay::satay;

    // operation locks

    /// created and destroyed during user withdraw
    /// @field vault_cap_lock - holds the vault_id, must be destroyed through satay::unlock_vault
    /// @field amount_needed - the amount of BaseCoin needed for liquidation
    /// @field vault_coins - ValutCoin<BaseCoin> to liqduiate
    /// @field witness - instance of StrategyType for validating function calls
    struct UserWithdrawLock<phantom BaseCoin, StrategyType: drop> {
        user_liq_lock: UserLiquidationLock<BaseCoin>,
        user_cap: UserCapability<BaseCoin>,
        witness: StrategyType
    }

    /// created and destroyed during harvest
    /// @field vault_cap_lock - holds the vault_id, must be destroyed through satay::unlock_vault
    /// @field profit - the amount of BaseCoin profit since last harvest
    /// @field debt_payment - the amount of BaseCoin to return to cover outstanding debt
    struct HarvestLock<phantom BaseCoin, StrategyType: drop> {
        harvest_info: HarvestInfo,
        keeper_cap: KeeperCapability<BaseCoin, StrategyType>
    }

    // vault manager functions

    /// calls approve_strategy for StrategyType on vault_id
    /// @param vault_manager - the transaction signer; must have vault_manager role on vault_config for vault_id
    /// @param debt_ratio - the percentage of vault funds to allocate to StrategyType in BPS
    /// @param witness - an instance of StrategyType to prove the source of the call
    public fun approve_strategy<BaseCoin, StrategyType: drop>(
        vault_manager: &signer,
        debt_ratio: u64,
        witness: StrategyType
    ) {
        satay::approve_strategy<BaseCoin, StrategyType>(vault_manager, debt_ratio, &witness);
    }

    /// updates the debt ratio for StrategyType
    /// @param vault_manager - the transaction signer; must have the vault manager role for vault_id
    /// @param debt_ratio - the new debt ratio for StrategyType
    /// @param witness - an instance of StrategyType to prove the source of the call
    public fun update_debt_ratio<BaseCoin, StrategyType: drop>(
        vault_manager: &signer,
        debt_ratio: u64,
        witness: StrategyType
    ) {
        satay::update_strategy_debt_ratio<BaseCoin, StrategyType>(vault_manager, debt_ratio, &witness);
    }

    /// sets the debt ratio for StrategyType to 0
    /// @param vault_manager - the transaction signer; must have the vault manager role for vault_id
    /// @param witness - an instance of StrategyType to prove the source of the call
    public fun revoke_strategy<BaseCoin, StrategyType: drop>(vault_manager: &signer, witness: StrategyType) {
        update_debt_ratio<BaseCoin, StrategyType>(vault_manager, 0, witness);
    }

    // deposit and withdraw

    /// withdraws StrategyCoin from a vault for harvest, called by keeper
    /// @param keeper_cap - holds the VaultCapability and witness for vault operations
    /// @param amount - the amount of StrategyCoin to withdraw from the vault
    public fun withdraw_strategy_coin<BaseCoin, StrategyType: drop>(
        harvest_lock: &HarvestLock<BaseCoin, StrategyType>,
        amount: u64,
    ): Coin<StrategyCoin<BaseCoin, StrategyType>> {
        vault::withdraw_strategy_coin<BaseCoin, StrategyType>(&harvest_lock.keeper_cap, amount)
    }

    /// withdraws StrategyCoin from a vault for liquidation, called by user
    /// @param user_cap - holds the VaultCapability and user address
    /// @param amount - the amount of StrategyCoin to withdraw from the vault
    /// @param user_withdraw_lock - holds the vault_id, amount_needed, vault_coins, and witness
    public fun withdraw_strategy_coin_for_liquidation<BaseCoin, StrategyType: drop>(
        user_withdraw_lock: &UserWithdrawLock<BaseCoin, StrategyType>,
        amount: u64,
    ): Coin<StrategyCoin<BaseCoin, StrategyType>> {
        vault::withdraw_strategy_coin_for_liquidation<BaseCoin, StrategyType>(
            &user_withdraw_lock.user_cap,
            amount,
            &user_withdraw_lock.witness,
        )
    }

    // for harvest

    /// opens a vault for harvest, called by keeper
    /// @param keeper - the transaction signer; must have keeper role on strategy_config for StrategyType on vault_id
    /// @param witness - an instance of StrategyType to prove the source of the call
    public fun open_vault_for_harvest<BaseCoin, StrategyType: drop>(
        keeper: &signer,
        strategy_balance: u64,
        witness: StrategyType,
    ) : (Coin<BaseCoin>, HarvestLock<BaseCoin, StrategyType>) {
        let keeper_cap = satay::keeper_lock_vault<BaseCoin, StrategyType>(
            keeper,
            witness
        );
        let (to_apply, harvest_info) = vault::process_harvest<BaseCoin, StrategyType>(
            &keeper_cap,
            strategy_balance
        );
        (to_apply, HarvestLock {
            harvest_info,
            keeper_cap
        })
    }

    /// closes a vault for harvest, called by keeper
    /// @param harvest_lock - holds the vault_id, profit, and debt_payment amounts
    /// @param debt_payment - the Coin<BaseCoin> to pay back to the vault
    /// @param profit - the Coin<BaseCoin> to deposit as profit into the vault
    /// @param strategy_coins - the Coin<StrategyCoin> resulting from BaseCoin deployment
    public fun close_vault_for_harvest<BaseCoin, StrategyType: drop>(
        harvest_lock: HarvestLock<BaseCoin, StrategyType>,
        debt_payment: Coin<BaseCoin>,
        profit: Coin<BaseCoin>,
        strategy_coins: Coin<StrategyCoin<BaseCoin, StrategyType>>
    ) {
        let HarvestLock<BaseCoin, StrategyType> {
            harvest_info,
            keeper_cap
        } = harvest_lock;
        vault::deposit_strategy_coin<BaseCoin, StrategyType>(&keeper_cap, strategy_coins);
        vault::destroy_harvest_info<BaseCoin, StrategyType>(&keeper_cap, harvest_info, debt_payment, profit);
        satay::keeper_unlock_vault<BaseCoin, StrategyType>(keeper_cap);
    }

    // for user withdraw

    /// called when vault does not have sufficient liquidity to fulfill user withdraw of vault_coins
    /// @param user - the transaction signer
    /// @param vault_coins - the amount of VaultCoin to liquidate
    /// @param witness - an instance of StrategyType to prove the source of the call
    public fun open_vault_for_user_withdraw<BaseCoin, StrategyType: drop>(
        user: &signer,
        vault_coins: Coin<VaultCoin<BaseCoin>>,
        witness: StrategyType
    ): UserWithdrawLock<BaseCoin, StrategyType> {
        let user_cap = satay::user_lock_vault<BaseCoin>(user);
        let user_liq_lock = vault::get_liquidation_lock<BaseCoin, StrategyType>(
            &user_cap,
            vault_coins
        );
        UserWithdrawLock<BaseCoin, StrategyType> {
            user_liq_lock,
            witness,
            user_cap
        }
    }

    /// closes a vault for user withdraw
    /// @param user_cap - holds the VaultCapability and user_address
    /// @param user_withdraw_lock - holds the vault_cap_lock, amount_needed, vault_coins, and witness
    /// @param base_coins - the Coin<BaseCoin> to return to the vault
    public fun close_vault_for_user_withdraw<BaseCoin, StrategyType: drop>(
        user_withdraw_lock: UserWithdrawLock<BaseCoin, StrategyType>,
        base_coins: Coin<BaseCoin>,
    ) {
        let UserWithdrawLock<BaseCoin, StrategyType> {
            user_liq_lock,
            witness,
            user_cap
        } = user_withdraw_lock;
        vault::user_liquidation(&user_cap, base_coins, user_liq_lock, &witness);
        satay::user_unlock_vault<BaseCoin>(user_cap);
    }

    // getters

    /// returns the amount of profit to return to the vault during harvest
    /// @param harvest_lock - the HarvestLock for StrategyType
    public fun get_harvest_profit<BaseCoin, StrategyType: drop>(
        harvest_lock: &HarvestLock<BaseCoin, StrategyType>
    ): u64 {
        vault::get_harvest_profit(&harvest_lock.harvest_info)
    }

    /// returns the amount of debt to pay back to the vault during harvest
    /// @param harvest_lock - the HarvestLock for StrategyType
    public fun get_harvest_debt_payment<BaseCoin, StrategyType: drop>(
        harvest_lock: &HarvestLock<BaseCoin, StrategyType>
    ): u64 {
        vault::get_harvest_debt_payment(&harvest_lock.harvest_info)
    }

    /// returns the amount of debt to pay back to the vault during user withdraw
    /// @param user_withdraw_lock - the UserWithdrawLock for StrategyType
    public fun get_user_withdraw_amount_needed<BaseCoin, StrategyType: drop>(
        user_withdraw_lock: &UserWithdrawLock<BaseCoin, StrategyType>
    ): u64 {
        vault::get_liquidation_amount_needed(&user_withdraw_lock.user_liq_lock)
    }

    #[test_only]
    public fun deposit_strategy_coin<BaseCoin, StrategyType: drop>(
        keeper_cap: &KeeperCapability<BaseCoin, StrategyType>,
        strategy_coins: Coin<StrategyCoin<BaseCoin, StrategyType>>,
    ) {
        vault::deposit_strategy_coin<BaseCoin, StrategyType>(keeper_cap, strategy_coins);
    }

    #[test_only]
    public fun test_withdraw_base_coin<BaseCoin, StrategyType: drop>(
        harvest_lock: &HarvestLock<BaseCoin, StrategyType>,
        amount: u64,
    ): Coin<BaseCoin> {
        vault::test_keeper_withdraw_base_coin<BaseCoin, StrategyType>(&harvest_lock.keeper_cap, amount)
    }
}