/// establishes access control for the strategy keeper role of strategies approved on a vault
module satay::keeper_config {
    use std::signer;

    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;

    use satay::vault_config;

    friend satay::vault;

    // error codes

    /// when the keeper config does not exist
    const ERR_CONFIG_DOES_NOT_EXIST: u64 = 1;

    /// when the account calling accept_keeper is not the new keeper
    const ERR_NOT_NEW_KEEPER: u64 = 2;

    /// when the signer is not the keeper
    const ERR_NOT_KEEPER: u64 = 3;

    /// holds the keeper information for each StrategyType, stored in vault account
    /// @field keeper_address - the address of the current keeper
    /// @field new_keeper_address - the address of the new keeper, set by set_keeper
    /// @field keeper_change_events - event handle for KeeperChangeEvent
    struct KeeperConfig<phantom BaseCoin, phantom StrategyType: drop> has key {
        keeper_address: address,
        new_keeper_address: address,
        keeper_change_events: EventHandle<KeeperChangeEvent>,
    }

    /// emitted when a new keeper accepts the role
    /// @field new_keeper_address - the address of the new keeper
    struct KeeperChangeEvent has drop, store {
        new_keeper_address: address,
    }

    /// initializes a KeeperConfig resource in the vault_account, called by vault::approve_strategy
    /// @param vault_account - the transaction signer; the resource account for the vault
    /// @param _witness - proves the origin of the call
    public(friend) fun initialize<BaseCoin, StrategyType: drop>(vault_account: &signer, _witness: &StrategyType) {
        move_to(vault_account, KeeperConfig<BaseCoin, StrategyType> {
            keeper_address: vault_config::get_vault_manager_address(signer::address_of(vault_account)),
            new_keeper_address: @0x0,
            keeper_change_events: account::new_event_handle<KeeperChangeEvent>(vault_account),
        });
    }

    /// set new_keeper_address on the KeeperConfig resource
    /// @param vault_manager - the transaction signer; must have the vault_manager role for vault_address
    /// @param vault_address - the address of the vault holding KeeperConfig<StrategyType>
    /// @param new_keeper_address - the address to offer keeper capability to
    public entry fun set_keeper<BaseCoin, StrategyType: drop>(
        vault_manager: &signer,
        vault_address: address,
        new_keeper_address: address
    )
    acquires KeeperConfig {
        assert_strategy_config_exists<BaseCoin, StrategyType>(vault_address);
        vault_config::assert_vault_manager(vault_manager, vault_address);
        let strategy_config = borrow_global_mut<KeeperConfig<BaseCoin, StrategyType>>(vault_address);
        strategy_config.new_keeper_address = new_keeper_address;
    }

    /// accept the keeper role for new_keeper_address
    /// @param new_keeper - the transaction signer; address of the signer must equal new_keeper_address
    /// @param vault_address - the address of the vault holding StrategyCofig<StrategyType>
    public entry fun accept_keeper<BaseCoin, StrategyType: drop>(new_keeper: &signer, vault_address: address)
    acquires KeeperConfig {
        assert_strategy_config_exists<BaseCoin, StrategyType>(vault_address);
        let vault_config = borrow_global_mut<KeeperConfig<BaseCoin, StrategyType>>(vault_address);
        assert!(signer::address_of(new_keeper) == vault_config.new_keeper_address, ERR_NOT_NEW_KEEPER);
        event::emit_event(&mut vault_config.keeper_change_events, KeeperChangeEvent {
            new_keeper_address: vault_config.new_keeper_address,
        });
        vault_config.keeper_address = vault_config.new_keeper_address;
        vault_config.new_keeper_address = @0x0;
    }

    #[view]
    /// returns the keeper address for StrategyType on vault_address
    /// @param vault_address - the address of the vault holding KeeperConfig<StrategyType>
    public fun get_keeper_address<BaseCoin, StrategyType: drop>(vault_address: address): address
    acquires KeeperConfig {
        assert_strategy_config_exists<BaseCoin, StrategyType>(vault_address);
        let config = borrow_global<KeeperConfig<BaseCoin, StrategyType>>(vault_address);
        config.keeper_address
    }

    /// asserts that the signer has the keeper role for strategy type on vault_address
    /// @param keeper - the transaction signer; must have the keeper role for KeeperConfig<StrategyType> on vault_address
    /// @param vault_address - the address of the vault holding KeeperConfig<StrategyType>
    public fun assert_keeper<BaseCoin, StrategyType: drop>(keeper: &signer, vault_address: address)
    acquires KeeperConfig {
        assert_strategy_config_exists<BaseCoin, StrategyType>(vault_address);
        let config = borrow_global<KeeperConfig<BaseCoin, StrategyType>>(vault_address);
        assert!(signer::address_of(keeper) == config.keeper_address, ERR_NOT_KEEPER);
    }

    /// asserts that KeeperConfig<StrategyType> exists on vault_address
    /// @param vault_address - the address of the vault to check for KeeperConfig<StrategyType>
    fun assert_strategy_config_exists<BaseCoin, StrategyType: drop>(vault_address: address) {
        assert!(exists<KeeperConfig<BaseCoin, StrategyType>>(vault_address), ERR_CONFIG_DOES_NOT_EXIST);
    }
}
