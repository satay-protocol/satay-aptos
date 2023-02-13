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
    struct StrategyCapability<phantom BaseCoin, phantom StrategyType: drop> has store {
        signer_cap: SignerCapability
    }

    /// the coin capabilities for StrategyCoin<BaseCoin, StrategyType>
    /// @param signer_cap - the signer capability for the strategy account
    /// @param mint_cap - the mint capability for the strategy coin
    /// @param burn_cap - the burn capability for the strategy coin
    /// @param freeze_cap - the freeze capability for the strategy coin
    struct StrategyCoinCaps<phantom BaseCoin, phantom StrategyType: drop> has key {
        mint_cap: MintCapability<StrategyCoin<BaseCoin, StrategyType>>,
        burn_cap: BurnCapability<StrategyCoin<BaseCoin, StrategyType>>,
        freeze_cap: FreezeCapability<StrategyCoin<BaseCoin, StrategyType>>
    }

    /// stores the coins for a strategy
    /// @field coin - the coin
    struct CoinStore<phantom CoinType> has key {
        coin: Coin<CoinType>
    }

    // governance functions

    /// register the strategy coin and account
    /// @param strategy_manager - the transaction signer
    public(friend) fun initialize<BaseCoin, StrategyType: drop>(
        satay_account: &signer,
        strategy_manager_address: address,
        witness: StrategyType
    ): StrategyCapability<BaseCoin, StrategyType> {
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
        ) = coin::initialize<StrategyCoin<BaseCoin, StrategyType>>(
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

        strategy_config::initialize<BaseCoin, StrategyType>(
            &strategy_signer,
            strategy_manager_address,
            &witness
        );

        let strategy_coin_caps = StrategyCoinCaps<BaseCoin, StrategyType> {
            mint_cap,
            burn_cap,
            freeze_cap
        };

        move_to(&strategy_signer, strategy_coin_caps);

        let strategy_cap = StrategyCapability<BaseCoin, StrategyType> {
            signer_cap
        };

        add_coin<BaseCoin, StrategyType, BaseCoin>(&strategy_cap);

        strategy_cap
    }

    // mint and burn

    /// mint amount of StrategyCoin<BaseCoin, StrategyType>
    /// @param strategy_cap - the StrategyCapability for the strategy account
    /// @param amount - the amount of StrategyCoin<BaseCoin, StrategyType> to mint
    public(friend) fun mint<BaseCoin, StrategyType: drop>(
        strategy_cap: &StrategyCapability<BaseCoin, StrategyType>,
        amount: u64,
    ): Coin<StrategyCoin<BaseCoin, StrategyType>>
    acquires StrategyCoinCaps {
        let strategy_address = strategy_account_address(strategy_cap);
        let strategy_coin_caps = borrow_global<StrategyCoinCaps<BaseCoin, StrategyType>>(strategy_address);
        coin::mint(amount, &strategy_coin_caps.mint_cap)
    }

    /// burn amount of StrategyCoin<BaseCoin, StrategyType>
    /// @param strategy_coins - the StrategyCoin<BaseCoin, StrategyType> to burn
    /// _witness - the witness for the strategy type
    public(friend) fun burn<BaseCoin, StrategyType: drop>(
        strategy_cap: &StrategyCapability<BaseCoin, StrategyType>,
        strategy_coins: Coin<StrategyCoin<BaseCoin, StrategyType>>
    )
    acquires StrategyCoinCaps {
        let strategy_address = strategy_account_address(strategy_cap);
        let strategy_coin_caps = borrow_global<StrategyCoinCaps<BaseCoin, StrategyType>>(strategy_address);
        coin::burn(strategy_coins, &strategy_coin_caps.burn_cap);
    }

    // coin functions

    /// creates a CoinStore<CoinType> in the strategy account
    /// @param strategy_cap - the StrategyCapability for the strategy account
    public(friend) fun add_coin<BaseCoin, StrategyType: drop, CoinType>(
        strategy_cap: &StrategyCapability<BaseCoin, StrategyType>
    ) {
        let strategy_signer = account::create_signer_with_capability(&strategy_cap.signer_cap);
        move_to(&strategy_signer, CoinStore<CoinType> {
            coin: coin::zero<CoinType>()
        });
    }

    /// deposit CoinType into strategy account
    /// @param strategy_cap - the StrategyCapability for the strategy account
    /// @param coins - the coins to deposit
    public(friend) fun deposit<BaseCoin, StrategyType: drop, CoinType>(
        strategy_cap: &StrategyCapability<BaseCoin, StrategyType>,
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
    public(friend) fun withdraw<BaseCoin, StrategyType: drop, CoinType>(
        strategy_cap: &StrategyCapability<BaseCoin, StrategyType>,
        amount: u64
    ): Coin<CoinType>
    acquires CoinStore {
        let strategy_coin_account_address = strategy_account_address(strategy_cap);
        let coin_store = borrow_global_mut<CoinStore<CoinType>>(strategy_coin_account_address);
        coin::extract(&mut coin_store.coin, amount)
    }

    // getters

    /// gets the address of the strategy account
    public fun strategy_account_address<BaseCoin, StrategyType: drop>(
        strategy_cap: &StrategyCapability<BaseCoin, StrategyType>
    ): address {
        account::get_signer_capability_address(&strategy_cap.signer_cap)
    }

    /// gets the CoinType balance of the strategy account
    public fun balance<BaseCoin, StrategyType: drop, CoinType>(
        strategy_cap: &StrategyCapability<BaseCoin, StrategyType>
    ): u64 acquires CoinStore {
        let strategy_address = strategy_account_address(strategy_cap);
        let coin_store = borrow_global<CoinStore<CoinType>>(strategy_address);
        coin::value<CoinType>(&coin_store.coin)
    }
}
