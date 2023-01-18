/// User and strategy entry point to vaults
/// Holds all vault capabilities
module satay::satay {

    use std::option::{Self, Option};
    use std::signer;

    use aptos_std::type_info::TypeInfo;
    use aptos_std::table::{Self, Table};

    use aptos_framework::coin::{Self, Coin};

    use satay::global_config;
    use satay::vault::{Self, VaultCapability, VaultCoin};

    friend satay::base_strategy;

    // error codes

    /// manager is not initialized
    const ERR_MANAGER: u64 = 1;

    /// strategy is not approved for vault
    const ERR_STRATEGY: u64 = 2;

    /// when the vault id of VaultCapability and VaultCapLock do not match
    const ERR_VAULT_CAP: u64 = 3;

    /// holds all VaultCapability resources in a mapping from vault_id to VaultInfo
    struct ManagerAccount has key {
        next_vault_id: u64,
        vaults: Table<u64, VaultInfo>,
    }

    /// holds a VaultCapability resource in an option to allow lending to strategies
    struct VaultInfo has store {
        vault_cap: Option<VaultCapability>,
    }

    /// returned by lock_vault to ensure a subsequent call to unlock_vault
    struct VaultCapLock<phantom StrategyType: drop> {
        vault_id: u64,
    }

    /// create and store ManagerAccount
    /// @param satay - singing account, must be deployer account
    public entry fun initialize(
        satay: &signer
    ) {
        // asserts that signer::address_of(satay) == @satay
        global_config::initialize(satay);
        move_to(satay, ManagerAccount { vaults: table::new(), next_vault_id: 0 });
    }

    // governance functions

    /// create new vault for BaseCoin
    /// @param governance - signing account, must hold governance role in global_config
    /// @param management_fee - the vault's fee in BPS, charged annually
    /// @param performance_fee - the vault's performance fee in bips, charged on profits
    public entry fun new_vault<BaseCoin>(
        governance: &signer,
        management_fee: u64,
        performance_fee: u64
    ) acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global_mut<ManagerAccount>(@satay);

        // get vault id and update next id
        let vault_id = account.next_vault_id;
        account.next_vault_id = account.next_vault_id + 1;

        // create vault and add to manager vaults table
        let vault_cap = vault::new<BaseCoin>(governance, vault_id, management_fee, performance_fee);
        table::add(
            &mut account.vaults,
            vault_id,
            VaultInfo {
                vault_cap: option::some(vault_cap),
            }
        );
    }

    // vault manager fucntions

    /// updates the management and performance fee for vault_id
    /// @param vault_manager - must have vault_manager role on vault_config for vault_id
    /// @param vault_id - the id of the vault in the ManagerAccount resource
    /// @param management_fee - the vault's fee in BPS, charged annually
    /// @param performance_fee - the vault's performance fee in bips, charged on profits
    public entry fun update_vault_fee(
        vault_manager: &signer,
        vault_id: u64,
        management_fee: u64,
        performance_fee: u64
    ) acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global_mut<ManagerAccount>(@satay);

        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        let vault_cap = option::extract(&mut vault_info.vault_cap);

        let vault_manager_cap = vault::get_vault_manager_capability(vault_manager, vault_cap);
        vault::update_fee(
            &vault_manager_cap,
            management_fee,
            performance_fee
        );

        option::fill(&mut vault_info.vault_cap, vault::destroy_vault_manager_capability(vault_manager_cap));
    }

    /// freezes user deposits to vault_id
    /// @param vault_manager - must have vault_manager role on vault_config
    /// @param vault_id - the id of the vault in the ManagerAccount resource
    public entry fun freeze_vault(
        vault_manager: &signer,
        vault_id: u64
    ) acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global_mut<ManagerAccount>(@satay);

        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        let vault_cap = option::extract(&mut vault_info.vault_cap);

        let vault_manager_cap = vault::get_vault_manager_capability(vault_manager, vault_cap);
        vault::freeze_vault(
            &vault_manager_cap
        );

        option::fill(&mut vault_info.vault_cap, vault::destroy_vault_manager_capability(vault_manager_cap));
    }

    /// unfreezes user deposits to vault_id
    /// @param vault_manager - must have vault_manager role on vault_config
    /// @param vault_id - the id of the vault in the ManagerAccount resource
    public entry fun unfreeze_vault(
        vault_manager: &signer,
        vault_id: u64
    ) acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global_mut<ManagerAccount>(@satay);

        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        let vault_cap = option::extract(&mut vault_info.vault_cap);

        let vault_manager_cap = vault::get_vault_manager_capability(vault_manager, vault_cap);
        vault::unfreeze_vault(
            &vault_manager_cap
        );

        option::fill(&mut vault_info.vault_cap, vault::destroy_vault_manager_capability(vault_manager_cap));
    }

    /// allows StrategyType to withdraw from vault_id and deposit StrategyCoin on harvest and tend
    /// @param vault_manager - must have vault_manager role on vault_config
    /// @param vault_id - the id of the vault in the ManagerAccount resource
    /// @param debt_ratio - the percentage of vault's total assets available to StrategyType in BPS
    /// @param witness - reference to an instance of StrategyType used to prove the source of the call
    public(friend) fun approve_strategy<StrategyType: drop, StrategyCoin>(
        vault_manager: &signer,
        vault_id: u64,
        debt_ratio: u64,
        witness: &StrategyType
    ) acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global_mut<ManagerAccount>(@satay);

        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        let vault_cap = option::extract(&mut vault_info.vault_cap);

        let vault_manager_cap = vault::get_vault_manager_capability(vault_manager, vault_cap);
        vault::approve_strategy<StrategyType, StrategyCoin>(
            &vault_manager_cap,
            debt_ratio,
            witness
        );

        option::fill(&mut vault_info.vault_cap, vault::destroy_vault_manager_capability(vault_manager_cap));
    }

    /// update the debt_ratio for StrategyType
    /// @param vault_manager - must have vault_manager role on vault_config
    /// @param vault_id - the id of the vault in the ManagerAccount resource
    /// @param debt_ratio - the percentage of vault's total assets available to StrategyType in BPS
    /// @param witness - reference to an instance of StrategyType used to prove the source of the call
    public(friend) fun update_strategy_debt_ratio<StrategyType: drop>(
        vault_manager: &signer,
        vault_id: u64,
        debt_ratio: u64,
        witness: &StrategyType
    ): u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global_mut<ManagerAccount>(@satay);

        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        let vault_cap = option::extract(&mut vault_info.vault_cap);
        assert_strategy_approved<StrategyType>(&vault_cap);

        let vault_manager_cap = vault::get_vault_manager_capability(
            vault_manager,
            vault_cap
        );
        vault::update_strategy_debt_ratio<StrategyType>(
            &vault_manager_cap,
            debt_ratio,
            witness
        );

        option::fill(&mut vault_info.vault_cap, vault::destroy_vault_manager_capability(vault_manager_cap));

        debt_ratio
    }

    // user functions

    /// entry script to deposit BaseCoin from user into vault, returning VaultCoin<BaseCoin> to user
    /// @param user - the depositor, must hold sufficient Coin<BaseCoin>
    /// @param vault_id - the id of the vault in the ManagerAccount resource
    /// @param amount - the amount of BaseCoin to deposit
    public entry fun deposit<BaseCoin>(
        user: &signer,
        vault_id: u64,
        amount: u64
    ) acquires ManagerAccount {
        let base_coins = coin::withdraw<BaseCoin>(user, amount);

        let vault_coins = deposit_as_user(user, vault_id, base_coins);

        let user_addr = signer::address_of(user);
        if(!vault::is_vault_coin_registered<BaseCoin>(user_addr)){
            coin::register<VaultCoin<BaseCoin>>(user);
        };
        coin::deposit(user_addr, vault_coins);
    }

    /// logic to deposit BaseCoin from user into vault
    /// @param user - the depositor, must hold sufficient Coin<BaseCoin>
    /// @param vault_id - the id of the vault in the ManagerAccount resource
    /// @param base_coins - coins to deposit
    /// @return vault_coins - liquid wrapper for deposit
    public fun deposit_as_user<BaseCoin>(
        user: &signer,
        vault_id: u64,
        base_coins: Coin<BaseCoin>
    ): Coin<VaultCoin<BaseCoin>> acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global_mut<ManagerAccount>(@satay);
        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        let vault_cap = option::extract(&mut vault_info.vault_cap);

        let user_cap = vault::get_user_capability(
            user,
            vault_cap,
        );

        let vault_coins = vault::deposit_as_user(&user_cap, base_coins);

        let (
            vault_cap,
            _
        ) = vault::destroy_user_capability(user_cap);

        option::fill(&mut vault_info.vault_cap, vault_cap);

        vault_coins
    }

    /// entry script to withdraw BaseCoin from vault to user, burns VaultCoin<BaseCoin>
    /// @param user - the withrdawer, must hold sufficient Coin<VaultCoin<BaseCoin>>
    /// @param vault_id - the id of the vault in the ManagerAccount resource
    /// @param amount - the amount of VaultCoin<BaseCoin> to burn
    public entry fun withdraw<BaseCoin>(
        user: &signer,
        vault_id: u64,
        amount: u64
    ) acquires ManagerAccount {
        let vault_coins = coin::withdraw<VaultCoin<BaseCoin>>(user, amount);

        let base_coins = withdraw_as_user(user, vault_id, vault_coins);

        let user_addr = signer::address_of(user);
        if(!coin::is_account_registered<BaseCoin>(user_addr)){
            coin::register<BaseCoin>(user);
        };
        coin::deposit(user_addr, base_coins);
    }

    /// logic to withdraw BaseCoin from vault for user
    /// @param user - the withrdawer, must hold sufficient Coin<VaultCoin<BaseCoin>>
    /// @param vault_id - the id of the vault in the ManagerAccount resource
    /// @param vault_coins - coins to burn
    /// @return base_coin - underlying vault asset
    public fun withdraw_as_user<BaseCoin>(
        user: &signer,
        vault_id: u64,
        vault_coins: Coin<VaultCoin<BaseCoin>>
    ): Coin<BaseCoin> acquires ManagerAccount {
        let account = borrow_global_mut<ManagerAccount>(@satay);
        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        let vault_cap = option::extract(&mut vault_info.vault_cap);

        let user_cap = vault::get_user_capability(
            user,
            vault_cap,
        );

        let base_coins = vault::withdraw_as_user<BaseCoin>(&user_cap, vault_coins);

        let (
            vault_cap,
            _
        ) = vault::destroy_user_capability(user_cap);
        option::fill(&mut vault_info.vault_cap, vault_cap);

        base_coins
    }

    // strategy functions

    /// get the VaultCapability for vault_id for StrategyType, StrategyType must be approved first
    /// @param vault_id - the id of the vault in the ManagerAccount resource
    /// @param _witness - reference to an instance of StrategyType used to prove the source of the call
    /// @returns vault_capability - the VaultCapability for the desired vault
    /// @returns stop_handle - holds the vault_id and StrategyType for checks in unlock_vault
    public(friend) fun lock_vault<StrategyType: drop>(
        vault_id: u64,
        _witness: &StrategyType
    ): (VaultCapability, VaultCapLock<StrategyType>) acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global_mut<ManagerAccount>(@satay);

        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);

        // assert that strategy is approved for vault
        assert_strategy_approved<StrategyType>(option::borrow(&vault_info.vault_cap));

        let vault_cap = option::extract(&mut vault_info.vault_cap);
        let stop_handle = VaultCapLock {
            vault_id,
        };
        (vault_cap, stop_handle)
    }

    /// return the VaultCapability to ManagerAccount, vault_cap and stop_handle must match
    /// @param vault_cap - VaultCapability for vault referenced by vault_id in preceding call to lock_vault
    /// @param stop_handle - holds the vault_id for vault_cap
    public(friend) fun unlock_vault<StrategyType: drop>(
        vault_cap: VaultCapability,
        stop_handle: VaultCapLock<StrategyType>
    ) acquires ManagerAccount {
        // assert that correct VaultCapLock for VaultCapability is passed
        assert_vault_cap_and_stop_handle_match(&vault_cap, &stop_handle);

        let VaultCapLock<StrategyType> {
            vault_id,
        } = stop_handle;

        let account = borrow_global_mut<ManagerAccount>(@satay);
        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        assert_strategy_approved<StrategyType>(&vault_cap);
        option::fill(&mut vault_info.vault_cap, vault_cap);
    }

    // getter functions

    // ManagerAccount fields

    /// gets the next vault_id, which is also the number of active vaults
    public fun get_next_vault_id(): u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        account.next_vault_id
    }

    // vault fields

    /// returns the vault address from a vault_id
    /// @param vault_id - the id of the vault in the ManagerAccount resource
    public fun get_vault_address_by_id(vault_id: u64): address acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::get_vault_addr(vault_cap)
    }

    /// returns the BaseCoin for vault_id
    /// @param vault_id - the id of the vault in the ManagerAccount resource
    public fun get_base_coin_by_id(vault_id: u64): TypeInfo acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::get_base_coin_type(vault_cap)
    }

    /// returns the management fee and performance fee for vault_id
    /// @param vault_id - the id of the vault in the ManagerAccount resource
    public fun get_vault_fees(vault_id: u64): (u64, u64) acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        vault::get_fees(option::borrow(&vault_info.vault_cap))
    }

    /// returns whether depoosts are frozen for vault_id
    /// @param vault_id - the id of the vault in the ManagerAccount resource
    public fun is_vault_frozen(vault_id: u64): bool acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        vault::is_vault_frozen(option::borrow(&vault_info.vault_cap))
    }

    /// returns the total debt ratio for vault_id
    /// @param vault_id - the id of the vault in the ManagerAccount resource
    public fun get_vault_debt_ratio(vault_id: u64): u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        vault::get_debt_ratio(option::borrow(&vault_info.vault_cap))
    }

    /// returns the total debt of vault_id
    /// @param vault_id - the id of the vault in the ManagerAccount resource
    public fun get_total_debt(vault_id: u64): u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        vault::get_total_debt(option::borrow(&vault_info.vault_cap))
    }

    /// returns the total assets of vault_id
    /// @param vault_id - the id of the vault in the ManagerAccount resource
    public fun get_total_assets<BaseCoin>(vault_id: u64): u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::total_assets<BaseCoin>(vault_cap)
    }

    // strategy fields

    /// returns whether vault_id has StrategyType approved
    /// @param vault_id - the id of the vault in the ManagerAccount resource
    public fun has_strategy<StrategyType: drop>(
        vault_id: u64,
    ) : bool acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        vault::has_strategy<StrategyType>(option::borrow(&vault_info.vault_cap))
    }

    /// returns total debt for StrategyType on vault_id
    /// @param vault_id - the id of the vault in the ManagerAccount resource
    public fun get_strategy_total_debt<StrategyType: drop>(
        vault_id: u64,
    ) : u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::total_debt<StrategyType>(vault_cap)
    }

    /// returns the debt ratio for StrategyType for vault_id
    /// @param vault_id - the id of the vault in the ManagerAccount resource
    public fun get_strategy_debt_ratio<StrategyType: drop>(
        vault_id: u64,
    ) : u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::debt_ratio<StrategyType>(vault_cap)
    }

    /// returns the credit availale for StrategyType for vault_id
    /// @param vault_id - the id of the vault in the ManagerAccount resource
    public fun get_credit_available<StrategyType: drop, BaseCoin>(
        vault_id: u64,
    ): u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::credit_available<StrategyType, BaseCoin>(vault_cap)
    }

    /// returns the outstanding debt for StrategyType for vault_id
    /// @param vault_id - the id of the vault in the ManagerAccount resource
    public fun get_debt_out_standing<StrategyType: drop, BaseCoin>(
        vault_id: u64,
    ): u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::debt_out_standing<StrategyType, BaseCoin>(vault_cap)
    }

    /// returns the timestamp of the last harvest for StrategyType for vault_id
    /// @param vault_id - the id of the vault in the ManagerAccount resource
    public fun get_last_report<StrategyType: drop>(
        vault_id: u64,
    ): u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::last_report<StrategyType>(vault_cap)
    }

    /// returns the type of the strategy coin for StrategyType for vault_id
    /// @param vault_id - the id of the vault in the ManagerAccount resource
    public fun get_strategy_coin_type<StrategyType: drop>(
        vault_id: u64,
    ): TypeInfo acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::get_strategy_coin_type<StrategyType>(vault_cap)
    }

    /// get the total gain for StrategyType for vault_id
    /// @param vault_id - the id of the vault in the ManagerAccount resource
    public fun get_total_gain<StrategyType: drop, BaseCoin>(
        vault_id: u64,
    ): u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::total_gain<StrategyType>(vault_cap)
    }

    /// get the total loss for StrategyType for vault_id
    /// @param vault_id - the id of the vault in the ManagerAccount resource
    public fun get_total_loss<StrategyType: drop, BaseCoin>(
        vault_id: u64,
    ): u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::total_loss<StrategyType>(vault_cap)
    }

    // user calculations

    /// returns the amount of VaultCoin minted for an amount of BaseCoin deposited to vault_id
    /// @param vault_id - the id of the vault in the ManagerAccount resource
    /// @param base_coin_amount - the amount of BaseCoin to deposit
    public fun get_vault_coin_amount<BaseCoin>(
        vault_id: u64,
        base_coin_amount: u64,
    ): u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::calculate_vault_coin_amount_from_base_coin_amount<BaseCoin>(vault_cap, base_coin_amount)
    }

    /// returns the amount of BaseCoin returned from vault_id by burining an amount of VaultCoin<BaseCoin>
    /// @param vault_id - the id of the vault in the ManagerAccount resource
    /// vault_coin_amount - the amount of VaultCoin<BaseCoin> to burn
    public fun get_base_coin_amount<BaseCoin>(
        vault_id: u64,
        vault_coin_amount: u64,
    ): u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::calculate_base_coin_amount_from_vault_coin_amount<BaseCoin>(vault_cap, vault_coin_amount)
    }

    // assert statements

    /// asserts that the BaseCoin generic is the correct BaseCoin for vault_id
    /// @param vault_id - the id of the vault in the ManagerAccount resource
    public fun assert_base_coin_correct_for_vault<BaseCoin>(
        vault_id: u64,
    ) acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::assert_base_coin_correct_for_vault_cap<BaseCoin>(vault_cap);
    }

    /// asserts that the ManagerAccount is initialized
    fun assert_manager_initialized() {
        assert!(exists<ManagerAccount>(@satay), ERR_MANAGER);
    }

    /// asserts that the vault_id for a given VaultCapability and VaultCapLock are equal, called by unlock_vault
    /// @param vault_cap - a VaultCapability reference
    /// @param stop_handle - A VaultCapLock reference
    fun assert_vault_cap_and_stop_handle_match<StrategyType: drop>(
        vault_cap: &VaultCapability,
        stop_handle: &VaultCapLock<StrategyType>,
    ) {
        assert!(vault::vault_cap_has_id(vault_cap, stop_handle.vault_id), ERR_VAULT_CAP);
    }

    /// asserts that StrategyType is approved on the vault controlled by vault_cap
    /// @param vault_cap - a VaultCapability reference
    fun assert_strategy_approved<StrategyType: drop>(
        vault_cap: &VaultCapability
    ) {
        assert!(vault::has_strategy<StrategyType>(vault_cap), ERR_STRATEGY);
    }

    #[test_only]
    public fun open_vault(vault_id: u64): VaultCapability acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global_mut<ManagerAccount>(@satay);
        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        option::extract(&mut vault_info.vault_cap)
    }

    #[test_only]
    public fun close_vault(vault_id: u64, vault_cap: VaultCapability) acquires ManagerAccount {
        assert!(
            vault::vault_cap_has_id(&vault_cap, vault_id),
            ERR_VAULT_CAP
        );
        let account = borrow_global_mut<ManagerAccount>(@satay);
        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        option::fill(&mut vault_info.vault_cap, vault_cap);
    }

    #[test_only]
    public fun test_lock_vault<StrategyType: drop>(
        vault_id: u64,
        witness: &StrategyType,
    ): (VaultCapability, VaultCapLock<StrategyType>) acquires ManagerAccount {
        lock_vault<StrategyType>(
            vault_id,
            witness
        )
    }

    #[test_only]
    public fun test_unlock_vault<StrategyType: drop>(
        vault_cap: VaultCapability,
        stop_handle: VaultCapLock<StrategyType>,
    ) acquires ManagerAccount {
        unlock_vault<StrategyType>(
            vault_cap,
            stop_handle,
        )
    }

    #[test_only]
    public fun test_approve_strategy<StrategyType: drop, StrategyCoin>(
        vault_manager: &signer,
        vault_id: u64,
        debt_ratio: u64,
        witness: StrategyType,
    ) acquires ManagerAccount {
        approve_strategy<StrategyType, StrategyCoin>(
            vault_manager,
            vault_id,
            debt_ratio,
            &witness
        );
    }

    #[test_only]
    public fun test_update_strategy_debt_ratio<StrategyType: drop>(
        vault_manager: &signer,
        vault_id: u64,
        debt_ratio: u64,
        witness: StrategyType
    ) acquires ManagerAccount {
        update_strategy_debt_ratio<StrategyType>(
            vault_manager,
            vault_id,
            debt_ratio,
            &witness
        );
    }

    #[test_only]
    public fun balance<CoinType>(manager_addr: address, vault_id: u64) : u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global_mut<ManagerAccount>(manager_addr);
        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::balance<CoinType>(vault_cap)
    }

    #[test_only]
    public fun test_assert_manager_initialized() {
        assert_manager_initialized();
    }

    #[test_only]
    public fun test_assert_vault_cap_and_stop_handle_match<StrategyType: drop>(
        vault_cap: &VaultCapability,
        stop_handle: &VaultCapLock<StrategyType>,
    ) {
        assert_vault_cap_and_stop_handle_match<StrategyType>(vault_cap, stop_handle);
    }

    #[test_only]
    public fun test_get_vault_address_by_id(vault_id: u64) : address acquires ManagerAccount {
        get_vault_address_by_id(vault_id)
    }
}