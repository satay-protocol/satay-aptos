module satay::global_config {

    use std::signer;

    struct GlobalConfig has key {
        dao_admin_address: address,
        strategy_admin_address: address
    }

    const ERR_CONFIG_DOES_NOT_EXIST: u64 = 401;
    const ERR_NO_ADMIN: u64 = 402;
    const ERR_WRONG_ADMIN: u64 = 403;

    // initialize dao_admin_address and strategy_admin_address
    public entry fun initialize(satay_admin: &signer) {
        // ensure initialize is only called by satay deployer
        assert!(signer::address_of(satay_admin) == @satay, ERR_NO_ADMIN);

        // store GlobalConfig in satay_admin account
        move_to(satay_admin, GlobalConfig {
            dao_admin_address: @satay,
            strategy_admin_address: @satay
        })
    }

    // setter methods

    // set dao_admin_address
    public entry fun set_dao_admin(dao_admin: &signer, new_admin: address) acquires GlobalConfig {
        // assert that global config has been initialized
        assert!(exists<GlobalConfig>(@satay), ERR_CONFIG_DOES_NOT_EXIST);

        // assert that signer is current dao_admin_address
        let config = borrow_global_mut<GlobalConfig>(@satay);
        assert!(signer::address_of(dao_admin) == config.dao_admin_address, ERR_WRONG_ADMIN);

        config.dao_admin_address = new_admin;
    }

    // set strategy_admin_address
    public entry fun set_strategy_admin(strategy_admin: &signer, new_admin: address) acquires GlobalConfig {
        // assert that global config has been initialized
        assert!(exists<GlobalConfig>(@satay), ERR_CONFIG_DOES_NOT_EXIST);

        // assert that signer is current strategy_admin_address
        let config = borrow_global_mut<GlobalConfig>(@satay);
        assert!(signer::address_of(strategy_admin) == config.strategy_admin_address, ERR_WRONG_ADMIN);

        config.strategy_admin_address = new_admin;
    }

    // getter methods

    // gets the current dao_admin_address
    public fun get_dao_admin(): address acquires GlobalConfig {
        assert!(exists<GlobalConfig>(@satay), ERR_CONFIG_DOES_NOT_EXIST);

        let config = borrow_global<GlobalConfig>(@satay);
        config.dao_admin_address
    }

    // get the current strategy_admin_address
    public fun get_strategy_admin(): address acquires GlobalConfig {
        assert!(exists<GlobalConfig>(@satay), ERR_CONFIG_DOES_NOT_EXIST);
        let config = borrow_global<GlobalConfig>(@satay);
        config.strategy_admin_address
    }
}
