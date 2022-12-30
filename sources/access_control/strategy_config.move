module satay::strategy_config {
    use std::signer;

    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;

    use satay::vault_config;

    friend satay::vault;

    const ERR_CONFIG_DOES_NOT_EXIST: u64 = 1;
    const ERR_NOT_NEW_KEEPER: u64 = 2;
    const ERR_NOT_KEEPER: u64 = 3;

    struct StrategyConfig<phantom StrategyType> has key {
        keeper_address: address,
        new_keeper_address: address,
        keeper_change_events: EventHandle<KeeperChangeEvent>,
    }

    struct KeeperChangeEvent has drop, store {
        new_keeper_address: address,
    }

    public(friend) fun initialize<StrategyType: drop>(
        vault_account: &signer,
        _witness: &StrategyType,
    ) {
        move_to(vault_account, StrategyConfig<StrategyType> {
            keeper_address: vault_config::get_vault_manager_address(signer::address_of(vault_account)),
            new_keeper_address: @0x0,
            keeper_change_events: account::new_event_handle<KeeperChangeEvent>(vault_account),
        });
    }

    public entry fun set_keeper<StrategyType: drop>(
        vault_manager: &signer,
        vault_address: address,
        new_keeper_address: address,
    ) acquires StrategyConfig {
        assert_strategy_config_exists<StrategyType>(vault_address);
        vault_config::assert_vault_manager(vault_manager, vault_address);
        let strategy_config = borrow_global_mut<StrategyConfig<StrategyType>>(vault_address);
        strategy_config.new_keeper_address = new_keeper_address;
    }

    public entry fun accept_keeper<StrategyType: drop>(
        new_keeper: &signer,
        vault_address: address,
    ) acquires StrategyConfig {
        assert_strategy_config_exists<StrategyType>(vault_address);
        let vault_config = borrow_global_mut<StrategyConfig<StrategyType>>(vault_address);
        assert!(signer::address_of(new_keeper) == vault_config.new_keeper_address, ERR_NOT_NEW_KEEPER);
        event::emit_event(&mut vault_config.keeper_change_events, KeeperChangeEvent {
            new_keeper_address: vault_config.new_keeper_address,
        });
        vault_config.keeper_address = vault_config.new_keeper_address;
        vault_config.new_keeper_address = @0x0;
    }

    public fun get_keeper_address<StrategyType: drop>(
        vault_address: address,
    ): address acquires StrategyConfig {
        assert_strategy_config_exists<StrategyType>(vault_address);
        let config = borrow_global<StrategyConfig<StrategyType>>(vault_address);
        config.keeper_address
    }

    public fun assert_keeper<StrategyType: drop>(
        keeper: &signer,
        vault_address: address,
    ) acquires StrategyConfig {
        assert_strategy_config_exists<StrategyType>(vault_address);
        let config = borrow_global<StrategyConfig<StrategyType>>(vault_address);
        assert!(signer::address_of(keeper) == config.keeper_address, ERR_NOT_KEEPER);
    }

    fun assert_strategy_config_exists<StrategyType: drop>(
        vault_address: address
    ) {
        assert!(exists<StrategyConfig<StrategyType>>(vault_address), ERR_CONFIG_DOES_NOT_EXIST);
    }
}
