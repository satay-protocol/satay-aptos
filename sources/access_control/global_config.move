module satay::global_config {
    use std::signer;

    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::event::{Self, EventHandle};

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

    /// When user is not keeper
    const ERR_NOT_KEEPER: u64 = 405;

    struct GlobalConfigResourceAccount has key {
        signer_cap: SignerCapability
    }

    /// The global configuration
    struct GlobalConfig has key {
        dao_admin_address: address,
        governance_address: address,
        new_dao_admin_address: address,
        new_governance_address: address,
        dao_admin_change_events: EventHandle<DaoAdminChangeEvent>,
        governance_change_events: EventHandle<GovernanceChangeEvent>,
    }

    // events

    struct DaoAdminChangeEvent has drop, store {
        new_dao_admin_address: address,
    }

    struct GovernanceChangeEvent has drop, store {
        new_governance_address: address,
    }

    /// Initialize admin contracts when initializing the satay
    public(friend) fun initialize(satay_admin: &signer) acquires GlobalConfig {
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
            dao_admin_change_events: account::new_event_handle<DaoAdminChangeEvent>(&global_config_signer),
            governance_change_events: account::new_event_handle<GovernanceChangeEvent>(&global_config_signer),
        });

        let global_config_account_address = signer::address_of(&global_config_signer);
        let global_config = borrow_global_mut<GlobalConfig>(global_config_account_address);
        event::emit_event(&mut global_config.dao_admin_change_events, DaoAdminChangeEvent {
            new_dao_admin_address: @satay
        });
        event::emit_event(&mut global_config.governance_change_events, GovernanceChangeEvent {
            new_governance_address: @satay
        });
    }

    // getter functions

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

        let new_dao_admin_address = signer::address_of(new_dao_admin);
        let config = borrow_global_mut<GlobalConfig>(global_config_account_address);

        assert!(config.new_dao_admin_address == new_dao_admin_address, ERR_NOT_ADMIN);

        config.dao_admin_address = new_dao_admin_address;
        config.new_dao_admin_address = @0x0;

        event::emit_event(&mut config.dao_admin_change_events, DaoAdminChangeEvent {
            new_dao_admin_address
        });
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

        let new_governance_address = signer::address_of(new_governance);
        let config = borrow_global_mut<GlobalConfig>(global_config_account_address);

        assert!(config.new_governance_address == new_governance_address, ERR_NOT_ADMIN);

        config.governance_address = new_governance_address;
        config.new_governance_address = @0x0;

        event::emit_event(&mut config.governance_change_events, GovernanceChangeEvent {
            new_governance_address
        });
    }
}