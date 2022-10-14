module satay::global_config {

    use std::signer;

    struct GlobalConfig has key {
        dao_admin_address: address,
        vault_manager_address: address
    }

    const ERR_CONFIG_DOES_NOT_EXIST: u64 = 401;
    const ERR_NO_ADMIN: u64 = 402;

    public fun initialize(satay_admin: &signer) {
        assert!(signer::address_of(satay_admin) == @satay, ERR_NO_ADMIN);

        move_to(satay_admin, GlobalConfig {
            dao_admin_address: @satay_dao_admin,
            vault_manager_address: @satay,
        })
    }

    public fun get_dao_admin(): address acquires GlobalConfig {
        assert!(exists<GlobalConfig>(@satay), ERR_CONFIG_DOES_NOT_EXIST);

        let config = borrow_global<GlobalConfig>(@satay);
        config.dao_admin_address
    }

    public fun get_vault_manager(): address acquires GlobalConfig {
        assert!(exists<GlobalConfig>(@satay), ERR_CONFIG_DOES_NOT_EXIST);

        let config = borrow_global<GlobalConfig>(@satay);
        config.vault_manager_address
    }
}
