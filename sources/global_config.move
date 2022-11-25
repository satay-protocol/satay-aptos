module satay::global_config {
    use std::signer;

    // use aptos_std::event::{Self, EventHandle};
    // use aptos_framework::account;

    friend satay::satay;

    // Error codes

    /// When config doesn't exists
    const ERROR_CONFIG_DOES_NOT_EXIST: u64 = 400;

    /// Unreachable, is a bug if thrown
    const ERR_UNREACHABLE: u64 = 401;

    /// When user is not admin
    const ERR_NOT_ADMIN: u64 = 402;

    /// When user is not governance
    const ERR_NOT_GOVERNANCE: u64 = 403;

    /// When user is not manager
    const ERR_NOT_MANAGER: u64 = 404;

    /// When user is not strategist
    const ERR_NOT_STRATEGIST: u64 = 405;

    /// When user is not keeper
    const ERR_NOT_KEEPER: u64 = 406;


    /// The global configuration
    struct GlobalConfig has key {
        dao_admin_address: address,
        governance_address: address,
        new_dao_admin_address: address,
        new_governance_address: address,
    }

    /// The vault configuration
    struct VaultConfig<phantom BaseCoin> has key {
        vault_manager_address: address,
        new_vault_manager_address: address,
    }

    /// The strategy configuration
    struct StrategyConfig<phantom StrategyType, phantom BaseCoin> has key {
        strategist_address: address,
        keeper_address: address,
        new_strategist_address: address,
        new_keeper_address: address,
    }

    /// Initialize admin contracts when initializing the satay
    public(friend) fun initialize(satay_admin: &signer) {
        assert!(signer::address_of(satay_admin) == @satay, ERR_UNREACHABLE);

        move_to(satay_admin, GlobalConfig {
            dao_admin_address: @satay,
            governance_address: @satay,
            new_dao_admin_address: @0x0,
            new_governance_address: @0x0,
        });
    }

    /// Initialize admin contracts when intializing the vault
    public(friend) fun initialize_vault<BaseCoin>(governance: &signer) acquires GlobalConfig {
        assert_governance(governance);

        move_to(governance, VaultConfig<BaseCoin> {
            vault_manager_address: @satay,
            new_vault_manager_address: @0x0,
        });
    }

    /// Initialize admin contracts when initializing the strategy
    public(friend) fun initialize_strategy<StrategyType: drop, BaseCoin>(governance: &signer) acquires GlobalConfig {
        assert_governance(governance);

        move_to(governance, StrategyConfig<StrategyType, BaseCoin> {
            strategist_address: @satay,
            keeper_address: @satay,
            new_strategist_address: @0x0,
            new_keeper_address: @0x0,
        });
    }

    /// Get DAO admin address
    public fun get_dao_admin(): address acquires GlobalConfig {
        assert!(exists<GlobalConfig>(@satay), ERROR_CONFIG_DOES_NOT_EXIST);

        let config = borrow_global<GlobalConfig>(@satay);
        config.dao_admin_address
    }

    /// Get Governance address
    public fun get_governance_address(): address acquires GlobalConfig {
        assert!(exists<GlobalConfig>(@satay), ERROR_CONFIG_DOES_NOT_EXIST);

        let config = borrow_global<GlobalConfig>(@satay);
        config.governance_address
    }

    /// Get vault manager address
    public fun get_vault_manager_address<BaseCoin>(): address acquires VaultConfig {
        assert!(exists<VaultConfig<BaseCoin>>(@satay), ERROR_CONFIG_DOES_NOT_EXIST);

        let config = borrow_global<VaultConfig<BaseCoin>>(@satay);
        config.vault_manager_address
    }

    /// Get strategist address
    public fun get_strategist_address<StrategyType: drop, BaseCoin>(): address acquires StrategyConfig {
        assert!(exists<StrategyConfig<StrategyType, BaseCoin>>(@satay), ERROR_CONFIG_DOES_NOT_EXIST);

        let config = borrow_global<StrategyConfig<StrategyType, BaseCoin>>(@satay);
        config.strategist_address
    }

    /// Get keeper address
    public fun get_keeper_address<StrategyType: drop, BaseCoin>(): address acquires StrategyConfig {
        assert!(exists<StrategyConfig<StrategyType, BaseCoin>>(@satay), ERROR_CONFIG_DOES_NOT_EXIST);

        let config = borrow_global<StrategyConfig<StrategyType, BaseCoin>>(@satay);
        config.keeper_address
    }

    /// is DAO admin
    public fun assert_dao_admin(dao_admin: &signer) acquires GlobalConfig {
        assert!(exists<GlobalConfig>(@satay), ERROR_CONFIG_DOES_NOT_EXIST);

        let config = borrow_global<GlobalConfig>(@satay);

        assert!(config.dao_admin_address == signer::address_of(dao_admin), ERR_NOT_ADMIN);
    }

    /// is Governance
    public fun assert_governance(governance: &signer) acquires GlobalConfig {
        assert!(exists<GlobalConfig>(@satay), ERROR_CONFIG_DOES_NOT_EXIST);

        let config = borrow_global<GlobalConfig>(@satay);

        assert!(config.governance_address == signer::address_of(governance), ERR_NOT_GOVERNANCE);
    }

    /// is Vault manager
    public fun assert_vault_manager<BaseCoin>(vault_manager: &signer) acquires GlobalConfig, VaultConfig {
        assert!(
            exists<GlobalConfig>(@satay) && 
            exists<VaultConfig<BaseCoin>>(@satay), 
            ERROR_CONFIG_DOES_NOT_EXIST);

        let addr = signer::address_of(vault_manager);
        let global_config = borrow_global<GlobalConfig>(@satay);
        let vault_config = borrow_global<VaultConfig<BaseCoin>>(@satay);

        assert!(
            global_config.governance_address == addr || 
            vault_config.vault_manager_address == addr, 
            ERR_NOT_MANAGER);
    }

    /// is Strategist
    public fun assert_strategist<StrategyType: drop, BaseCoin>(strategist: &signer) acquires GlobalConfig, VaultConfig, StrategyConfig {
        assert!(
            exists<GlobalConfig>(@satay) && 
            exists<VaultConfig<BaseCoin>>(@satay) && 
            exists<StrategyConfig<StrategyType, BaseCoin>>(@satay),
            ERROR_CONFIG_DOES_NOT_EXIST);

        let addr = signer::address_of(strategist);
        let global_config = borrow_global<GlobalConfig>(@satay);
        let vault_config = borrow_global<VaultConfig<BaseCoin>>(@satay);
        let strategy_config = borrow_global<StrategyConfig<StrategyType, BaseCoin>>(@satay);

        assert!(
            global_config.governance_address == addr || 
            vault_config.vault_manager_address == addr || 
            strategy_config.strategist_address == addr, 
            ERR_NOT_STRATEGIST);
    }

    /// is Keeper
    public fun assert_keeper<StrategyType: drop, BaseCoin>(keeper: &signer) acquires GlobalConfig, VaultConfig, StrategyConfig {
        assert!(
            exists<GlobalConfig>(@satay) && 
            exists<VaultConfig<BaseCoin>>(@satay) && 
            exists<StrategyConfig<StrategyType, BaseCoin>>(@satay),
            ERROR_CONFIG_DOES_NOT_EXIST);

        let addr = signer::address_of(keeper);
        let global_config = borrow_global<GlobalConfig>(@satay);
        let vault_config = borrow_global<VaultConfig<BaseCoin>>(@satay);
        let strategy_config = borrow_global<StrategyConfig<StrategyType, BaseCoin>>(@satay);

        assert!(
            global_config.governance_address == addr || 
            vault_config.vault_manager_address == addr || 
            strategy_config.strategist_address == addr || 
            strategy_config.keeper_address == addr, 
            ERR_NOT_KEEPER);
    }

    /// set new DAO admin address
    public entry fun set_dao_admin(dao_admin: &signer, new_addr: address) acquires GlobalConfig {
        assert_dao_admin(dao_admin);

        let config = borrow_global_mut<GlobalConfig>(@satay);

        config.new_dao_admin_address = new_addr;
    }

    /// accept new DAO admin address
    public entry fun accept_dao_admin(new_dao_admin: &signer) acquires GlobalConfig {
        assert!(exists<GlobalConfig>(@satay), ERROR_CONFIG_DOES_NOT_EXIST);

        let new_addr = signer::address_of(new_dao_admin);
        let config = borrow_global_mut<GlobalConfig>(@satay);

        assert!(config.new_dao_admin_address == new_addr, ERR_NOT_ADMIN);

        config.dao_admin_address = new_addr;
        config.new_dao_admin_address = @0x0;
    }

    /// set new Governance address
    public entry fun set_governance(governance: &signer, new_addr: address) acquires GlobalConfig {
        assert_governance(governance);

        let config = borrow_global_mut<GlobalConfig>(@satay);

        config.new_governance_address = new_addr;
    }

    /// accept new Governance address
    public entry fun accept_governance(new_governance: &signer) acquires GlobalConfig {
        assert!(exists<GlobalConfig>(@satay), ERROR_CONFIG_DOES_NOT_EXIST);

        let new_addr = signer::address_of(new_governance);
        let config = borrow_global_mut<GlobalConfig>(@satay);

        assert!(config.new_governance_address == new_addr, ERR_NOT_ADMIN);

        config.governance_address = new_addr;
        config.new_governance_address = @0x0;
    }

    /// set new Vault manager address
    public entry fun set_vault_manager<BaseCoin>(vault_manager: &signer, new_addr: address) acquires GlobalConfig, VaultConfig {
        assert_vault_manager<BaseCoin>(vault_manager);

        let config = borrow_global_mut<VaultConfig<BaseCoin>>(@satay);

        config.new_vault_manager_address = new_addr;
    }

    /// accept new Vault manager address
    public entry fun accept_vault_manager<BaseCoin>(new_vault_manager: &signer) acquires VaultConfig {
        assert!(exists<VaultConfig<BaseCoin>>(@satay), ERROR_CONFIG_DOES_NOT_EXIST);

        let new_addr = signer::address_of(new_vault_manager);
        let config = borrow_global_mut<VaultConfig<BaseCoin>>(@satay);

        assert!(config.new_vault_manager_address == new_addr, ERR_NOT_MANAGER);

        config.vault_manager_address = new_addr;
        config.new_vault_manager_address = @0x0;
    }

    /// set new Strategist address
    public entry fun set_strategist<StrategyType: drop, BaseCoin>(strategist: &signer, new_addr: address) acquires GlobalConfig, VaultConfig, StrategyConfig {
        assert_strategist<StrategyType, BaseCoin>(strategist);

        let config = borrow_global_mut<StrategyConfig<StrategyType, BaseCoin>>(@satay);

        config.new_strategist_address = new_addr;
    }

    /// accept new Strategist address
    public entry fun accept_strategist<StrategyType: drop, BaseCoin>(strategist: &signer) acquires StrategyConfig {
        assert!(exists<StrategyConfig<StrategyType, BaseCoin>>(@satay), ERROR_CONFIG_DOES_NOT_EXIST);

        let new_addr = signer::address_of(strategist);
        let config = borrow_global_mut<StrategyConfig<StrategyType, BaseCoin>>(@satay);

        assert!(config.new_strategist_address == new_addr, ERR_NOT_MANAGER);

        config.strategist_address = new_addr;
        config.new_strategist_address = @0x0;
    }

    /// set new Keeper address
    public entry fun set_keeper<StrategyType: drop, BaseCoin>(keeper: &signer, new_addr: address) acquires GlobalConfig, VaultConfig, StrategyConfig {
        assert_keeper<StrategyType, BaseCoin>(keeper);

        let config = borrow_global_mut<StrategyConfig<StrategyType, BaseCoin>>(@satay);

        config.new_keeper_address = new_addr;
    }

    /// accept new Keeper address
    public entry fun accept_keeper<StrategyType: drop, BaseCoin>(keeper: &signer) acquires StrategyConfig {
        assert!(exists<StrategyConfig<StrategyType, BaseCoin>>(@satay), ERROR_CONFIG_DOES_NOT_EXIST);

        let new_addr = signer::address_of(keeper);
        let config = borrow_global_mut<StrategyConfig<StrategyType, BaseCoin>>(@satay);

        assert!(config.new_keeper_address == new_addr, ERR_NOT_MANAGER);

        config.keeper_address = new_addr;
        config.new_keeper_address = @0x0;
    }
}