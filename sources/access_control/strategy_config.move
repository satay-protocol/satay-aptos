/// establishes access control for the strategy keeper role of strategies approved on a vault
module satay::strategy_config {
    use std::signer;

    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;

    friend satay::strategy_coin;

    // error codes

    /// when the strategy coin config does not exist
    const ERR_CONFIG_DOES_NOT_EXIST: u64 = 1;

    /// when the account calling accept_strategy_manager is not the new strategy coin manager
    const ERR_NOT_NEW_MANAGER: u64 = 2;

    /// when the signer is not the strategy coin manager
    const ERR_NOT_MANAGER: u64 = 3;

    /// holds the strategy manager information for each (BaseCoin, StrategyType), stored in strategy account
    /// @field strategy_manager_address - the address of the current strategy manager
    /// @field new_strategy_manager_address - the address of the new strategy manager
    /// @field strategy_manager_change_events - the event handle for StrategyManagerChangeEvent
    struct StrategyConfig<phantom BaseCoin, phantom StrategyType: drop> has key {
        strategy_manager_address: address,
        new_strategy_manager_address: address,
        strategy_manager_change_events: EventHandle<StrategyManagerChangeEvent>,
    }

    /// emitted when a new strategy manager accepts the role
    /// @field new_strategy_manager_address - the address of the new strategy coin manager
    struct StrategyManagerChangeEvent has drop, store {
        new_strategy_manager_address: address,
    }

    /// initializes a StrategyConfig resource in the strategy account, called by strategy_coin::initialize
    /// @param strategy_account - the transaction signer; the resource account for the strategy
    /// @param strategy_manager_address - the address of the strategy manager
    /// @param _witness - proves the origin of the call
    public(friend) fun initialize<BaseCoin, StrategyType: drop>(
        strategy_account: &signer,
        strategy_manager_address: address,
        _witness: &StrategyType
    ) {
        move_to(strategy_account, StrategyConfig<BaseCoin, StrategyType> {
            strategy_manager_address,
            new_strategy_manager_address: @0x0,
            strategy_manager_change_events: account::new_event_handle<StrategyManagerChangeEvent>(strategy_account)
        });
    }

    /// sets the new strategy coin manager address
    /// @param strategy_manager - the transaction signer; must have the strategy manager role for the strategy
    /// @param strategy_address - the address of the strategy account
    /// @param new_strategy_manager_address - the address of the new strategy manager
    public entry fun set_strategy_manager<BaseCoin, StrategyType: drop>(
        strategy_manager: &signer,
        strategy_address: address,
        new_strategy_manager_address: address
    )
    acquires StrategyConfig {
        assert_strategy_config_exists<BaseCoin, StrategyType>(strategy_address);
        assert_strategy_manager<BaseCoin, StrategyType>(strategy_manager, strategy_address);
        let strategy_config = borrow_global_mut<StrategyConfig<BaseCoin, StrategyType>>(strategy_address);
        strategy_config.new_strategy_manager_address = new_strategy_manager_address;
    }

    /// accepts the new strategy manager role for the strategy
    /// @param new_strategy_manager - the transaction signer; must be the new strategy manager
    /// @param strategy_address - the address of the strategy
    public entry fun accept_strategy_manager<BaseCoin, StrategyType: drop>(
        new_strategy_manager: &signer,
        strategy_address: address
    )
    acquires StrategyConfig {
        assert_strategy_config_exists<BaseCoin, StrategyType>(strategy_address);
        let strategy_config = borrow_global_mut<StrategyConfig<BaseCoin, StrategyType>>(strategy_address);
        let new_strategy_manager_address = signer::address_of(new_strategy_manager);
        assert!(new_strategy_manager_address == strategy_config.new_strategy_manager_address, ERR_NOT_MANAGER);
        event::emit_event(&mut strategy_config.strategy_manager_change_events, StrategyManagerChangeEvent {
            new_strategy_manager_address
        });
        strategy_config.strategy_manager_address = strategy_config.new_strategy_manager_address;
        strategy_config.new_strategy_manager_address = @0x0;
    }

    #[view]
    /// returns the strategy manager address for the strategy
    /// @param strategy_address - the address of the strategy
    public fun get_strategy_manager_address<BaseCoin, StrategyType: drop>(strategy_address: address): address
    acquires StrategyConfig {
        assert_strategy_config_exists<BaseCoin, StrategyType>(strategy_address);
        let config = borrow_global<StrategyConfig<BaseCoin, StrategyType>>(strategy_address);
        config.strategy_manager_address
    }

    /// asserts that the signer has the strategy manager role for the strategy
    /// @param strategy_manager - the transaction signer; must have the strategy manager role
    /// @param strategy_address - the address of the strategy
    public fun assert_strategy_manager<BaseCoin, StrategyType: drop>(
        strategy_manager: &signer,
        strategy_address: address
    )
    acquires StrategyConfig {
        assert_strategy_config_exists<BaseCoin, StrategyType>(strategy_address);
        let config = borrow_global<StrategyConfig<BaseCoin, StrategyType>>(strategy_address);
        assert!(signer::address_of(strategy_manager) == config.strategy_manager_address, ERR_NOT_MANAGER);
    }

    /// asserts that StrategyCoinConfig<BaseCoin, StrategyType> exists on strategy_address
    /// @param strategy_address - the address of the strategy
    fun assert_strategy_config_exists<BaseCoin, StrategyType: drop>(strategy_address: address) {
        assert!(exists<StrategyConfig<BaseCoin, StrategyType>>(strategy_address), ERR_CONFIG_DOES_NOT_EXIST);
    }
}
