module satay::global_config {

    use std::signer;

    struct GlobalConfig has key {
        dao_admin_address: address,
        strategy_admin_address: address
    }

    const ERR_CONFIG_DOES_NOT_EXIST: u64 = 401;
    const ERR_NO_ADMIN: u64 = 402;
    const ERR_WRONG_ADMIN: u64 = 403;

    public fun initialize(satay_admin: &signer) {
        assert!(signer::address_of(satay_admin) == @satay, ERR_NO_ADMIN);

        move_to(satay_admin, GlobalConfig {
            dao_admin_address: @satay,
            strategy_admin_address: @satay
        })
    }

    public fun get_dao_admin(): address acquires GlobalConfig {
        assert!(exists<GlobalConfig>(@satay), ERR_CONFIG_DOES_NOT_EXIST);

        let config = borrow_global<GlobalConfig>(@satay);
        config.dao_admin_address
    }

    public fun set_dao_admin(dao_admin: &signer, new_admin: address) acquires GlobalConfig {
        assert!(exists<GlobalConfig>(@satay), ERR_CONFIG_DOES_NOT_EXIST);
        let config = borrow_global_mut<GlobalConfig>(@satay);
        assert!(signer::address_of(dao_admin) == config.dao_admin_address, ERR_WRONG_ADMIN);

        config.dao_admin_address = new_admin;
    }

    public fun get_strategy_admin(): address acquires GlobalConfig {
        assert!(exists<GlobalConfig>(@satay), ERR_CONFIG_DOES_NOT_EXIST);
        let config = borrow_global<GlobalConfig>(@satay);

        config.strategy_admin_address
    }

    public fun set_strategy_admin(strategy_admin: &signer, new_admin: address) acquires GlobalConfig {
        assert!(exists<GlobalConfig>(@satay), ERR_CONFIG_DOES_NOT_EXIST);
        let config = borrow_global_mut<GlobalConfig>(@satay);
        assert!(signer::address_of(strategy_admin) == config.strategy_admin_address, ERR_WRONG_ADMIN);
        config.strategy_admin_address = new_admin;
    }
}
