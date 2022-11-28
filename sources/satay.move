module satay::satay {
    use std::option::{Self, Option};
    use std::signer;

    use aptos_framework::coin;
    use aptos_std::table::{Self, Table};

    use satay::global_config;
    use satay::vault::{Self, VaultCapability};

    friend satay::base_strategy;

    const ERR_MANAGER: u64 = 1;
    const ERR_STRATEGY: u64 = 2;
    const ERR_COIN: u64 = 3;
    const ERR_VAULT_CAP: u64 = 4;
    const ERR_VAULT_NO_STRATEGY: u64 = 6;

    struct ManagerAccount has key {
        next_vault_id: u64,
        vaults: Table<u64, VaultInfo>,
    }

    struct VaultInfo has store {
        // VaultCapability of the vault.
        // `Option` here is required to allow lending the capability object to the strategy.
        vault_cap: Option<VaultCapability>,
    }

    // returned by lock_vault to ensure a subsequent call to unlock_vault
    struct VaultCapLock<StrategyType: drop> {
        vault_id: u64,
        strategy_type: StrategyType
    }

    // called by managers

    // create manager account and store in sender's account
    public entry fun initialize(
        satay: &signer
    ) {
        // asserts that signer::address_of(satay) == @satay
        global_config::initialize(satay);
        move_to(satay, ManagerAccount { vaults: table::new(), next_vault_id: 0 });
    }

    // create new vault for BaseCoin
    public entry fun new_vault<BaseCoin>(
        governance: &signer,
        seed: vector<u8>,
        management_fee: u64,
        performance_fee: u64
    ) acquires ManagerAccount {
        global_config::assert_governance(governance);

        assert_manager_initialized();
        let account = borrow_global_mut<ManagerAccount>(@satay);

        global_config::initialize_vault<BaseCoin>(governance);

        // get vault id and update next id
        let vault_id = account.next_vault_id;
        account.next_vault_id = account.next_vault_id + 1;

        // create vault and add to manager vaults table
        let vault_cap = vault::new<BaseCoin>(governance, seed, vault_id, management_fee, performance_fee);
        table::add(
            &mut account.vaults,
            vault_id,
            VaultInfo {
                vault_cap: option::some(vault_cap),
            }
        );
    }

    public entry fun update_vault_fee(
        governance: &signer,
        vault_id: u64,
        management_fee: u64,
        performance_fee: u64
    ) acquires ManagerAccount {
        global_config::assert_governance(governance);
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);

        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);

        vault::update_fee(vault_cap, management_fee, performance_fee);
    }

    // called by users

    // user deposits amount of BaseCoin into vault_id of manager_addr
    public entry fun deposit<BaseCoin>(
        user: &signer,
        vault_id: u64,
        amount: u64
    ) acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);

        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);

        let base_coin = coin::withdraw<BaseCoin>(user, amount);

        vault::deposit_as_user(user, vault_cap, base_coin);
    }

    // user withdraws amount of BaseCoin from vault_id of manager_addr
    public entry fun withdraw<BaseCoin>(
        user: &signer,
        vault_id: u64,
        amount: u64
    ) acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);

        let vault_info = table::borrow(&account.vaults, vault_id);

        let vault_cap = option::borrow(&vault_info.vault_cap);
        let user_addr = signer::address_of(user);
        let base_coin = vault::withdraw_as_user<BaseCoin>(user, vault_cap, amount);
        coin::deposit(user_addr, base_coin);
    }

    // called by strategies

    // allows Strategy to get VaultCapability of vault_id of manager_addr
    public(friend) fun approve_strategy<StrategyType: drop, StrategyCoin>(
        governance: &signer,
        vault_id: u64,
        debt_ratio: u64,
        _witness: &StrategyType
    ) acquires ManagerAccount {
        global_config::assert_governance(governance);
        global_config::initialize_strategy<StrategyType>(governance);

        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);

        let vault_info = table::borrow(&account.vaults, vault_id);
        vault::approve_strategy<StrategyType, StrategyCoin>(
            option::borrow(&vault_info.vault_cap),
            debt_ratio
        );
    }

    // get VaultCapability of vault_id of manager_addr
    // StrategyType must be approved
    public(friend) fun lock_vault<StrategyType: drop>(
        vault_id: u64,
        witness: StrategyType
    ): (VaultCapability, VaultCapLock<StrategyType>) acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global_mut<ManagerAccount>(@satay);

        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);

        // assert that strategy is approved for vault
        assert!(
            vault::has_strategy<StrategyType>(option::borrow(&vault_info.vault_cap)),
            ERR_STRATEGY
        );

        let vault_cap = option::extract(&mut vault_info.vault_cap);
        let stop_handle = VaultCapLock {
            vault_id,
            strategy_type: witness,
        };
        (vault_cap, stop_handle)
    }

    // returns vault_cap to vault after strategy has completed operation
    public(friend) fun unlock_vault<StrategyType: drop>(
        vault_capability: VaultCapability,
        stop_handle: VaultCapLock<StrategyType>
    ) acquires ManagerAccount {
        // assert that correct VaultCapLock for VaultCapability is passed
        assert_vault_cap_and_stop_handle_match(&vault_capability, &stop_handle);

        let VaultCapLock<StrategyType> {
            vault_id,
            strategy_type: _
        } = stop_handle;

        let account = borrow_global_mut<ManagerAccount>(@satay);
        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        assert!(
            vault::has_strategy<StrategyType>(&vault_capability),
            ERR_STRATEGY
        );
        option::fill(&mut vault_info.vault_cap, vault_capability);
    }

    // update the strategy debt ratio
    public(friend) fun update_strategy_debt_ratio<StrategyType: drop>(
        vault_id: u64,
        debt_ratio: u64,
        _witness: StrategyType
    ): u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);

        let vault_info = table::borrow(&account.vaults, vault_id);
        assert!(vault::has_strategy<StrategyType>(option::borrow(&vault_info.vault_cap)), ERR_VAULT_NO_STRATEGY);

        vault::update_strategy_debt_ratio<StrategyType>(
            option::borrow(&vault_info.vault_cap),
            debt_ratio
        )
    }

    // update strategy credit threshold
    public(friend) fun update_strategy_credit_threshold<StrategyType: drop>(
        vault_id: u64,
        credit_threshold: u64,
        _witness: StrategyType
    ) acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        
        let vault_info = table::borrow(&account.vaults, vault_id);
        assert!(vault::has_strategy<StrategyType>(option::borrow(&vault_info.vault_cap)), ERR_VAULT_NO_STRATEGY);
        vault::update_strategy_credit_threshold<StrategyType>(option::borrow(&vault_info.vault_cap), credit_threshold);
    }

    // set strategy force harvest trigger once
    public(friend) fun set_strategy_force_harvest_trigger_once<StrategyType: drop>(
        vault_id: u64,
        _witness: StrategyType
    ) acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        assert!(vault::has_strategy<StrategyType>(option::borrow(&vault_info.vault_cap)), ERR_VAULT_NO_STRATEGY);
        vault::set_strategy_force_harvest_trigger_once<StrategyType>(option::borrow(&vault_info.vault_cap));
    }

    // update strategy max report delay
    public(friend) fun update_strategy_max_report_delay<StrategyType: drop>(
        vault_id: u64,
        max_report_delay: u64,
        _witness: StrategyType
    ) acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);

        let vault_info = table::borrow(&account.vaults, vault_id);
        assert!(vault::has_strategy<StrategyType>(option::borrow(&vault_info.vault_cap)), ERR_VAULT_NO_STRATEGY);
        vault::update_strategy_max_report_delay<StrategyType>(option::borrow(&vault_info.vault_cap), max_report_delay);
    }

    // getter functions

    public fun get_next_vault_id() : u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        account.next_vault_id
    }

    // checks if vault_id for manager has StrategyType approved
    public fun has_strategy<StrategyType: drop>(
        vault_id: u64,
    ) : bool acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        vault::has_strategy<StrategyType>(option::borrow(&vault_info.vault_cap))
    }

    // get vault address for vault_id
    public fun get_vault_address_by_id(
        vault_id: u64
    ): address acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::get_vault_addr(vault_cap)
    }

    // get total assets for (manager_addr, vault_id)
    public fun get_vault_total_asset<CoinType>(vault_id: u64) : u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::total_assets<CoinType>(vault_cap)
    }

    public fun get_strategy_witness<StrategyType: drop>(
        vault_cap_lock: &VaultCapLock<StrategyType>
    ): &StrategyType {
        &vault_cap_lock.strategy_type
    }

    public fun get_vault_id<StrategyType: drop>(
        vault_cap_lock: &VaultCapLock<StrategyType>
    ): u64 {
        vault_cap_lock.vault_id
    }

    fun assert_manager_initialized() {
        assert!(exists<ManagerAccount>(@satay), ERR_MANAGER);
    }

    fun assert_vault_cap_and_stop_handle_match<StrategyType: drop>(
        vault_cap: &VaultCapability,
        stop_handle: &VaultCapLock<StrategyType>,
    ) {
        let vault_id = stop_handle.vault_id;
        assert!(
            vault::vault_cap_has_id(vault_cap, vault_id),
            ERR_VAULT_CAP
        );
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
        witness: StrategyType,
    ): (VaultCapability, VaultCapLock<StrategyType>) acquires ManagerAccount {
        lock_vault<StrategyType>(
            vault_id,
            witness,
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
        governance: &signer,
        vault_id: u64,
        debt_ratio: u64,
        witness: StrategyType,
    ) acquires ManagerAccount {
        approve_strategy<StrategyType, StrategyCoin>(
            governance,
            vault_id,
            debt_ratio,
            &witness
        );
    }

    #[test_only]
    public fun test_update_strategy_debt_ratio<StrategyType: drop>(
        vault_id: u64,
        debt_ratio: u64,
        witness: StrategyType
    ) acquires ManagerAccount {
        update_strategy_debt_ratio<StrategyType>(
            vault_id,
            debt_ratio,
            witness
        );
    }

    #[test_only]
    public fun test_update_strategy_credit_threshold<StrategyType: drop>(
        vault_id: u64,
        credit_threshold: u64,
        witness: StrategyType
    ) acquires ManagerAccount {
        update_strategy_credit_threshold<StrategyType>(
            vault_id,
            credit_threshold,
            witness
        );
    }

    #[test_only]
    public fun test_set_strategy_force_harvest_trigger_once<StrategyType: drop>(
        vault_id: u64,
        witness: StrategyType
    ) acquires ManagerAccount {
        set_strategy_force_harvest_trigger_once<StrategyType>(
            vault_id,
            witness
        );
    }

    #[test_only]
    public fun test_update_strategy_max_report_delay<StrategyType: drop>(
        vault_id: u64,
        max_report_delay: u64,
        witness: StrategyType
    ) acquires ManagerAccount {
        update_strategy_max_report_delay<StrategyType>(
            vault_id,
            max_report_delay,
            witness
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