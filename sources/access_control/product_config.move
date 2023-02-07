/// establishes access control for the strategy keeper role of strategies approved on a vault
module satay::product_config {
    use std::signer;

    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;

    use satay::vault_config;

    friend satay::base_product;

    // error codes

    /// when the strategy config does not exist
    const ERR_CONFIG_DOES_NOT_EXIST: u64 = 1;

    /// when the account calling accept_keeper is not the new keeper
    const ERR_NOT_NEW_MANAGER: u64 = 2;

    /// when the signer is not the keeper
    const ERR_NOT_MANAGER: u64 = 3;

    /// holds the product manager information for each (ProductTyoe, BaseCoin), stored in product account
    /// @field product_manager_address - the address of the current product manager
    /// @field new_product_manager_address - the address of the new product manager, set by set_product_manager
    /// @field product_manager_change_events - the event handle for ProductManagerChangeEvent
    struct ProductConfig<phantom ProductType: drop, phantom BaseCoin> has key {
        product_manager_address: address,
        new_product_manager_address: address,
        product_manager_change_events: EventHandle<ProductManagerChangeEvent>,
    }

    /// emitted when a new product manager accepts the role
    /// @field new_product_manager_address - the address of the new product manager
    struct ProductManagerChangeEvent has drop, store {
        new_product_manager_address: address,
    }

    /// initializes a ProductConfig resource in the product_account, called by base_product::initialize
    /// @param product_account - the transaction signer; the resource account for the product
    /// @param _witness - proves the origin of the call
    public(friend) fun initialize<ProductType: drop, BaseCoin>(
        vault_account: &signer,
        product_manager_address: address,
        _witness: &ProductType
    ) {
        move_to(vault_account, ProductConfig<ProductType, BaseCoin> {
            product_manager_address,
            new_product_manager_address: @0x0,
            product_manager_change_events: account::new_event_handle<ProductManagerChangeEvent>(vault_account),
        });
    }

    /// sets the new product manager address for the product
    /// @param product_manager - the transaction signer; must have the product manager role for the product
    /// @param product_address - the address of the product holding ProductConfig<ProductType, BaseCoin>
    /// @param new_product_manager_address - the address of the new product manager
    public entry fun set_product_manager<ProductType: drop, BaseCoin>(
        product_manager: &signer,
        product_address: address,
        new_product_manager_address: address
    )
    acquires ProductConfig {
        assert_product_config_exists<ProductType, BaseCoin>(product_address);
        vault_config::assert_vault_manager(product_manager, product_address);
        let strategy_config = borrow_global_mut<ProductConfig<ProductType, BaseCoin>>(product_address);
        strategy_config.new_product_manager_address = new_product_manager_address;
    }

    /// accepts the new product manager role for the product
    /// @param new_product_manager - the transaction signer; must be the new product manager address for the product
    /// @param product_address - the address of the product holding ProductConfig<ProductType, BaseCoin>
    public entry fun accept_product_manager<ProductType: drop, BaseCoin>(
        new_product_manager: &signer,
        product_address: address
    )
    acquires ProductConfig {
        assert_product_config_exists<ProductType, BaseCoin>(product_address);
        let product_config = borrow_global_mut<ProductConfig<ProductType, BaseCoin>>(product_address);
        assert!(signer::address_of(new_product_manager) == product_config.new_product_manager_address, ERR_NOT_MANAGER);
        event::emit_event(&mut product_config.product_manager_change_events, ProductManagerChangeEvent {
            new_product_manager_address: product_config.new_product_manager_address,
        });
        product_config.product_manager_address = product_config.new_product_manager_address;
        product_config.new_product_manager_address = @0x0;
    }

    /// returns the product manager address for the product
    /// @param product_address - the address of the product holding ProductConfig<ProductType, BaseCoin>
    public fun get_product_manager_address<ProductType: drop, BaseCoin>(product_address: address): address
    acquires ProductConfig {
        assert_product_config_exists<ProductType, BaseCoin>(product_address);
        let config = borrow_global<ProductConfig<ProductType, BaseCoin>>(product_address);
        config.product_manager_address
    }

    /// asserts that the signer has the keeper role for strategy type on vault_address
    /// @param keeper - the transaction signer; must have the keeper role for StrategyConfig<StrategyType> on vault_address
    /// @param vault_address - the address of the vault holding StrategyConfig<StrategyType>
    public fun assert_product_manager<ProductType: drop, BaseCoin>(product_manager: &signer, product_address: address)
    acquires ProductConfig {
        assert_product_config_exists<ProductType, BaseCoin>(product_address);
        let config = borrow_global<ProductConfig<ProductType, BaseCoin>>(product_address);
        assert!(signer::address_of(product_manager) == config.product_manager_address, ERR_NOT_MANAGER);
    }

    /// asserts that StrategyConfig<StrategyType> exists on vault_address
    /// @param vault_address - the address of the vault to check for StrategyConfig<StrategyType>
    fun assert_product_config_exists<ProductType: drop, BaseCoin>(product_address: address) {
        assert!(exists<ProductConfig<ProductType, BaseCoin>>(product_address), ERR_CONFIG_DOES_NOT_EXIST);
    }
}
