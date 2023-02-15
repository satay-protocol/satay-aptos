/// user and strategy entry point to vault operations
/// holds all VaultCapability resources in a table
module satay::satay {

    use std::option::{Self, Option};
    use std::signer;

    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::account::{Self, SignerCapability};

    use satay_coins::vault_coin::{VaultCoin};
    use satay_coins::strategy_coin::{StrategyCoin};

    use satay::global_config;
    use satay::vault_config;
    use satay::strategy_config;
    use satay::keeper_config;

    use satay::vault::{Self, VaultCapability, KeeperCapability, UserCapability, VaultManagerCapability};
    use satay::satay_account;
    use satay::strategy_coin;
    use satay::strategy_coin::StrategyCapability;

    friend satay::base_strategy;

    // error codes


    /// when StrategyType is not approved for a vault
    const ERR_STRATEGY: u64 = 1;

    // structs

    struct SatayAccount has key {
        signer_cap: SignerCapability
    }

    /// holds a VaultCapability resource in an option
    /// @field vault_cap - Option holding VaultCapability; needed to allow lending to strategies
    struct VaultInfo<phantom BaseCoin> has key {
        vault_cap: Option<VaultCapability<BaseCoin>>,
    }

    struct StrategyInfo<phantom BaseCoin, phantom StrategyType: drop> has key {
        strategy_cap: Option<StrategyCapability<BaseCoin, StrategyType>>
    }

    // deployer functions

    /// create and store  in deployer account
    /// @param satay - the transaction signer; must be the deployer account
    public entry fun initialize(satay: &signer) {
        global_config::initialize(satay);
        let signer_cap = satay_account::retrieve_signer_cap(satay);
        move_to(satay, SatayAccount {
            signer_cap
        });
    }

    // governance functions

    /// create new vault for BaseCoin
    /// @param governance - the transaction signer; must hold governance role in global_config
    /// @param management_fee - the vault's management fee in BPS, charged annually
    /// @param performance_fee - the vault's performance fee in bips, charged on profits
    public entry fun new_vault<BaseCoin>(governance: &signer, management_fee: u64, performance_fee: u64)
    acquires SatayAccount {
        global_config::assert_governance(governance);

        let satay_account = borrow_global<SatayAccount>(@satay);
        let satay_account_signer = account::create_signer_with_capability(&satay_account.signer_cap);

        // create vault and add to manager vaults table
        let vault_cap = vault::new<BaseCoin>(
            &satay_account_signer,
            management_fee,
            performance_fee
        );

        move_to(&satay_account_signer, VaultInfo<BaseCoin> {
            vault_cap: option::some(vault_cap)
        });
    }

    ///
    public fun new_strategy<BaseCoin, StrategyType: drop>(governance: &signer, witness: StrategyType)
    acquires SatayAccount {
        global_config::assert_governance(governance);
        let satay_account = borrow_global<SatayAccount>(@satay);
        let satay_account_signer = account::create_signer_with_capability(&satay_account.signer_cap);
        let strategy_cap = strategy_coin::initialize<BaseCoin, StrategyType>(
            &satay_account_signer,
            signer::address_of(governance),
            witness
        );
        move_to(&satay_account_signer, StrategyInfo<BaseCoin, StrategyType> {
            strategy_cap: option::some(strategy_cap)
        });
    }

    // vault manager fucntions

    /// updates the management and performance fee for vault_id
    /// @param vault_manager - the transaction signer; must have vault_manager role on vault_config for vault_id
    /// @param management_fee - the vault's management fee in BPS, charged annually
    /// @param performance_fee - the vault's performance fee in bips, charged on profits
    public entry fun update_vault_fee<BaseCoin>(vault_manager: &signer, management_fee: u64, performance_fee: u64)
    acquires SatayAccount, VaultInfo {
        let vault_manager_cap = vault_manager_lock_vault<BaseCoin>(vault_manager);
        vault::update_fee(&vault_manager_cap, management_fee, performance_fee);
        vault_manager_unlock_vault<BaseCoin>(vault_manager_cap);
    }

    /// freezes user deposits to vault_id
    /// @param vault_manager - the transaction signer; must have vault_manager role on vault_config for vault_id
    public entry fun freeze_vault<BaseCoin>(vault_manager: &signer)
    acquires SatayAccount, VaultInfo {
        let vault_manager_cap = vault_manager_lock_vault<BaseCoin>(vault_manager);
        vault::freeze_vault(&vault_manager_cap);
        vault_manager_unlock_vault<BaseCoin>(vault_manager_cap);
    }

    /// unfreezes user deposits to vault_id
    /// @param vault_manager - the transaction signer; must have vault_manager role on vault_config for vault_id
    public entry fun unfreeze_vault<BaseCoin>(vault_manager: &signer)
    acquires SatayAccount, VaultInfo {
        let vault_manager_cap = vault_manager_lock_vault<BaseCoin>(vault_manager);
        vault::unfreeze_vault(&vault_manager_cap);
        vault_manager_unlock_vault<BaseCoin>(vault_manager_cap);
    }

    /// allows StrategyType to withdraw from vault_id and deposit StrategyCoin on harvest
    /// @param vault_manager - the transaction signer; must have vault_manager role on vault_config for vault_id
    /// @param vault_id - the id of the vault in the  resource
    /// @param debt_ratio - the percentage of vault's total assets available to StrategyType in BPS
    /// @param witness - reference to an instance of StrategyType used to prove the source of the call
    public(friend) fun approve_strategy<BaseCoin, StrategyType: drop>(
        vault_manager: &signer,
        debt_ratio: u64,
        witness: &StrategyType
    )
    acquires SatayAccount, VaultInfo {
        let vault_manager_cap = vault_manager_lock_vault<BaseCoin>(vault_manager);
        vault::approve_strategy<BaseCoin, StrategyType>(&vault_manager_cap, debt_ratio, witness);
        vault_manager_unlock_vault<BaseCoin>(vault_manager_cap);
    }

    /// update the debt_ratio for StrategyType
    /// @param vault_manager - the transaction signer; must have vault_manager role on vault_config for vault_id
    /// @param debt_ratio - the percentage of vault's total assets available to StrategyType in BPS
    /// @param witness - reference to an instance of StrategyType used to prove the source of the call
    public(friend) fun update_strategy_debt_ratio<BaseCoin, StrategyType: drop>(
        vault_manager: &signer,
        debt_ratio: u64,
        witness: &StrategyType
    )
    acquires SatayAccount, VaultInfo {
        let vault_manager_cap = vault_manager_lock_vault<BaseCoin>(vault_manager);
        vault::update_strategy_debt_ratio<BaseCoin, StrategyType>(
            &vault_manager_cap,
            debt_ratio,
            witness
        );
        vault_manager_unlock_vault<BaseCoin>(vault_manager_cap);
    }

    // user functions

    /// entry script to deposit BaseCoin from user into vault, returning VaultCoin<BaseCoin> to user
    /// @param user - the transaction signer; must hold at least amount of Coin<BaseCoin>
    /// @param amount - the amount of Coin<BaseCoin> to deposit
    public entry fun deposit<BaseCoin>(user: &signer, amount: u64)
    acquires SatayAccount, VaultInfo {
        let base_coins = coin::withdraw<BaseCoin>(user, amount);
        let vault_coins = deposit_as_user(user, base_coins);
        let user_addr = signer::address_of(user);
        if(!vault::is_vault_coin_registered<BaseCoin>(user_addr)){
            coin::register<VaultCoin<BaseCoin>>(user);
        };
        coin::deposit(user_addr, vault_coins);
    }

    /// converts Coin<BaseCoin> into Coin<VaultCoin<BaseCoin>> by depositing into vault_id
    /// @param user - the transaction signer
    /// @param base_coins - coins to deposit
    /// @return vault_coins - liquid wrapper for deposit
    public fun deposit_as_user<BaseCoin>(
        user: &signer,
        base_coins: Coin<BaseCoin>
    ): Coin<VaultCoin<BaseCoin>>
    acquires SatayAccount, VaultInfo {
        let user_cap = user_lock_vault<BaseCoin>(user);
        let vault_coins = vault::deposit_as_user(&user_cap, base_coins);
        user_unlock_vault<BaseCoin>(user_cap);
        vault_coins
    }

    /// entry script to withdraw BaseCoin from vault, returning BaseCoin to user
    /// @param user - the transaction signer; must hold amount of Coin<VaultCoin<BaseCoin>>
    /// @param amount - the amount of Coin<VaultCoin<BaseCoin>> to burn
    public entry fun withdraw<BaseCoin>(user: &signer, amount: u64)
    acquires SatayAccount, VaultInfo {
        let vault_coins = coin::withdraw<VaultCoin<BaseCoin>>(user, amount);
        let base_coins = withdraw_as_user(user, vault_coins);
        let user_addr = signer::address_of(user);
        if(!coin::is_account_registered<BaseCoin>(user_addr)){
            coin::register<BaseCoin>(user);
        };
        coin::deposit(user_addr, base_coins);
    }

    /// converts Coin<VaultCoin<BaseCoin>> into Coin<BaseCoin> by withdrawing from vault_id
    /// @param user - the withrdawer, must hold sufficient Coin<VaultCoin<BaseCoin>>
    /// @param vault_id - the id of the vault in the  resource
    /// @param vault_coins - coins to burn
    /// @return base_coin - underlying vault asset
    public fun withdraw_as_user<BaseCoin>(
        user: &signer,
        vault_coins: Coin<VaultCoin<BaseCoin>>
    ): Coin<BaseCoin>
    acquires SatayAccount, VaultInfo {
        let user_cap = user_lock_vault<BaseCoin>(user);
        let base_coins = vault::withdraw_as_user<BaseCoin>(&user_cap, vault_coins);
        user_unlock_vault<BaseCoin>(user_cap);
        base_coins
    }


    // strategy coin functions

    /// mint amount of StrategyCoin<BaseCoin, StrategyType>
    /// @param amount - amount to mint
    /// @param _witness - instance of StrategyType used to prove the source of the call
    public fun strategy_mint<BaseCoin, StrategyType: drop>(
        amount: u64,
        _witness: StrategyType
    ): Coin<StrategyCoin<BaseCoin, StrategyType>>
    acquires SatayAccount, StrategyInfo {
        let satay_account_address = get_satay_account_address();
        let strategy_info = borrow_global<StrategyInfo<BaseCoin, StrategyType>>(
            satay_account_address
        );
        strategy_coin::mint(option::borrow(&strategy_info.strategy_cap), amount)
    }

    /// burn amount of StrategyCoin<BaseCoin, StrategyType>
    /// @param strategy_coins - Coin<StrategyCoin<BaseCoin, StrategyType>> to burn
    /// @param _witness - instance of StrategyType used to prove the source of the call
    public fun strategy_burn<BaseCoin, StrategyType: drop>(
        strategy_coins: Coin<StrategyCoin<BaseCoin, StrategyType>>,
        _witness: StrategyType
    ) acquires SatayAccount, StrategyInfo {
        let satay_account_address = get_satay_account_address();
        let strategy_info = borrow_global<StrategyInfo<BaseCoin, StrategyType>>(
            satay_account_address
        );
        strategy_coin::burn(option::borrow(&strategy_info.strategy_cap), strategy_coins);
    }

    /// create CoinStore<CoinType> for the strategy account
    /// @param _witness - instance of StrategyType used to prove the source of the call
    public fun strategy_add_coin<BaseCoin, StrategyType: drop, CoinType>(
        _witness: StrategyType
    ) acquires SatayAccount, StrategyInfo {
        let satay_account_address = get_satay_account_address();
        let strategy_info = borrow_global<StrategyInfo<BaseCoin, StrategyType>>(
            satay_account_address
        );
        strategy_coin::add_coin<BaseCoin, StrategyType, CoinType>(option::borrow(&strategy_info.strategy_cap));
    }

    /// deposit amount of CoinType into the strategy account
    /// @param coins - Coin<CoinType> to deposit
    /// @param _witness - instance of StrategyType used to prove the source of the call
    public fun strategy_deposit<BaseCoin, StrategyType: drop, CoinType>(
        coins: Coin<CoinType>,
        _witness: StrategyType
    ) acquires SatayAccount, StrategyInfo {
        let satay_account_address = get_satay_account_address();
        let strategy_info = borrow_global<StrategyInfo<BaseCoin, StrategyType>>(
            satay_account_address
        );
        strategy_coin::deposit<BaseCoin, StrategyType, CoinType>(option::borrow(&strategy_info.strategy_cap), coins);
    }

    /// withdraw amount of CoinType from the strategy account
    /// @param amount - amount to withdraw
    /// @param _witness - instance of StrategyType used to prove the source of the call
    public fun strategy_withdraw<BaseCoin, StrategyType: drop, CoinType>(
        amount: u64,
        _witness: StrategyType
    ): Coin<CoinType> acquires SatayAccount, StrategyInfo {
        let satay_account_address = get_satay_account_address();
        let strategy_info = borrow_global<StrategyInfo<BaseCoin, StrategyType>>(
            satay_account_address
        );
        strategy_coin::withdraw<BaseCoin, StrategyType, CoinType>(option::borrow(&strategy_info.strategy_cap), amount)
    }

    // lock/unlock

    /// get the VaultCapability for Vault<BaseCoin>
    fun lock_vault<BaseCoin>(): VaultCapability<BaseCoin>
    acquires SatayAccount, VaultInfo {
        let satay_account_address = get_satay_account_address();
        let vault_info = borrow_global_mut<VaultInfo<BaseCoin>>(satay_account_address);
        option::extract(&mut vault_info.vault_cap)
    }

    /// return the VaultCapability for Vault<BaseCoin>
    fun unlock_vault<BaseCoin>(vault_cap: VaultCapability<BaseCoin>)
    acquires SatayAccount, VaultInfo {
        let satay_account_address = get_satay_account_address();
        let vault_info = borrow_global_mut<VaultInfo<BaseCoin>>(satay_account_address);
        option::fill(&mut vault_info.vault_cap, vault_cap);
    }

    /// get the VaultCapability for Vault<BaseCoin> and assert that (BaseCoin, StrategyType) is approved
    /// @param _witness - reference to an instance of StrategyType used to prove the source of the call
    fun strategy_lock_vault<BaseCoin, StrategyType: drop>(_witness: &StrategyType): VaultCapability<BaseCoin>
    acquires SatayAccount, VaultInfo {
        let vault_cap = lock_vault<BaseCoin>();
        assert_strategy_approved<BaseCoin, StrategyType>(&vault_cap);
        vault_cap
    }

    /// return the VaultCapability for Vault<BaseCoin>
    /// @param vault_cap - VaultCapability for Vault<BaseCoin>
    fun strategy_unlock_vault<BaseCoin, StrategyType: drop>(vault_cap: VaultCapability<BaseCoin>)
    acquires SatayAccount, VaultInfo {
        unlock_vault(vault_cap);
    }

    /// get the VaultManagerCapability for Vault<BaseCoin>
    /// @param vault_manager - the transaction signer; must have the vault manager role on satay::vault_config
    fun vault_manager_lock_vault<BaseCoin>(vault_manager: &signer): VaultManagerCapability<BaseCoin>
    acquires SatayAccount, VaultInfo {
        let vault_cap = lock_vault<BaseCoin>();
        vault::get_vault_manager_capability(vault_manager, vault_cap)
    }

    /// return the VaultManagerCapability for Vault<BaseCoin>
    /// @param vault_manager_cap - VaultManagerCapability for Vault<BaseCoin>
    fun vault_manager_unlock_vault<BaseCoin>(vault_manager_cap: VaultManagerCapability<BaseCoin>)
    acquires SatayAccount, VaultInfo {
        let vault_cap = vault::destroy_vault_manager_capability(vault_manager_cap);
        unlock_vault(vault_cap);
    }

    /// get the KeeperCapability for Vault<BaseCoin>, StrategyType must be approved
    /// @param keeper - the transaction signer; must hold the keeper role for StrategyType on satay::keeper_config
    /// @param witness - instance of StrategyType used to prove the source of the call
    public(friend) fun keeper_lock_vault<BaseCoin, StrategyType: drop>(
        keeper: &signer,
        witness: StrategyType
    ): KeeperCapability<BaseCoin, StrategyType>
    acquires SatayAccount, VaultInfo {
        let vault_cap = strategy_lock_vault<BaseCoin, StrategyType>(&witness);
        vault::get_keeper_capability<BaseCoin, StrategyType>(keeper, vault_cap, witness)
    }

    /// destroy the KeeperCapability, vault_cap and stop_handle must match
    /// @param keeper_cap - KeeperCapability for vault referenced by vault_id in preceding call to keeper_lock_vault
    /// @param vault_cap_lock - holds the vault_id for vault_cap
    public(friend) fun keeper_unlock_vault<BaseCoin, StrategyType: drop>(
        keeper_cap: KeeperCapability<BaseCoin, StrategyType>,
    ) acquires SatayAccount, VaultInfo {
        let vault_cap = vault::destroy_keeper_capability(keeper_cap);
        strategy_unlock_vault<BaseCoin, StrategyType>(vault_cap);
    }

    /// get the UserCapability of vault_id for use by StrategyType, StrategyType must be approved first
    /// followed by a subsequent call to user_unlock_vault
    /// @param user - the transaction signer
    /// @param witness - reference to an instance of StrategyType used to prove the source of the call
    public(friend) fun user_lock_vault<BaseCoin>(
        user: &signer,
    ) : UserCapability<BaseCoin>
    acquires SatayAccount, VaultInfo {
        let vault_cap = lock_vault<BaseCoin>();
        vault::get_user_capability(user, vault_cap)
    }

    /// destroy the UserCapability, vault_cap and stop_handle must match
    /// @param user_cap - UserCapability for vault referenced by vault_id in preceding call to user_lock_vault
    /// @param vault_cap_lock - holds the vault_id for vault_cap
    public(friend) fun user_unlock_vault<BaseCoin>(
        user_cap: UserCapability<BaseCoin>,
    ) acquires SatayAccount, VaultInfo {
        let (vault_cap, _) = vault::destroy_user_capability(user_cap);
        unlock_vault<BaseCoin>(vault_cap);
    }

    // getter functions

    // satay account

    #[view]
    /// gets the address of the satay account
    public fun get_satay_account_address(): address acquires SatayAccount {
        let satay_account = borrow_global<SatayAccount>(@satay);
        account::get_signer_capability_address(&satay_account.signer_cap)
    }
    
    // vault fields

    #[view]
    /// returns the address of Vault<BaseCoin>
    public fun get_vault_address<BaseCoin>(): address
    acquires SatayAccount, VaultInfo {
        let satay_account_address = get_satay_account_address();
        vault::get_vault_address(
            option::borrow(&borrow_global<VaultInfo<BaseCoin>>(satay_account_address).vault_cap)
        )
    }

    #[view]
    /// returns the management fee and performance fee for vault_id
    /// @param vault_id - the id of the vault in the  resource
    public fun get_vault_fees<BaseCoin>(): (u64, u64)
    acquires SatayAccount, VaultInfo {
        let satay_account_address = get_satay_account_address();
        vault::get_fees(
            option::borrow(&borrow_global<VaultInfo<BaseCoin>>(satay_account_address).vault_cap)
        )
    }

    #[view]
    /// returns whether depoosts are frozen for vault_id
    /// @param vault_id - the id of the vault in the  resource
    public fun is_vault_frozen<BaseCoin>(): bool
    acquires SatayAccount, VaultInfo {
        let satay_account_address = get_satay_account_address();
        vault::is_vault_frozen(
            option::borrow(&borrow_global<VaultInfo<BaseCoin>>(satay_account_address).vault_cap)
        )
    }

    #[view]
    /// returns the total debt ratio for vault_id
    /// @param vault_id - the id of the vault in the  resource
    public fun get_vault_debt_ratio<BaseCoin>(): u64
    acquires SatayAccount, VaultInfo {
        let satay_account_address = get_satay_account_address();
        vault::get_debt_ratio(
            option::borrow(&borrow_global<VaultInfo<BaseCoin>>(satay_account_address).vault_cap)
        )
    }

    #[view]
    /// returns the total debt of vault_id
    /// @param vault_id - the id of the vault in the  resource
    public fun get_total_debt<BaseCoin>(): u64
    acquires SatayAccount, VaultInfo {
        let satay_account_address = get_satay_account_address();
        vault::get_total_debt(
            option::borrow(&borrow_global<VaultInfo<BaseCoin>>(satay_account_address).vault_cap)
        )
    }

    #[view]
    /// returns the total balance of CoinType in Vault<BaseCoin>
    public fun get_vault_balance<BaseCoin, CoinType>(): u64
    acquires SatayAccount, VaultInfo {
        let satay_account_address = get_satay_account_address();
        vault::balance<BaseCoin, CoinType>(
            option::borrow(&borrow_global<VaultInfo<BaseCoin>>(satay_account_address).vault_cap)
        )
    }

    #[view]
    /// returns the total assets of vault_id
    /// @param vault_id - the id of the vault in the  resource
    public fun get_total_assets<BaseCoin>(): u64
    acquires SatayAccount, VaultInfo {
        let satay_account_address = get_satay_account_address();
        vault::total_assets(
            option::borrow(&borrow_global<VaultInfo<BaseCoin>>(satay_account_address).vault_cap)
        )
    }

    #[view]
    /// returns the address of the vault manager for Vault<BaseCoin>
    /// REMOVE IN NEXT DEPLOYMENT
    public fun get_vault_manager<BaseCoin>(): address
    acquires SatayAccount, VaultInfo {
        vault_config::get_vault_manager_address(get_vault_address<BaseCoin>())
    }

    #[view]
    /// returns the address of the vault manager for Vault<BaseCoin>
    public fun get_vault_manager_address<BaseCoin>(): address
    acquires SatayAccount, VaultInfo {
        vault_config::get_vault_manager_address(get_vault_address<BaseCoin>())
    }

    // strategy fields

    #[view]
    /// returns whether vault_id has StrategyType approved
    /// @param vault_id - the id of the vault in the  resource
    public fun has_strategy<BaseCoin, StrategyType: drop>(): bool
    acquires SatayAccount, VaultInfo {
        let satay_account_address = get_satay_account_address();
        vault::has_strategy<BaseCoin, StrategyType>(
            option::borrow(&borrow_global<VaultInfo<BaseCoin>>(satay_account_address).vault_cap)
        )
    }

    #[view]
    /// returns the address of the strategy resource account
    public fun get_strategy_address<BaseCoin, StrategyType: drop>(): address
    acquires SatayAccount, StrategyInfo {
        let satay_account_address = get_satay_account_address();
        strategy_coin::strategy_account_address(
            option::borrow(&borrow_global<StrategyInfo<BaseCoin, StrategyType>>(satay_account_address).strategy_cap)
        )
    }

    #[view]
    /// returns the CoinType balance of the strategy resource account
    public fun get_strategy_balance<BaseCoin, StrategyType: drop, CoinType>(): u64
    acquires SatayAccount, StrategyInfo {
        let satay_account_address = get_satay_account_address();
        strategy_coin::balance<BaseCoin, StrategyType, CoinType>(
            option::borrow(&borrow_global<StrategyInfo<BaseCoin, StrategyType>>(satay_account_address).strategy_cap)
        )
    }

    #[view]
    /// returns total debt for StrategyType on vault_id
    /// @param vault_id - the id of the vault in the  resource
    public fun get_strategy_total_debt<BaseCoin, StrategyType: drop>(): u64
    acquires SatayAccount, VaultInfo {
        let satay_account_address = get_satay_account_address();
        vault::total_debt<BaseCoin, StrategyType>(
            option::borrow(&borrow_global<VaultInfo<BaseCoin>>(satay_account_address).vault_cap)
        )
    }

    #[view]
    /// returns the debt ratio for StrategyType for vault_id
    /// @param vault_id - the id of the vault in the  resource
    public fun get_strategy_debt_ratio<BaseCoin, StrategyType: drop>(): u64
    acquires SatayAccount, VaultInfo {
        let satay_account_address = get_satay_account_address();
        vault::debt_ratio<BaseCoin, StrategyType>(
            option::borrow(&borrow_global<VaultInfo<BaseCoin>>(satay_account_address).vault_cap)
        )
    }

    #[view]
    /// returns the credit availale for StrategyType for vault_id
    /// @param vault_id - the id of the vault in the  resource
    public fun get_credit_available<BaseCoin, StrategyType: drop>(): u64
    acquires SatayAccount, VaultInfo {
        let satay_account_address = get_satay_account_address();
        vault::credit_available<BaseCoin, StrategyType>(
            option::borrow(&borrow_global<VaultInfo<BaseCoin>>(satay_account_address).vault_cap)
        )
    }

    #[view]
    /// returns the outstanding debt for StrategyType for vault_id
    /// @param vault_id - the id of the vault in the  resource
    public fun get_debt_out_standing<BaseCoin, StrategyType: drop>(): u64
    acquires SatayAccount, VaultInfo {
        let satay_account_address = get_satay_account_address();
        vault::debt_out_standing<BaseCoin, StrategyType>(
            option::borrow(&borrow_global<VaultInfo<BaseCoin>>(satay_account_address).vault_cap)
        )
    }

    #[view]
    /// returns the timestamp of the last harvest for StrategyType for vault_id
    /// @param vault_id - the id of the vault in the  resource
    public fun get_last_report<BaseCoin, StrategyType: drop>(): u64
    acquires SatayAccount, VaultInfo {
        let satay_account_address = get_satay_account_address();
        vault::last_report<BaseCoin, StrategyType>(
            option::borrow(&borrow_global<VaultInfo<BaseCoin>>(satay_account_address).vault_cap)
        )
    }

    #[view]
    /// get the total gain for StrategyType for vault_id
    /// @param vault_id - the id of the vault in the  resource
    public fun get_total_gain<BaseCoin, StrategyType: drop>(): u64
    acquires SatayAccount, VaultInfo {
        let satay_account_address = get_satay_account_address();
        vault::total_gain<BaseCoin, StrategyType>(
            option::borrow(&borrow_global<VaultInfo<BaseCoin>>(satay_account_address).vault_cap)
        )
    }

    #[view]
    /// get the total loss for StrategyType for vault_id
    /// @param vault_id - the id of the vault in the  resource
    public fun get_total_loss<BaseCoin, StrategyType: drop>(): u64
    acquires SatayAccount, VaultInfo {
        let satay_account_address = get_satay_account_address();
        vault::total_loss<BaseCoin, StrategyType>(
            option::borrow(&borrow_global<VaultInfo<BaseCoin>>(satay_account_address).vault_cap)
        )
    }

    // user calculations

    #[view]
    /// returns the amount of VaultCoin minted for an amount of BaseCoin deposited to vault_id
    /// @param base_coin_amount - the amount of BaseCoin to deposit
    public fun get_vault_coin_amount<BaseCoin>(base_coin_amount: u64): u64
    acquires SatayAccount, VaultInfo {
        let satay_account_address = get_satay_account_address();
        vault::calculate_vault_coin_amount_from_base_coin_amount<BaseCoin>(
            option::borrow(&borrow_global<VaultInfo<BaseCoin>>(satay_account_address).vault_cap),
            base_coin_amount
        )
    }

    #[view]
    /// returns the amount of BaseCoin returned from vault_id by burining an amount of VaultCoin<BaseCoin>
    /// vault_coin_amount - the amount of VaultCoin<BaseCoin> to burn
    public fun get_base_coin_amount<BaseCoin>(vault_coin_amount: u64): u64
    acquires SatayAccount, VaultInfo {
        let satay_account_address = get_satay_account_address();
        vault::calculate_base_coin_amount_from_vault_coin_amount<BaseCoin>(
            option::borrow(&borrow_global<VaultInfo<BaseCoin>>(satay_account_address).vault_cap),
            vault_coin_amount
        )
    }

    #[view]
    /// returns the address of the strategy manager for (BaseCoin, StrategyType)
    public fun get_strategy_manager_address<BaseCoin, StrategyType: drop>(): address
    acquires SatayAccount, StrategyInfo {
        strategy_config::get_strategy_manager_address<BaseCoin, StrategyType>(
            get_strategy_address<BaseCoin, StrategyType>()
        )
    }

    #[view]
    /// returns the address of the keeper for (BaseCoin, StrategyType)
    public fun get_keeper_address<BaseCoin, StrategyType: drop>(): address
    acquires SatayAccount, VaultInfo {
        keeper_config::get_keeper_address<BaseCoin, StrategyType>(get_vault_address<BaseCoin>())
    }

    // assert statements

    /// asserts that StrategyType is approved on the vault controlled by vault_cap
    /// @param vault_cap - a VaultCapability reference
    fun assert_strategy_approved<BaseCoin, StrategyType: drop>(vault_cap: &VaultCapability<BaseCoin>) {
        assert!(vault::has_strategy<BaseCoin, StrategyType>(vault_cap), ERR_STRATEGY);
    }

    // test functions

    #[test_only]
    public fun test_lock_vault<BaseCoin>(): VaultCapability<BaseCoin>
    acquires SatayAccount, VaultInfo {
        lock_vault<BaseCoin>()
    }

    #[test_only]
    public fun test_unlock_vault<BaseCoin>(vault_cap: VaultCapability<BaseCoin>)
    acquires SatayAccount, VaultInfo {
        unlock_vault<BaseCoin>(vault_cap);
    }

    #[test_only]
    public fun test_strategy_lock_vault<BaseCoin, StrategyType: drop>(witness: &StrategyType): VaultCapability<BaseCoin>
    acquires SatayAccount, VaultInfo {
        strategy_lock_vault<BaseCoin, StrategyType>(witness)
    }

    #[test_only]
    public fun test_strategy_unlock_vault<BaseCoin, StrategyType: drop>(vault_cap: VaultCapability<BaseCoin>)
    acquires SatayAccount, VaultInfo {
        strategy_unlock_vault<BaseCoin, StrategyType>(vault_cap)
    }

    #[test_only]
    public fun test_keeper_lock_vault<BaseCoin, StrategyType: drop>(
        keeper: &signer,
        witness: StrategyType
    ): KeeperCapability<BaseCoin, StrategyType>
    acquires SatayAccount, VaultInfo {
        keeper_lock_vault<BaseCoin, StrategyType>(keeper, witness)
    }

    #[test_only]
    public fun test_keeper_unlock_vault<BaseCoin, StrategyType: drop>(
        keeper_cap: KeeperCapability<BaseCoin, StrategyType>
    )
    acquires SatayAccount, VaultInfo {
        keeper_unlock_vault<BaseCoin, StrategyType>(keeper_cap);
    }

    #[test_only]
    public fun test_user_lock_vault<BaseCoin>(
        user: &signer,
    ): UserCapability<BaseCoin>
    acquires SatayAccount, VaultInfo {
        user_lock_vault<BaseCoin>(user)
    }

    #[test_only]
    public fun test_user_unlock_vault<BaseCoin>(
        user_cap: UserCapability<BaseCoin>,
    ) acquires SatayAccount, VaultInfo {
        user_unlock_vault<BaseCoin>(user_cap);
    }

    #[test_only]
    public fun test_approve_strategy<BaseCoin, StrategyType: drop>(
        vault_manager: &signer,
        debt_ratio: u64,
        witness: StrategyType,
    ) acquires SatayAccount, VaultInfo {
        approve_strategy<BaseCoin, StrategyType>(vault_manager, debt_ratio, &witness);
    }

    #[test_only]
    public fun test_update_strategy_debt_ratio<BaseCoin, StrategyType: drop>(
        vault_manager: &signer,
        debt_ratio: u64,
        witness: StrategyType
    ) acquires SatayAccount, VaultInfo {
        update_strategy_debt_ratio<BaseCoin, StrategyType>(vault_manager, debt_ratio, &witness);
    }
}