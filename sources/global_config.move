module satay::global_config {
    use std::signer;

    use aptos_framework::account::SignerCapability;
    use aptos_framework::account;

    friend satay::satay;

    // Error codes

    /// When config doesn't exists
    const ERR_CONFIG_DOES_NOT_EXIST: u64 = 400;

    /// Unreachable, is a bug if thrown
    const ERR_NOT_SATAY: u64 = 401;

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
    struct StrategyConfig<phantom StrategyType> has key {
        strategist_address: address,
        keeper_address: address,
        new_strategist_address: address,
        new_keeper_address: address,
    }

    struct GlobalConfigResourceAccount has key {
        signer_cap: SignerCapability
    }

    /// Initialize admin contracts when initializing the satay
    public(friend) fun initialize(satay_admin: &signer) {
        assert!(signer::address_of(satay_admin) == @satay, ERR_NOT_SATAY);

        let (global_config_signer, signer_cap) = account::create_resource_account(
            satay_admin,
            b"global config resource account",
        );

        move_to(satay_admin, GlobalConfigResourceAccount {signer_cap});

        move_to(&global_config_signer, GlobalConfig {
            dao_admin_address: @satay,
            governance_address: @satay,
            new_dao_admin_address: @0x0,
            new_governance_address: @0x0,
        });
    }

    /// Initialize admin contracts when intializing the vault
    public(friend) fun initialize_vault<BaseCoin>(
        governance: &signer
    ) acquires GlobalConfigResourceAccount, GlobalConfig {
        assert_governance(governance);

        let global_config_account = borrow_global<GlobalConfigResourceAccount>(@satay);
        let global_config_signer = account::create_signer_with_capability(&global_config_account.signer_cap);

        move_to(&global_config_signer, VaultConfig<BaseCoin> {
            vault_manager_address: @satay,
            new_vault_manager_address: @0x0,
        });
    }

    /// Initialize admin contracts when initializing the strategy
    public(friend) fun initialize_strategy<StrategyType: drop>(
        governance: &signer
    ) acquires GlobalConfig, GlobalConfigResourceAccount {
        assert_governance(governance);

        let global_config_account = borrow_global<GlobalConfigResourceAccount>(@satay);
        let global_config_signer = account::create_signer_with_capability(&global_config_account.signer_cap);

        move_to(&global_config_signer, StrategyConfig<StrategyType> {
            strategist_address: @satay,
            keeper_address: @satay,
            new_strategist_address: @0x0,
            new_keeper_address: @0x0,
        });
    }

    public fun get_global_config_account_address(): address acquires GlobalConfigResourceAccount {
        assert!(exists<GlobalConfigResourceAccount>(@satay), ERR_CONFIG_DOES_NOT_EXIST);

        let global_config_account = borrow_global<GlobalConfigResourceAccount>(@satay);
        let global_config_account_address = account::get_signer_capability_address(
            &global_config_account.signer_cap
        );

        assert!(exists<GlobalConfig>(global_config_account_address), ERR_CONFIG_DOES_NOT_EXIST);

        global_config_account_address
    }

    /// Get DAO admin address
    public fun get_dao_admin(): address acquires GlobalConfig, GlobalConfigResourceAccount {
        let global_config_account_address = get_global_config_account_address();
        let config = borrow_global<GlobalConfig>(global_config_account_address);
        config.dao_admin_address
    }

    /// Get Governance address
    public fun get_governance_address(): address acquires GlobalConfig, GlobalConfigResourceAccount {
        let global_config_account_address = get_global_config_account_address();
        let config = borrow_global<GlobalConfig>(global_config_account_address);
        config.governance_address
    }

    /// Get vault manager address
    public fun get_vault_manager_address<BaseCoin>(): address acquires VaultConfig, GlobalConfigResourceAccount {
        let global_config_account_address = get_global_config_account_address();

        assert!(exists<VaultConfig<BaseCoin>>(global_config_account_address), ERR_CONFIG_DOES_NOT_EXIST);

        let config = borrow_global<VaultConfig<BaseCoin>>(global_config_account_address);
        config.vault_manager_address
    }

    /// Get strategist address
    public fun get_strategist_address<StrategyType: drop>(): address acquires StrategyConfig, GlobalConfigResourceAccount {
        let global_config_account_address = get_global_config_account_address();

        assert!(exists<StrategyConfig<StrategyType>>(global_config_account_address), ERR_CONFIG_DOES_NOT_EXIST);

        let config = borrow_global<StrategyConfig<StrategyType>>(global_config_account_address);
        config.strategist_address
    }

    /// Get keeper address
    public fun get_keeper_address<StrategyType: drop>(): address acquires StrategyConfig, GlobalConfigResourceAccount {
        let global_config_account_address = get_global_config_account_address();

        assert!(exists<StrategyConfig<StrategyType>>(global_config_account_address), ERR_CONFIG_DOES_NOT_EXIST);

        let config = borrow_global<StrategyConfig<StrategyType>>(global_config_account_address);
        config.keeper_address
    }

    /// is DAO admin
    public fun assert_dao_admin(
        dao_admin: &signer
    ) acquires GlobalConfig, GlobalConfigResourceAccount {
        assert!(get_dao_admin() == signer::address_of(dao_admin), ERR_NOT_ADMIN);
    }

    /// is Governance
    public fun assert_governance(
        governance: &signer
    ) acquires GlobalConfig, GlobalConfigResourceAccount {
        assert!(get_governance_address() == signer::address_of(governance), ERR_NOT_GOVERNANCE);
    }

    /// is Vault manager
    public fun assert_vault_manager<BaseCoin>(
        vault_manager: &signer
    ) acquires GlobalConfigResourceAccount, GlobalConfig, VaultConfig {
        let addr = signer::address_of(vault_manager);

        assert!(
            get_governance_address() == addr ||
            get_vault_manager_address<BaseCoin>() == addr,
            ERR_NOT_MANAGER
        );
    }

    /// is Strategist
    public fun assert_strategist<StrategyType: drop, BaseCoin>(
        strategist: &signer
    ) acquires GlobalConfigResourceAccount, GlobalConfig, VaultConfig, StrategyConfig {
        let addr = signer::address_of(strategist);

        assert!(
            get_governance_address() == addr ||
            get_vault_manager_address<BaseCoin>() == addr ||
            get_strategist_address<StrategyType>() == addr,
            ERR_NOT_STRATEGIST
        );
    }

    /// is Keeper
    public fun assert_keeper<StrategyType: drop, BaseCoin>(
        keeper: &signer
    ) acquires GlobalConfigResourceAccount, GlobalConfig, VaultConfig, StrategyConfig {
        let addr = signer::address_of(keeper);

        assert!(
            get_governance_address() == addr ||
            get_vault_manager_address<BaseCoin>() == addr ||
            get_strategist_address<StrategyType>() == addr ||
            get_keeper_address<StrategyType>() == addr,
            ERR_NOT_KEEPER
        );
    }

    /// set new DAO admin address
    public entry fun set_dao_admin(
        dao_admin: &signer,
        new_addr: address
    ) acquires GlobalConfigResourceAccount, GlobalConfig {
        assert_dao_admin(dao_admin);
        let global_config_account_address = get_global_config_account_address();
        let config = borrow_global_mut<GlobalConfig>(global_config_account_address);
        config.new_dao_admin_address = new_addr;
    }

    /// accept new DAO admin address
    public entry fun accept_dao_admin(
        new_dao_admin: &signer
    ) acquires GlobalConfigResourceAccount, GlobalConfig {
        let global_config_account_address = get_global_config_account_address();

        let new_addr = signer::address_of(new_dao_admin);
        let config = borrow_global_mut<GlobalConfig>(global_config_account_address);

        assert!(config.new_dao_admin_address == new_addr, ERR_NOT_ADMIN);

        config.dao_admin_address = new_addr;
        config.new_dao_admin_address = @0x0;
    }

    /// set new Governance address
    public entry fun set_governance(
        governance: &signer,
        new_addr: address
    ) acquires GlobalConfigResourceAccount, GlobalConfig {
        assert_governance(governance);

        let global_config_account_address = get_global_config_account_address();

        let config = borrow_global_mut<GlobalConfig>(global_config_account_address);

        config.new_governance_address = new_addr;
    }

    /// accept new Governance address
    public entry fun accept_governance(
        new_governance: &signer
    ) acquires GlobalConfigResourceAccount, GlobalConfig {
        let global_config_account_address = get_global_config_account_address();

        let new_addr = signer::address_of(new_governance);
        let config = borrow_global_mut<GlobalConfig>(global_config_account_address);

        assert!(config.new_governance_address == new_addr, ERR_NOT_ADMIN);

        config.governance_address = new_addr;
        config.new_governance_address = @0x0;
    }

    /// set new Vault manager address
    public entry fun set_vault_manager<BaseCoin>(
        vault_manager: &signer,
        new_addr: address
    ) acquires GlobalConfigResourceAccount, GlobalConfig, VaultConfig {
        assert_vault_manager<BaseCoin>(vault_manager);

        let global_config_account_address = get_global_config_account_address();

        let config = borrow_global_mut<VaultConfig<BaseCoin>>(global_config_account_address);

        config.new_vault_manager_address = new_addr;
    }

    /// accept new Vault manager address
    public entry fun accept_vault_manager<BaseCoin>(
        new_vault_manager: &signer
    ) acquires GlobalConfigResourceAccount, VaultConfig {
        let global_config_account_address = get_global_config_account_address();

        let new_addr = signer::address_of(new_vault_manager);
        let config = borrow_global_mut<VaultConfig<BaseCoin>>(global_config_account_address);

        assert!(config.new_vault_manager_address == new_addr, ERR_NOT_MANAGER);

        config.vault_manager_address = new_addr;
        config.new_vault_manager_address = @0x0;
    }

    /// set new Strategist address
    public entry fun set_strategist<StrategyType: drop, BaseCoin>(
        strategist: &signer,
        new_addr: address
    ) acquires GlobalConfigResourceAccount, GlobalConfig, VaultConfig, StrategyConfig {
        assert_strategist<StrategyType, BaseCoin>(strategist);

        let global_config_account_address = get_global_config_account_address();

        let config = borrow_global_mut<StrategyConfig<StrategyType>>(global_config_account_address);

        config.new_strategist_address = new_addr;
    }

    /// accept new Strategist address
    public entry fun accept_strategist<StrategyType: drop>(
        strategist: &signer
    ) acquires GlobalConfigResourceAccount, StrategyConfig {
        let global_config_account_address = get_global_config_account_address();

        let new_addr = signer::address_of(strategist);
        let config = borrow_global_mut<StrategyConfig<StrategyType>>(global_config_account_address);

        assert!(config.new_strategist_address == new_addr, ERR_NOT_MANAGER);

        config.strategist_address = new_addr;
        config.new_strategist_address = @0x0;
    }

    /// set new Keeper address
    public entry fun set_keeper<StrategyType: drop, BaseCoin>(
        keeper: &signer,
        new_addr: address
    ) acquires GlobalConfig, VaultConfig, StrategyConfig, GlobalConfigResourceAccount {
        assert_keeper<StrategyType, BaseCoin>(keeper);

        let global_config_account_address = get_global_config_account_address();

        let config = borrow_global_mut<StrategyConfig<StrategyType>>(global_config_account_address);

        config.new_keeper_address = new_addr;
    }

    /// accept new Keeper address
    public entry fun accept_keeper<StrategyType: drop>(keeper: &signer) acquires StrategyConfig, GlobalConfigResourceAccount {
        let global_config_account_address = get_global_config_account_address();

        assert!(exists<StrategyConfig<StrategyType>>(global_config_account_address), ERR_CONFIG_DOES_NOT_EXIST);

        let new_addr = signer::address_of(keeper);
        let config = borrow_global_mut<StrategyConfig<StrategyType>>(global_config_account_address);

        assert!(config.new_keeper_address == new_addr, ERR_NOT_MANAGER);

        config.keeper_address = new_addr;
        config.new_keeper_address = @0x0;
    }
}