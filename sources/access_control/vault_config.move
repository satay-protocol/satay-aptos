module satay::vault_config {

    use std::signer;

    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;
    use satay::global_config;

    const ERR_CONFIG_DOES_NOT_EXIST: u64 = 1;
    const ERR_NOT_NEW_MANAGER: u64 = 2;
    const ERR_NOT_MANAGER: u64 = 3;

    friend satay::vault;

    struct VaultConfig has key {
        vault_manager_address: address,
        new_vault_manager_address: address,
        vault_manager_change_events: EventHandle<VaultManagerChangeEvent>,
    }

    struct VaultManagerChangeEvent has drop, store {
        new_vault_manager_address: address,
    }

    public(friend) fun initialize (
        vault_account: &signer
    ) {
        move_to(vault_account, VaultConfig {
            vault_manager_address: global_config::get_governance_address(),
            new_vault_manager_address: @0x0,
            vault_manager_change_events: account::new_event_handle<VaultManagerChangeEvent>(vault_account),
        });
    }

    public entry fun set_vault_manager(
        governance: &signer,
        vault_address: address,
        new_vault_manager_address: address,
    ) acquires VaultConfig {
        assert_vault_config_exists(vault_address);
        global_config::assert_governance(governance);
        let vault_config = borrow_global_mut<VaultConfig>(vault_address);
        vault_config.new_vault_manager_address = new_vault_manager_address;
    }

    public entry fun accept_vault_manager(
        vault_manager: &signer,
        vault_address: address,
    ) acquires VaultConfig {
        assert_vault_config_exists(vault_address);
        let vault_config = borrow_global_mut<VaultConfig>(vault_address);
        assert!(signer::address_of(vault_manager) == vault_config.new_vault_manager_address, ERR_NOT_NEW_MANAGER);
        event::emit_event(&mut vault_config.vault_manager_change_events, VaultManagerChangeEvent {
            new_vault_manager_address: vault_config.new_vault_manager_address,
        });
        vault_config.vault_manager_address = vault_config.new_vault_manager_address;
        vault_config.new_vault_manager_address = @0x0;
    }

    public fun get_vault_manager_address(
        vault_address: address,
    ): address acquires VaultConfig {
        assert_vault_config_exists(vault_address);
        let config = borrow_global<VaultConfig>(vault_address);
        config.vault_manager_address
    }

    public fun assert_vault_manager(
        vault_manager: &signer,
        vault_address: address,
    ) acquires VaultConfig {
        assert_vault_config_exists(vault_address);
        let config = borrow_global<VaultConfig>(vault_address);
        assert!(signer::address_of(vault_manager) == config.vault_manager_address, ERR_NOT_MANAGER);
    }

    fun assert_vault_config_exists(
        vault_address: address
    ) {
        assert!(exists<VaultConfig>(vault_address), ERR_CONFIG_DOES_NOT_EXIST);
    }

}
