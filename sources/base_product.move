module satay::base_product {

    use std::signer;
    use std::string;

    use std::option;

    use aptos_framework::coin::{Self, MintCapability, BurnCapability, Coin};
    use aptos_framework::account::{Self, SignerCapability};

    use satay::math;
    use satay::product_config;

    // error codes

    /// when non-deployer calls initialize
    const ERR_NOT_DEPLOYER: u64 = 1;
    /// when product is not initialized
    const ERR_NOT_INITIALIZED: u64 = 2;
    /// when non-manager calls manager function
    const ERR_NOT_MANAGER: u64 = 3;

    // constants

    /// replace this with the name of the coin you are issuing
    const NAME_PREFIX: vector<u8> = b"Product Coin";
    /// replace this with the symbol of the coin you are issuing
    const SYMBOL_PREFIX: vector<u8> = b"p";

    /// replace this with the unique product coin name
    struct ProductCoin<phantom ProductType: drop, phantom BaseCoin> {}

    struct ProductAccount<phantom ProductType: drop, phantom BaseCoin> has key {
        signer_cap: SignerCapability,
        manager_address: address,
        mint_cap: MintCapability<ProductCoin<ProductType, BaseCoin>>,
        burn_cap: BurnCapability<ProductCoin<ProductType, BaseCoin>>,
    }

    // deployer functions

    /// initialize the product account
    /// @param deployer - the transaction signer; must be the module deployer
    public fun initialize<ProductType: drop, BaseCoin>(deployer: &signer, witness: &ProductType) {
        // assert that the deployer is calling initialize
        assert_deployer(deployer);

        let name = string::utf8(NAME_PREFIX);
        let symbol = string::utf8(SYMBOL_PREFIX);

        let base_coin_name = coin::name<BaseCoin>();
        let base_coin_symbol = coin::symbol<BaseCoin>();

        string::append(&mut name, base_coin_name);
        string::append(&mut symbol, base_coin_symbol);

        let (
            burn_cap,
            freeze_cap,
            mint_cap
        ) = coin::initialize<ProductCoin<ProductType, BaseCoin>>(
            deployer,
            name,
            symbol,
            coin::decimals<BaseCoin>(),
            true,
        );
        coin::destroy_freeze_cap(freeze_cap);

        let (
            product_signer,
            signer_cap
        ) = account::create_resource_account(deployer, *string::bytes(&symbol));

        product_config::initialize<ProductType, BaseCoin>(
            &product_signer,
            signer::address_of(deployer),
            witness
        );

        // products may accept different base coins, in which case you would need to replace AptosCoin
        coin::register<BaseCoin>(&product_signer);

        let product_account = ProductAccount {
            signer_cap,
            manager_address: signer::address_of(deployer),
            mint_cap,
            burn_cap,
        };

        move_to(deployer, product_account);
    }

    // user scripts

    /// mint product coins
    /// @param user - the transaction signer; must hold amount of BaseCoin
    /// @param amount - the amount of BaseCoin to be converted to ProductCoin
    public entry fun deposit<ProductType: drop, BaseCoin>(user: &signer, amount: u64)
    acquires ProductAccount {
        let base_coins = coin::withdraw<BaseCoin>(user, amount);
        let product_coins = apply(base_coins);
        safe_deposit<ProductCoin<ProductType, BaseCoin>>(user, product_coins);
    }

    /// burn product coins
    /// @param user - the transaction signer; must hold amount of ProductCoin
    /// @param amount - the amount of ProductCoin to be converted to BaseCoin
    public entry fun withdraw<ProductType: drop, BaseCoin>(user: &signer, amount: u64)
    acquires ProductAccount {
        let product_coins = coin::withdraw<ProductCoin<ProductType, BaseCoin>>(user, amount);
        let base_coins = liquidate(product_coins);
        safe_deposit<BaseCoin>(user, base_coins);
    }

    // operations

    /// convert base coins to product coins
    /// @param base_coins - the base coins to convert
    public fun apply<ProductType: drop, BaseCoin>(base_coins: Coin<BaseCoin>): Coin<ProductCoin<ProductType, BaseCoin>>
    acquires ProductAccount {
        assert_product_initialized<ProductType, BaseCoin>();
        let base_coin_amount = coin::value(&base_coins);
        let mint_amount = calc_product_coin_amount<ProductType, BaseCoin>(base_coin_amount);
        let product_account = borrow_global<ProductAccount<ProductType, BaseCoin>>(@satay);
        coin::deposit(account::get_signer_capability_address(&product_account.signer_cap), base_coins);
        coin::mint(mint_amount, &product_account.mint_cap)
    }

    /// convert product coins to base coins
    /// @param product_coins - the product coins to convert
    public fun liquidate<ProductType: drop, BaseCoin>(product_coins: Coin<ProductCoin<ProductType, BaseCoin>>): Coin<BaseCoin>
    acquires ProductAccount {
        assert_product_initialized<ProductType, BaseCoin>();

        let product_coin_amount = coin::value(&product_coins);
        let base_coin_amount = calc_base_coin_amount<ProductType, BaseCoin>(product_coin_amount);

        let product_account = borrow_global<ProductAccount<ProductType, BaseCoin>>(@satay);
        let product_signer = account::create_signer_with_capability(&product_account.signer_cap);

        coin::burn(product_coins, &product_account.burn_cap);
        coin::withdraw<BaseCoin>(&product_signer, base_coin_amount)
    }

    // admin

    /// set the manager address
    /// @param manager - the transaction signer; must be the current manager
    /// @param new_manager - the new manager address
    public entry fun set_manager<ProductType: drop, BaseCoin>(manager: &signer, new_manager: address)
    acquires ProductAccount {
        assert_manager<ProductType, BaseCoin>(manager);
        borrow_global_mut<ProductAccount<ProductType, BaseCoin>>(signer::address_of(manager)).manager_address = new_manager;
    }

    /// claim rewards and reinvest
    /// @param user - the transaction signer; must hold > 0 ProductCoin
    public entry fun tend<ProductType: drop, BaseCoin>(manager: &signer)
    acquires ProductAccount {
        assert_manager<ProductType, BaseCoin>(manager);
        let returns = coin::zero<BaseCoin>();
        let product_address = product_account_address<ProductType, BaseCoin>();
        coin::deposit<BaseCoin>(product_address, returns);
    }

    // calculations

    /// calculate the amount of product coins that can be minted for a given amount of base coins
    /// @param product_coin_amount - the amount of ProductCoin<BaseCoin> to be converted
    public fun calc_base_coin_amount<ProductType: drop, BaseCoin>(product_coin_amount: u64): u64
    acquires ProductAccount {
        let product_account_address = product_account_address<ProductType, BaseCoin>();
        let product_coin_supply_option = coin::supply<ProductCoin<ProductType, BaseCoin>>();
        let base_coin_holdings = coin::balance<BaseCoin>(product_account_address);
        let product_coin_supply = option::get_with_default(&product_coin_supply_option, 0);
        if(product_coin_supply == 0) {
            return product_coin_amount
        };
        math::calculate_proportion_of_u64_with_u128_denominator(
            base_coin_holdings,
            product_coin_amount,
            product_coin_supply,
        )
    }

    /// calculate the amount of base coins that can be liquidated for a given amount of product coins
    /// @param base_coin_amount - the amount of BaseCoin to be converted
    public fun calc_product_coin_amount<ProductType: drop, BaseCoin>(base_coin_amount: u64): u64
    acquires ProductAccount {
        let product_account_address = product_account_address<ProductType, BaseCoin>();
        let product_coin_supply = coin::supply<ProductCoin<ProductType, BaseCoin>>();
        let base_coin_holdings = coin::balance<BaseCoin>(product_account_address);
        if(base_coin_holdings == 0) {
            return base_coin_amount
        };
        math::mul_u128_u64_div_u64_result_u64(
            option::get_with_default(&product_coin_supply, 0),
            base_coin_amount,
            base_coin_holdings,
        )
    }

    // helpers

    /// deposit CoinType to user, register if necessary
    /// @param user - the transaction signer
    /// @param product_coins - the coins to deposit
    fun safe_deposit<CoinType>(user: &signer, product_coins: Coin<CoinType>) {
        if (coin::is_account_registered<CoinType>(signer::address_of(user))) {
            coin::deposit<CoinType>(signer::address_of(user), product_coins);
        } else {
            coin::register<CoinType>(user);
            coin::deposit<CoinType>(signer::address_of(user), product_coins);
        }
    }

    // getters

    /// gets the address of the product account for BaseCoin
    public fun product_account_address<ProductType: drop, BaseCoin>(): address
    acquires ProductAccount {
        assert_product_initialized<ProductType, BaseCoin>();
        let product_account = borrow_global<ProductAccount<ProductType, BaseCoin>>(@satay);
        account::get_signer_capability_address(&product_account.signer_cap)
    }

    // access control

    /// asserts that the transaction signer is the deployer of the module
    /// @param deployer - must be the deployer of the package
    fun assert_deployer(deployer: &signer) {
        assert!(signer::address_of(deployer) == @satay, ERR_NOT_DEPLOYER);
    }

    fun assert_product_initialized<ProductType: drop, BaseCoin>() {
        assert!(exists<ProductAccount<ProductType, BaseCoin>>(@satay), ERR_NOT_INITIALIZED)
    }

    /// asserts that the transaction signer is the manager of the product
    /// @param manager - must be the manager of the product
    fun assert_manager<ProductType: drop, BaseCoin>(manager: &signer) acquires ProductAccount {
        assert_product_initialized<ProductType, BaseCoin>();
        let product_account = borrow_global<ProductAccount<ProductType, BaseCoin>>(@satay);
        assert!(signer::address_of(manager) == product_account.manager_address, ERR_NOT_MANAGER);
    }
}
