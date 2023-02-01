/// establishes access control for the vault manager role of vaults
module satay::vault_config {

    use std::signer;

    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;

    use satay::global_config;

    friend satay::vault;

    // Error codes

    /// when the vault config does not exist
    const ERR_CONFIG_DOES_NOT_EXIST: u64 = 1;
    /// when the signer is not the new vault manager
    const ERR_NOT_NEW_MANAGER: u64 = 2;
    /// when the signer is not the vault manager
    const ERR_NOT_MANAGER: u64 = 3;

    /// holds the vault manager information for each vault; stored in the the vault's resource account
    /// @field vault_manager_address - the current vault manager address
    /// @field new_vault_manager_address - the new vault manager address
    /// @field vault_manager_change_events - the event handle for vault manager change events
    struct VaultConfig has key {
        vault_manager_address: address,
        new_vault_manager_address: address,
        vault_manager_change_events: EventHandle<VaultManagerChangeEvent>,
    }

    /// emitted when the vault manager is changed
    /// @field new_vault_manager_address - the new vault manager address
    struct VaultManagerChangeEvent has drop, store {
        new_vault_manager_address: address,
    }

    /// initializes the vault config for the vault
    /// @param vault_account - the transaction signer; the vault's resource account
    public(friend) fun initialize (vault_account: &signer) {
        move_to(vault_account, VaultConfig {
            vault_manager_address: global_config::get_governance_address(),
            new_vault_manager_address: @0x0,
            vault_manager_change_events: account::new_event_handle<VaultManagerChangeEvent>(vault_account),
        });
    }

    /// sets the new vault manager address
    /// @param governance - the transaction signer; must have governance role in the global_config module
    /// @param vault_address - the vault's resource account address
    /// @param new_vault_manager_address - the new vault manager address
    public entry fun set_vault_manager(governance: &signer, vault_address: address, new_vault_manager_address: address)
    acquires VaultConfig {
        assert_vault_config_exists(vault_address);
        global_config::assert_governance(governance);
        let vault_config = borrow_global_mut<VaultConfig>(vault_address);
        vault_config.new_vault_manager_address = new_vault_manager_address;
    }

    /// accepts the new vault manager address
    /// @param vault_manager - the transaction signer; must be the new vault manager address
    /// @param vault_address - the vault's resource account address
    public entry fun accept_vault_manager(vault_manager: &signer, vault_address: address)
    acquires VaultConfig {
        assert_vault_config_exists(vault_address);
        let vault_config = borrow_global_mut<VaultConfig>(vault_address);
        assert!(signer::address_of(vault_manager) == vault_config.new_vault_manager_address, ERR_NOT_NEW_MANAGER);
        event::emit_event(&mut vault_config.vault_manager_change_events, VaultManagerChangeEvent {
            new_vault_manager_address: vault_config.new_vault_manager_address,
        });
        vault_config.vault_manager_address = vault_config.new_vault_manager_address;
        vault_config.new_vault_manager_address = @0x0;
    }

    /// gets the vault manager address
    /// @param vault_address - the vault's resource account address
    public fun get_vault_manager_address(vault_address: address): address
    acquires VaultConfig {
        assert_vault_config_exists(vault_address);
        let config = borrow_global<VaultConfig>(vault_address);
        config.vault_manager_address
    }

    /// asserts that the signer is the vault manager for the vault whose address equals vault_address
    /// @param vault_manager - the transaction signer; must be the vault manager
    /// @param vault_address - the vault's resource account address
    public fun assert_vault_manager(vault_manager: &signer, vault_address: address)
    acquires VaultConfig {
        assert_vault_config_exists(vault_address);
        let config = borrow_global<VaultConfig>(vault_address);
        assert!(signer::address_of(vault_manager) == config.vault_manager_address, ERR_NOT_MANAGER);
    }

    /// asserts that the vault config exists for the vault whose address equals vault_address
    /// @param vault_address - the vault's resource account address
    fun assert_vault_config_exists(vault_address: address) {
        assert!(exists<VaultConfig>(vault_address), ERR_CONFIG_DOES_NOT_EXIST);
    }
}
