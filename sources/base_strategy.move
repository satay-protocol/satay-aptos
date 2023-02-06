/// facilitates interaction between vaults and structured products
module satay::base_strategy {

    use aptos_framework::coin::{Coin};

    use satay_vault_coin::vault_coin::VaultCoin;

    use satay::vault::{Self, VaultCapability, UserCapability, KeeperCapability, UserLiquidationLock, HarvestInfo};
    use satay::satay::{Self, VaultCapLock};

    // error codes

    /// when a keeper calls tend but the strategy has debt outstanding
    const ERR_DEBT_OUT_STANDING: u64 = 304;

    // operation locks

    /// created and destroyed during user withdraw
    /// @field vault_cap_lock - holds the vault_id, must be destroyed through satay::unlock_vault
    /// @field amount_needed - the amount of BaseCoin needed for liquidation
    /// @field vault_coins - ValutCoin<BaseCoin> to liqduiate
    /// @field witness - instance of StrategyType for validating function calls
    struct UserWithdrawLock<StrategyType: drop, phantom BaseCoin> {
        vault_cap_lock: VaultCapLock<StrategyType>,
        user_liq_lock: UserLiquidationLock<BaseCoin>,
        user_cap: UserCapability,
        witness: StrategyType
    }

    /// created and destroyed during harvest
    /// @field vault_cap_lock - holds the vault_id, must be destroyed through satay::unlock_vault
    /// @field profit - the amount of BaseCoin profit since last harvest
    /// @field debt_payment - the amount of BaseCoin to return to cover outstanding debt
    struct HarvestLock<StrategyType: drop> {
        vault_cap_lock: VaultCapLock<StrategyType>,
        harvest_info: HarvestInfo,
        keeper_cap: KeeperCapability<StrategyType>
    }

    /// created and destroyed during tend
    /// @field vault_cap_lock - holds the vault_id, must be destroyed through satay::unlock_vault
    struct TendLock<phantom StrategyType: drop> {
        vault_cap_lock: VaultCapLock<StrategyType>,
    }

    // vault manager functions

    /// calls approve_strategy for StrategyType on vault_id
    /// @param vault_manager - the transaction signer; must have vault_manager role on vault_config for vault_id
    /// @param vault_id - the id for the vault
    /// @param debt_ratio - the percentage of vault funds to allocate to StrategyType in BPS
    /// @param witness - an instance of StrategyType to prove the source of the call
    public fun initialize<StrategyType: drop, StrategyCoin>(
        vault_manager: &signer,
        vault_id: u64,
        debt_ratio: u64,
        witness: StrategyType
    ) {
        satay::approve_strategy<StrategyType, StrategyCoin>(
            vault_manager,
            vault_id,
            debt_ratio,
            &witness
        );
    }

    /// updates the debt ratio for StrategyType
    /// @param vault_manager - the transaction signer; must have the vault manager role for vault_id
    /// @param vault_id - the id for the vault
    /// @param debt_ratio - the new debt ratio for StrategyType
    /// @param witness - an instance of StrategyType to prove the source of the call
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

    /// sets the debt ratio for StrategyType to 0
    /// @param vault_manager - the transaction signer; must have the vault manager role for vault_id
    /// @param vault_id - the id for the vault
    /// @param witness - an instance of StrategyType to prove the source of the call
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

    // deposit and withdraw

    /// withdraws StrategyCoin from a vault for harvest, called by keeper
    /// @param keeper_cap - holds the VaultCapability and witness for vault operations
    /// @param amount - the amount of StrategyCoin to withdraw from the vault
    public fun withdraw_strategy_coin<StrategyType: drop, StrategyCoin>(
        harvest_lock: &HarvestLock<StrategyType>,
        amount: u64,
    ): Coin<StrategyCoin> {
        vault::withdraw_strategy_coin<StrategyType, StrategyCoin>(
            &harvest_lock.keeper_cap,
            amount,
        )
    }

    /// withdraws StrategyCoin from a vault for liquidation, called by user
    /// @param user_cap - holds the VaultCapability and user address
    /// @param amount - the amount of StrategyCoin to withdraw from the vault
    /// @param user_withdraw_lock - holds the vault_id, amount_needed, vault_coins, and witness
    public fun withdraw_strategy_coin_for_liquidation<StrategyType: drop, StrategyCoin, BaseCoin>(
        user_withdraw_lock: &UserWithdrawLock<StrategyType, BaseCoin>,
        amount: u64,
    ): Coin<StrategyCoin> {
        vault::withdraw_strategy_coin_for_liquidation<StrategyType, StrategyCoin, BaseCoin>(
            &user_withdraw_lock.user_cap,
            amount,
            &user_withdraw_lock.witness,
        )
    }

    // for harvest

    /// opens a vault for harvest, called by keeper
    /// @param keeper - the transaction signer; must have keeper role on strategy_config for StrategyType on vault_id
    /// @param vault_id - the id for the vault
    /// @param witness - an instance of StrategyType to prove the source of the call
    public fun open_vault_for_harvest<StrategyType: drop, BaseCoin, StrategyCoin>(
        keeper: &signer,
        vault_id: u64,
        strategy_balance: u64,
        witness: StrategyType,
    ) : (Coin<BaseCoin>, HarvestLock<StrategyType>) {
        let (vault_cap, vault_cap_lock) = open_vault<StrategyType>(
            vault_id,
            &witness
        );
        let keeper_cap = vault::get_keeper_capability<StrategyType>(
            keeper,
            vault_cap,
            witness
        );
        let (to_apply, harvest_info) = vault::process_harvest<StrategyType, BaseCoin, StrategyCoin>(
            &keeper_cap,
            strategy_balance
        );

        (to_apply, HarvestLock {
            vault_cap_lock,
            harvest_info,
            keeper_cap
        })
    }

    // /// calculates new debt position for StrategyType and returns Coin<BaseCoin> to deploy to strategy
    // /// @param keeper_cap - holds the VaultCapability and witness for vault operations
    // /// @param strategy_balance - the amount of BaseCoin in the strategy
    // /// @param vault_cap_lock - holds the vault_id, stored in HarvestLock
    // public fun process_harvest<StrategyType: drop, BaseCoin, StrategyCoin>(
    //     keeper_cap: &KeeperCapability<StrategyType>,
    //     strategy_balance: u64,
    //     vault_cap_lock: VaultCapLock<StrategyType>,
    // ) : (Coin<BaseCoin>, HarvestLock<StrategyType>) {
    //
    // }

    /// closes a vault for harvest, called by keeper
    /// @param keeper_cap - holds the VaultCapability and witness for vault operations
    /// @param harvest_lock - holds the vault_id, profit, and debt_payment amounts
    /// @param debt_payment - the Coin<BaseCoin> to pay back to the vault
    /// @param profit - the Coin<BaseCoin> to deposit as profit into the vault
    /// @param strategy_coins - the Coin<StrategyCoin> resulting from BaseCoin deployment
    public fun close_vault_for_harvest<StrategyType: drop, BaseCoin, StrategyCoin>(
        harvest_lock: HarvestLock<StrategyType>,
        debt_payment: Coin<BaseCoin>,
        profit: Coin<BaseCoin>,
        strategy_coins: Coin<StrategyCoin>
    ) {
        let HarvestLock<StrategyType> {
            vault_cap_lock,
            harvest_info,
            keeper_cap
        } = harvest_lock;

        vault::deposit_strategy_coin<StrategyType, StrategyCoin>(
            &keeper_cap,
            strategy_coins,
        );

        vault::destroy_harvest_info<StrategyType, BaseCoin>(
            &keeper_cap,
            harvest_info,
            debt_payment,
            profit
        );

        let vault_cap = vault::destroy_keeper_capability(keeper_cap);
        close_vault<StrategyType>(
            vault_cap,
            vault_cap_lock
        );
    }

    // for tend

    /// opens a vault for tend, called by keeper
    /// @param keeper - the transaction signer; must have keeper role on strategy_config for StrategyType on vault_id
    /// @param vault_id - the id for the vault
    /// @param witness - an instance of StrategyType to prove the source of the call
    public fun open_vault_for_tend<StrategyType: drop, BaseCoin>(
        keeper: &signer,
        vault_id: u64,
        witness: StrategyType,
    ): (KeeperCapability<StrategyType>, TendLock<StrategyType>) {
        let (vault_cap, vault_cap_lock) = open_vault<StrategyType>(
            vault_id,
            &witness
        );
        let debt_out_standing = vault::debt_out_standing<StrategyType, BaseCoin>(&vault_cap);
        assert!(debt_out_standing == 0, ERR_DEBT_OUT_STANDING);

        let keeper_cap = vault::get_keeper_capability<StrategyType>(
            keeper,
            vault_cap,
            witness
        );
        let tend_lock = TendLock {
            vault_cap_lock,
        };

        (keeper_cap, tend_lock)
    }

    /// closes a vault for tend, called by keeper
    /// @param keeper_cap - holds the VaultCapability and witness for vault operations
    /// @param tend_lock - holds the vault_cap_lock
    /// @param strategy_coins - the Coin<StrategyCoin> resulting reinvestment of rewards
    public fun close_vault_for_tend<StrategyType: drop, StrategyCoin>(
        keeper_cap: KeeperCapability<StrategyType>,
        tend_lock: TendLock<StrategyType>,
        strategy_coins: Coin<StrategyCoin>
    ) {
        let TendLock<StrategyType> {
            vault_cap_lock
        } = tend_lock;
        vault::deposit_strategy_coin<StrategyType, StrategyCoin>(
            &keeper_cap,
            strategy_coins,
        );
        let vault_cap = vault::destroy_keeper_capability(keeper_cap);
        close_vault<StrategyType>(
            vault_cap,
            vault_cap_lock
        );
    }

    // for user withdraw

    /// called when vault does not have sufficient liquidity to fulfill user withdraw of vault_coins
    /// @param user - the transaction signer
    /// @param vault_id - the id for the vault
    /// @param vault_coins - the amount of VaultCoin to liquidate
    /// @param witness - an instance of StrategyType to prove the source of the call
    public fun open_vault_for_user_withdraw<StrategyType: drop, BaseCoin, StrategyCoin>(
        user: &signer,
        vault_id: u64,
        vault_coins: Coin<VaultCoin<BaseCoin>>,
        witness: StrategyType
    ): UserWithdrawLock<StrategyType, BaseCoin> {
        let (vault_cap, vault_cap_lock) = open_vault<StrategyType>(
            vault_id,
            &witness
        );

        let user_liq_lock = vault::get_liquidation_lock<StrategyType, BaseCoin>(
            &vault_cap,
            vault_coins
        );

        let user_cap = vault::get_user_capability(
            user,
            vault_cap,
        );

        UserWithdrawLock<StrategyType, BaseCoin> {
            vault_cap_lock,
            user_liq_lock,
            witness,
            user_cap
        }
    }

    /// closes a vault for user withdraw
    /// @param user_cap - holds the VaultCapability and user_address
    /// @param user_withdraw_lock - holds the vault_cap_lock, amount_needed, vault_coins, and witness
    /// @param base_coins - the Coin<BaseCoin> to return to the vault
    public fun close_vault_for_user_withdraw<StrategyType: drop, BaseCoin>(
        user_withdraw_lock: UserWithdrawLock<StrategyType, BaseCoin>,
        base_coins: Coin<BaseCoin>,
    ) {
        let UserWithdrawLock<StrategyType, BaseCoin> {
            vault_cap_lock,
            user_liq_lock,
            witness,
            user_cap
        } = user_withdraw_lock;

        vault::user_liquidation(
            &user_cap,
            base_coins,
            user_liq_lock,
            &witness
        );

        let (vault_cap, _) = vault::destroy_user_capability(user_cap);

        close_vault<StrategyType>(vault_cap, vault_cap_lock);
    }

    // getters

    /// returns the balance of StrategyCoin in the vault during harvest
    /// @param keeper_cap - the KeeperCapability for the vault
    public fun harvest_balance<StrategyType: drop, StrategyCoin>(keeper_cap: &KeeperCapability<StrategyType>): u64 {
        vault::harvest_balance<StrategyType, StrategyCoin>(keeper_cap)
    }

    /// returns the amount of profit to return to the vault during harvest
    /// @param harvest_lock - the HarvestLock for StrategyType
    public fun get_harvest_profit<StrategyType: drop>(harvest_lock: &HarvestLock<StrategyType>): u64 {
        vault::get_harvest_profit(&harvest_lock.harvest_info)
    }

    /// returns the amount of debt to pay back to the vault during harvest
    /// @param harvest_lock - the HarvestLock for StrategyType
    public fun get_harvest_debt_payment<StrategyType: drop>(harvest_lock: &HarvestLock<StrategyType>): u64 {
        vault::get_harvest_debt_payment(&harvest_lock.harvest_info)
    }

    /// returns the amount of debt to pay back to the vault during user withdraw
    /// @param user_withdraw_lock - the UserWithdrawLock for StrategyType
    public fun get_user_withdraw_amount_needed<StrategyType: drop, BaseCoin>(
        user_withdraw_lock: &UserWithdrawLock<StrategyType, BaseCoin>
    ): u64 {
        vault::get_liquidation_amount_needed(&user_withdraw_lock.user_liq_lock)
    }

    // helpers

    /// gets the VaultCapability and VaultCapLock<StrategyType> for vault_id
    /// @param vault_id - the id for the vault
    /// @param witness - a reference to an instance of StrategyType to prove the source of the call
    fun open_vault<StrategyType: drop>(
        vault_id: u64,
        witness: &StrategyType
    ): (VaultCapability, VaultCapLock<StrategyType>) {
        satay::lock_vault<StrategyType>(vault_id, witness)
    }

    /// returns the VaultCapability and destroys the VaultCapLock<StrategyType>
    /// @param vault_cap - the VaultCapability for the vault
    /// @param vault_cap_lock - the VaultCapLock<StrategyType> for the vault
    fun close_vault<StrategyType: drop>(
        vault_cap: VaultCapability,
        stop_handle: VaultCapLock<StrategyType>
    ) {
        satay::unlock_vault<StrategyType>(vault_cap, stop_handle);
    }

    #[test_only]
    public fun deposit_strategy_coin<StrategyType: drop, StrategyCoin>(
        keeper_cap: &KeeperCapability<StrategyType>,
        strategy_coins: Coin<StrategyCoin>,
    ) {
        vault::deposit_strategy_coin<StrategyType, StrategyCoin>(
            keeper_cap,
            strategy_coins,
        );
    }

    #[test_only]
    public fun test_withdraw_base_coin<StrategyType: drop, BaseCoin>(
        harvest_lock: &HarvestLock<StrategyType>,
        amount: u64,
    ): Coin<BaseCoin> {
        vault::test_keeper_withdraw_base_coin<StrategyType, BaseCoin>(
            &harvest_lock.keeper_cap,
            amount,
        )
    }
}