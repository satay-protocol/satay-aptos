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

    struct ManagerAccount has key {
        next_vault_id: u64,
        vaults: Table<u64, VaultInfo>,
    }

    struct VaultInfo has store {
        vault_cap: VaultCapability,
        strategy_type: Option<TypeInfo>,
    }

    public fun initialize(manager: &signer) {
        move_to(manager, ManagerAccount { vaults: table::new(), next_vault_id: 0 });
    }

    public fun new_vault<BaseCoin>(manager: &signer, seed: vector<u8>) acquires ManagerAccount {
        let manager_addr = signer::address_of(manager);
        assert_manager_initialized(manager_addr);
        let account = borrow_global_mut<ManagerAccount>(manager_addr);

        let vault_id = account.next_vault_id;
        account.next_vault_id = account.next_vault_id + 1;

        let vault_cap = vault::new<BaseCoin>(manager, seed);
        table::add(
            &mut account.vaults,
            vault_id,
            VaultInfo {
                vault_cap,
                strategy_type: option::none()
            }
        );
    }

    public entry fun deposit<BaseCoin>(
        user: &signer,
        manager_addr: address,
        vault_id: u64,
        amount: u64
    ) acquires ManagerAccount {
        assert_manager_initialized(manager_addr);
        let account = borrow_global_mut<ManagerAccount>(manager_addr);

        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        let vault_cap = &vault_info.vault_cap;

        let base_coin = coin::withdraw<BaseCoin>(user, amount);
        vault::deposit_as_user(vault_cap, signer::address_of(user), base_coin);
    }

    public entry fun withdraw<BaseCoin>(
        user: &signer,
        manager_addr: address,
        vault_id: u64,
        amount: u64
    ) acquires ManagerAccount {
        assert_manager_initialized(manager_addr);
        let account = borrow_global_mut<ManagerAccount>(manager_addr);

        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);

        let vault_cap = &vault_info.vault_cap;
        let user_addr = signer::address_of(user);
        let base_coin = vault::withdraw_as_user<BaseCoin>(vault_cap, user_addr, amount);
        coin::deposit(user_addr, base_coin);
    }

    public fun approve_strategy<Strategy>(manager: &signer, vault_id: u64) acquires ManagerAccount {
        let manager_addr = signer::address_of(manager);
        assert_manager_initialized(manager_addr);
        let account = borrow_global_mut<ManagerAccount>(manager_addr);

        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        vault_info.strategy_type = option::some(type_info::type_of<Strategy>());
    }

    public fun get_vault_cap<Strategy>(
        manager_addr: address,
        vault_id: u64,
        _witness: Strategy
    ): (VaultCapability, ) acquires ManagerAccount {
        assert_manager_initialized(manager_addr);
        let account = borrow_global_mut<ManagerAccount>(manager_addr);

        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        assert!(
            vault_info.strategy_type == option::some(type_info::type_of<Strategy>()),
            ERR_STRATEGY
        );

        &vault_info.vault_cap
        // (vault_info.vault_cap, VaultCapLoan { manager_addr, vault_id })
    }

    // public fun put_vault_cap(vault_cap: VaultCapability, vault_cap_loan: VaultCapLoan) {
    // }

    fun assert_manager_initialized(manager_addr: address) {
        assert!(exists<ManagerAccount>(manager_addr), ERR_MANAGER);
    }
}















