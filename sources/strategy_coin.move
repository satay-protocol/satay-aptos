module satay::strategy_coin {

    use std::string;

    use aptos_std::type_info;

    use aptos_framework::coin::{Self, MintCapability, BurnCapability, Coin, FreezeCapability};
    use aptos_framework::account::{Self, SignerCapability};

    use satay_coins::strategy_coin::StrategyCoin;

    use satay::strategy_config;

    friend satay::satay;

    // error codes

    /// the strategy capability
    /// @param signer_cap - the StrategyCapability for the strategy account
    struct StrategyCapability<phantom StrategyType, phantom BaseCoin> has store {
        signer_cap: SignerCapability
    }

    /// the coin capabilities for StrategyCoin<StrategyType, BaseCoin>
    /// @param signer_cap - the signer capability for the strategy account
    /// @param mint_cap - the mint capability for the strategy coin
    /// @param burn_cap - the burn capability for the strategy coin
    /// @param freeze_cap - the freeze capability for the strategy coin
    struct StrategyCoinCaps<phantom StrategyType: drop, phantom BaseCoin> has key {
        mint_cap: MintCapability<StrategyCoin<StrategyType, BaseCoin>>,
        burn_cap: BurnCapability<StrategyCoin<StrategyType, BaseCoin>>,
        freeze_cap: FreezeCapability<StrategyCoin<StrategyType, BaseCoin>>
    }

    /// stores the coins for a strategy
    /// @field coin - the coin
    struct CoinStore<phantom CoinType> has key {
        coin: Coin<CoinType>
    }

    // governance functions

    /// register the strategy coin and account
    /// @param strategy_manager - the transaction signer
    public(friend) fun initialize<StrategyType: drop, BaseCoin>(
        satay_account: &signer,
        strategy_manager_address: address,
        witness: StrategyType
    ): StrategyCapability<StrategyType, BaseCoin> {
        let strategy_struct = type_info::struct_name(&type_info::type_of<StrategyType>());
        let base_coin_symbol = coin::symbol<BaseCoin>();

        let name = copy base_coin_symbol;
        string::append_utf8(&mut name, b":");
        string::append_utf8(&mut name, copy strategy_struct);

        let symbol = coin::symbol<BaseCoin>();
        string::append_utf8(&mut symbol, b":");
        string::append_utf8(&mut name, copy strategy_struct);

        let (
            burn_cap,
            freeze_cap,
            mint_cap
        ) = coin::initialize<StrategyCoin<StrategyType, BaseCoin>>(
            satay_account,
            name,
            symbol,
            coin::decimals<BaseCoin>(),
            true,
        );

        let (
            strategy_signer,
            signer_cap
        ) = account::create_resource_account(satay_account, *string::bytes(&symbol));

        strategy_config::initialize<StrategyType, BaseCoin>(
            &strategy_signer,
            strategy_manager_address,
            &witness
        );



        let strategy_coin_caps = StrategyCoinCaps<StrategyType, BaseCoin> {
            mint_cap,
            burn_cap,
            freeze_cap
        };

        move_to(&strategy_signer, strategy_coin_caps);

        let strategy_cap = StrategyCapability<StrategyType, BaseCoin> {
            signer_cap
        };

        add_coin<StrategyType, BaseCoin, BaseCoin>(&strategy_cap);

        strategy_cap
    }

    // mint and burn

    /// mint amount of StrategyCoin<StrategyType, BaseCoin>
    /// @param strategy_cap - the StrategyCapability for the strategy account
    /// @param amount - the amount of StrategyCoin<StrategyType, BaseCoin> to mint
    public(friend) fun mint<StrategyType: drop, BaseCoin>(
        strategy_cap: &StrategyCapability<StrategyType, BaseCoin>,
        amount: u64,
    ): Coin<StrategyCoin<StrategyType, BaseCoin>>
    acquires StrategyCoinCaps {
        let strategy_address = strategy_account_address(strategy_cap);
        let strategy_coin_caps = borrow_global<StrategyCoinCaps<StrategyType, BaseCoin>>(strategy_address);
        coin::mint(amount, &strategy_coin_caps.mint_cap)
    }

    /// burn amount of StrategyCoin<StrategyType, BaseCoin>
    /// @param strategy_coins - the StrategyCoin<StrategyType, BaseCoin> to burn
    /// _witness - the witness for the strategy type
    public(friend) fun burn<StrategyType: drop, BaseCoin>(
        strategy_cap: &StrategyCapability<StrategyType, BaseCoin>,
        strategy_coins: Coin<StrategyCoin<StrategyType, BaseCoin>>
    )
    acquires StrategyCoinCaps {
        let strategy_address = strategy_account_address(strategy_cap);
        let strategy_coin_caps = borrow_global<StrategyCoinCaps<StrategyType, BaseCoin>>(strategy_address);
        coin::burn(strategy_coins, &strategy_coin_caps.burn_cap);
    }

    // coin functions

    /// creates a CoinStore<CoinType> in the strategy account
    /// @param strategy_cap - the StrategyCapability for the strategy account
    public(friend) fun add_coin<StrategyType: drop, BaseCoin, CoinType>(
        strategy_cap: &StrategyCapability<StrategyType, BaseCoin>
    ) {
        let strategy_signer = account::create_signer_with_capability(&strategy_cap.signer_cap);
        move_to(&strategy_signer, CoinStore<CoinType> {
            coin: coin::zero<CoinType>()
        });
    }

    /// deposit CoinType into strategy account
    /// @param strategy_cap - the StrategyCapability for the strategy account
    /// @param coins - the coins to deposit
    public(friend) fun deposit<StrategyType: drop, BaseCoin, CoinType>(
        strategy_cap: &StrategyCapability<StrategyType, BaseCoin>,
        coins: Coin<CoinType>
    )
    acquires CoinStore {
        let strategy_coin_account_address = strategy_account_address(strategy_cap);
        let coin_store = borrow_global_mut<CoinStore<CoinType>>(strategy_coin_account_address);
        coin::merge(&mut coin_store.coin, coins);
    }

    /// withdraw CoinType from strategy account
    /// @param strategy_cap - the StrategyCapability for the strategy account
    /// @param amount - the amount of CoinType to withdraw
    public(friend) fun withdraw<StrategyType: drop, BaseCoin, CoinType>(
        strategy_cap: &StrategyCapability<StrategyType, BaseCoin>,
        amount: u64
    ): Coin<CoinType>
    acquires CoinStore {
        let strategy_coin_account_address = strategy_account_address(strategy_cap);
        let coin_store = borrow_global_mut<CoinStore<CoinType>>(strategy_coin_account_address);
        coin::extract(&mut coin_store.coin, amount)
    }

    // getters

    /// gets the address of the product account for BaseCoin
    public fun strategy_account_address<StrategyType: drop, BaseCoin>(
        strategy_cap: &StrategyCapability<StrategyType, BaseCoin>
    ): address {
        account::get_signer_capability_address(&strategy_cap.signer_cap)
    }
}
