module satay::strategy_coin {

    use std::signer;
    use std::string;


    use aptos_framework::coin::{Self, MintCapability, BurnCapability, Coin, FreezeCapability};
    use aptos_framework::account::{Self, SignerCapability};

    use satay::strategy_config;
    use aptos_std::type_info;

    // error codes

    /// when non-deployer calls initialize
    const ERR_NOT_DEPLOYER: u64 = 1;
    /// when product is not initialized
    const ERR_NOT_INITIALIZED: u64 = 2;
    /// when non-manager calls manager function
    const ERR_NOT_MANAGER: u64 = 3;

    // constants

    /// replace this with the name of the coin you are issuing
    const NAME_SUFFIX: vector<u8> = b" Coin";
    /// replace this with the symbol of the coin you are issuing
    const SYMBOL_PREFIX: vector<u8> = b"";

    /// replace this with the unique product coin name
    struct StrategyCoin<phantom StrategyType: drop, phantom BaseCoin> {}

    struct StrategyAccount<phantom StrategyType: drop, phantom BaseCoin> has key {
        signer_cap: SignerCapability,
        manager_address: address,
        mint_cap: MintCapability<StrategyCoin<StrategyType, BaseCoin>>,
        burn_cap: BurnCapability<StrategyCoin<StrategyType, BaseCoin>>,
        freeze_cap: FreezeCapability<StrategyCoin<StrategyType, BaseCoin>>
    }

    // deployer functions

    /// initialize the strategy coin and account
    /// @param strategy_manager - the transaction signer
    public fun initialize<StrategyType: drop, BaseCoin>(deployer: &signer, witness: StrategyType) {
        // assert that the deployer is calling initialize
        assert_deployer(deployer);

        let strategy_struct = type_info::struct_name(&type_info::type_of<StrategyType>());

        let name = coin::name<BaseCoin>();
        string::append_utf8(&mut name, b"-");
        string::append_utf8(&mut name, copy strategy_struct);
        string::append_utf8(&mut name, NAME_SUFFIX);


        let symbol = coin::symbol<BaseCoin>();
        string::append_utf8(&mut symbol, b"-");
        string::append_utf8(&mut name, copy strategy_struct);

        let (
            burn_cap,
            freeze_cap,
            mint_cap
        ) = coin::initialize<StrategyCoin<StrategyType, BaseCoin>>(
            deployer,
            name,
            symbol,
            coin::decimals<BaseCoin>(),
            true,
        );

        let (
            strategy_signer,
            signer_cap
        ) = account::create_resource_account(deployer, *string::bytes(&symbol));

        strategy_config::initialize<StrategyType, BaseCoin>(
            &strategy_signer,
            signer::address_of(deployer),
            &witness
        );

        coin::register<BaseCoin>(&strategy_signer);

        let product_account = StrategyAccount {
            signer_cap,
            manager_address: signer::address_of(deployer),
            mint_cap,
            burn_cap,
            freeze_cap
        };

        move_to(deployer, product_account);
    }

    // mint and burn

    public fun mint<StrategyType: drop, BaseCoin>(
        amount: u64,
        _witness: StrategyType,
    ): Coin<StrategyCoin<StrategyType, BaseCoin>>
    acquires StrategyAccount {
        assert_strategy_initialized<StrategyType, BaseCoin>();
        let strategy_account = borrow_global_mut<StrategyAccount<StrategyType, BaseCoin>>(@satay);
        coin::mint(amount, &strategy_account.mint_cap)
    }


    public fun burn<StrategyType: drop, BaseCoin>(
        strategy_coins: Coin<StrategyCoin<StrategyType, BaseCoin>>,
        _witness: StrategyType
    )
    acquires StrategyAccount {
        assert_strategy_initialized<StrategyType, BaseCoin>();
        let strategy_account = borrow_global_mut<StrategyAccount<StrategyType, BaseCoin>>(@satay);
        coin::burn(strategy_coins, &strategy_account.burn_cap)
    }

    // helpers

    /// deposit CoinType to user, register if necessary
    /// @param user - the transaction signer
    /// @param coins - the coins to deposit
    public fun safe_deposit<CoinType>(user: &signer, coins: Coin<CoinType>) {
        if (coin::is_account_registered<CoinType>(signer::address_of(user))) {
            coin::deposit<CoinType>(signer::address_of(user), coins);
        } else {
            coin::register<CoinType>(user);
            coin::deposit<CoinType>(signer::address_of(user), coins);
        }
    }

    // getters

    /// gets the address of the product account for BaseCoin
    public fun strategy_account_address<StrategyType: drop, BaseCoin>(): address
    acquires StrategyAccount {
        assert_strategy_initialized<StrategyType, BaseCoin>();
        let strategy_account = borrow_global<StrategyAccount<StrategyType, BaseCoin>>(@satay);
        account::get_signer_capability_address(&strategy_account.signer_cap)
    }

    // access control

    /// asserts that the transaction signer is the deployer of the module
    /// @param deployer - must be the deployer of the package
    fun assert_deployer(deployer: &signer) {
        assert!(signer::address_of(deployer) == @satay, ERR_NOT_DEPLOYER);
    }

    fun assert_strategy_initialized<StrategyType: drop, BaseCoin>() {
        assert!(exists<StrategyAccount<StrategyType, BaseCoin>>(@satay), ERR_NOT_INITIALIZED)
    }
}
