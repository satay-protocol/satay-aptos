module satay::satay {
    use std::option::{Self, Option};
    use std::signer;

    use aptos_framework::coin;
    use aptos_std::table::{Self, Table};
    use aptos_std::type_info::{Self, TypeInfo};

    use satay::vault::{Self, VaultCapability};

    const ERR_MANAGER: u64 = 1;
    const ERR_STRATEGY: u64 = 2;
    const ERR_COIN: u64 = 3;
    const ERR_VAULT_CAP: u64 = 4;

    struct ManagerAccount has key {
        next_vault_id: u64,
        vaults: Table<u64, VaultInfo>,
    }

    struct VaultInfo has store {
        /// VaultCapability of the vault.
        /// `Option` here is required to allow "lending" the capability object to the strategy.
        vault_cap: Option<VaultCapability>,

        /// Currently approved strategy
        strategy_type: Option<TypeInfo>,
    }

    // create manager account and give it to the sender
    public entry fun initialize(manager: &signer) {
        move_to(manager, ManagerAccount { vaults: table::new(), next_vault_id: 0 });
    }

    /// Manager creates a new `Vault` as a resource account with it's own `CoinStorage` resources.
    /// Assigns a new `vault_id` to it.
    /// Later, vaults are identified as a pair of `(manager_address, vault_id)`.
    public entry fun new_vault<BaseCoin>(manager: &signer, seed: vector<u8>) acquires ManagerAccount {
        let manager_addr = signer::address_of(manager);
        assert_manager_initialized(manager_addr);
        let account = borrow_global_mut<ManagerAccount>(manager_addr);

        let vault_id = account.next_vault_id;
        account.next_vault_id = account.next_vault_id + 1;

        let vault_cap = vault::new<BaseCoin>(manager, seed, vault_id);
        table::add(
            &mut account.vaults,
            vault_id,
            VaultInfo {
                vault_cap: option::some(vault_cap),
                strategy_type: option::none()
            }
        );
    }

    // user deposits amount of BaseCoin into vault_id of manager_addr
    public entry fun deposit<BaseCoin>(
        user: &signer,
        manager_addr: address,
        vault_id: u64,
        amount: u64
    ) acquires ManagerAccount {
        assert_manager_initialized(manager_addr);
        let account = borrow_global_mut<ManagerAccount>(manager_addr);

        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);

        let base_coin = coin::withdraw<BaseCoin>(user, amount);

        vault::deposit_as_user(user, vault_cap, base_coin);
    }

    // user withdraws amount of BaseCoin from vault_id of manager_addr
    public entry fun withdraw<BaseCoin>(
        user: &signer,
        manager_addr: address,
        vault_id: u64,
        amount: u64
    ) acquires ManagerAccount {
        assert_manager_initialized(manager_addr);
        let account = borrow_global_mut<ManagerAccount>(manager_addr);

        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);

        let vault_cap = option::borrow(&vault_info.vault_cap);
        let user_addr = signer::address_of(user);
        let base_coin = vault::withdraw_as_user<BaseCoin>(user, vault_cap, amount);
        coin::deposit(user_addr, base_coin);
    }

    // Allows this strategy to access the vault. To be called in the governance.
    public entry fun approve_strategy<Strategy>(manager: &signer, vault_id: u64) acquires ManagerAccount {
        let manager_addr = signer::address_of(manager);
        assert_manager_initialized(manager_addr);
        let account = borrow_global_mut<ManagerAccount>(manager_addr);

        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        vault_info.strategy_type = option::some(type_info::type_of<Strategy>());
    }

    struct VaultCapLock { vault_id: u64 }

    public fun lock_vault<Strategy: drop>(
        manager_addr: address,
        vault_id: u64,
        _witness: Strategy
    ): (VaultCapability, VaultCapLock) acquires ManagerAccount {
        assert_manager_initialized(manager_addr);
        let account = borrow_global_mut<ManagerAccount>(manager_addr);

        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        assert!(
            vault_info.strategy_type == option::some(type_info::type_of<Strategy>()),
            ERR_STRATEGY
        );

        let vault_cap = option::extract(&mut vault_info.vault_cap);
        (vault_cap, VaultCapLock { vault_id })
    }

    public fun unlock_vault<Strategy>(
        manager_addr: address,
        vault_capability: VaultCapability,
        stop_handle: VaultCapLock
    ) acquires ManagerAccount {
        let VaultCapLock { vault_id } = stop_handle;
        // TODO: think about how to prevent wrong VaultCapability passed here by using this VaultCapLock fields
        assert!(
            vault::vault_cap_has_id(&vault_capability, vault_id),
            ERR_VAULT_CAP
        );

        let account = borrow_global_mut<ManagerAccount>(manager_addr);

        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        assert!(
            vault_info.strategy_type == option::some(type_info::type_of<Strategy>()),
            ERR_STRATEGY
        );
        option::fill(&mut vault_info.vault_cap, vault_capability);
    }

    fun assert_manager_initialized(manager_addr: address) {
        assert!(exists<ManagerAccount>(manager_addr), ERR_MANAGER);
    }

    public fun get_next_vault_id(manager_addr: address) : u64 acquires ManagerAccount {
        assert_manager_initialized(manager_addr);
        let account = borrow_global_mut<ManagerAccount>(manager_addr);
        account.next_vault_id
    }

    #[test_only]
    public fun balance<CoinType>(manager_addr: address, vault_id: u64) : u64 acquires ManagerAccount {
        assert_manager_initialized(manager_addr);
        let account = borrow_global_mut<ManagerAccount>(manager_addr);
        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::balance<CoinType>(vault_cap)
    }
}















