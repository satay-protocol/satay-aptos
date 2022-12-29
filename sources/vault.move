module satay::vault {
    use std::signer;
    use std::string;
    use std::option;

    use aptos_std::type_info::{TypeInfo};
    use aptos_std::type_info;

    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability, FreezeCapability};
    use aptos_framework::timestamp;
    use aptos_framework::event::{Self, EventHandle};

    use satay::dao_storage;
    use satay::math;

    friend satay::satay;
    friend satay::base_strategy;
  
    const MAX_DEBT_RATIO_BPS: u64 = 10000; // 100%
    const MAX_MANAGEMENT_FEE: u64 = 5000; // 50%
    const MAX_PERFORMANCE_FEE: u64 = 5000; // 50%
    const SECS_PER_YEAR: u64 = 31556952; // 365.2425 days

    const ERR_NO_USER_POSITION: u64 = 101;
    const ERR_NOT_ENOUGH_USER_POSITION: u64 = 102;
    const ERR_COIN: u64 = 103;
    const ERR_NOT_REGISTERED_USER: u64 = 104;
    const ERR_STRATEGY_NOT_REGISTERED: u64 = 105;
    const ERR_INVALID_DEBT_RATIO: u64 = 106;
    const ERR_INVALID_FEE: u64 = 107;
    const ERR_INSUFFICIENT_CREDIT: u64 = 108;

    struct CoinStore<phantom CoinType> has key {
        coin: Coin<CoinType>
    }

    struct Vault has key {
        base_coin_type: TypeInfo,
        base_coin_decimals: u8,
        management_fee: u64,
        performance_fee: u64,
        debt_ratio: u64,
        total_debt: u64,
        deposit_event: EventHandle<DepositEvent>,
        withdraw_event: EventHandle<WithdrawEvent>,
    }

    struct VaultCapability has store, drop {
        storage_cap: SignerCapability,
        vault_id: u64,
        vault_addr: address,
    }

    struct VaultCoin<phantom BaseCoin> has key {}

    struct VaultCoinCaps<phantom BaseCoin> has key {
        mint_cap: MintCapability<VaultCoin<BaseCoin>>,
        freeze_cap: FreezeCapability<VaultCoin<BaseCoin>>,
        burn_cap: BurnCapability<VaultCoin<BaseCoin>>
    }

    struct VaultStrategy<phantom StrategyType> has key, store {
        strategy_coin_type: TypeInfo,
        debt_ratio: u64,
        total_debt: u64,
        total_gain: u64,
        total_loss: u64,
        last_report: u64,
    }

    // events

    struct DepositEvent has drop, store {
        user_addr: address,
        base_coin_amount: u64,
        vault_coin_amount: u64,
    }

    struct WithdrawEvent has drop, store {
        user_addr: address,
        base_coin_amount: u64,
        vault_coin_amount: u64,
    }

    // for satay

    // create new vault with BaseCoin as its base coin type
    public(friend) fun new<BaseCoin>(
        governance: &signer, 
        seed: vector<u8>, 
        vault_id: u64,
        management_fee: u64,
        performance_fee: u64
    ): VaultCapability {
        assert_fee_amounts(management_fee, performance_fee);

        // create a resource account for the vault managed by the sender
        let (vault_acc, storage_cap) = account::create_resource_account(governance, seed);

        // create a new vault and move it to the vault account
        let base_coin_type = type_info::type_of<BaseCoin>();
        let base_coin_decimals = coin::decimals<BaseCoin>();
        let vault = Vault {
            base_coin_type,
            base_coin_decimals,
            management_fee,
            performance_fee,
            debt_ratio: 0,
            total_debt: 0,
            deposit_event: account::new_event_handle<DepositEvent>(&vault_acc),
            withdraw_event: account::new_event_handle<WithdrawEvent>(&vault_acc),
        };
        move_to(&vault_acc, vault);

        // create vault coin name
        let vault_coin_name = coin::name<BaseCoin>();
        string::append_utf8(&mut vault_coin_name, b" Vault");

        // create vault coin symbol
        let vault_coin_symbol = string::utf8(b"s");
        string::append(&mut vault_coin_symbol, coin::symbol<BaseCoin>());

        // initialize vault coin and move vault caps to vault owner
        let (burn_cap,
            freeze_cap,
            mint_cap
        ) = coin::initialize<VaultCoin<BaseCoin>>(
            governance,
            vault_coin_name,
            vault_coin_symbol,
            base_coin_decimals,
            true
        );
        move_to(&vault_acc, VaultCoinCaps<BaseCoin> { mint_cap, freeze_cap, burn_cap});

        // create vault capability and use it to add BaseCoin to coin storage
        let vault_cap = VaultCapability {
            storage_cap,
            vault_addr: signer::address_of(&vault_acc),
            vault_id,
        };
        add_coin<BaseCoin>(&vault_cap);

        // register vault with dao_storage
        dao_storage::register<VaultCoin<BaseCoin>>(&vault_acc);
        // return vault_cap to be stored in vaults table on Satay module
        vault_cap
    }

    // create a new CoinStore for CoinType
    public(friend) fun add_coin<CoinType>(
        vault_cap: &VaultCapability
    ) {
        let owner = account::create_signer_with_capability(&vault_cap.storage_cap);
        move_to(
            &owner,
            CoinStore<CoinType> { coin: coin::zero() }
        );
    }

    // user functions

    // deposit base_coin into the vault
    // called by satay module
    public(friend) fun deposit_as_user<BaseCoin>(
        user: &signer,
        vault_cap: &VaultCapability,
        base_coin: Coin<BaseCoin>
    ) acquires Vault, CoinStore, VaultCoinCaps {
        assert_base_coin_correct_for_vault_cap<BaseCoin>(vault_cap);
        // mint share amount
        let base_coin_amount = coin::value(&base_coin);
        let vault_coin_amount = calculate_share_amount_from_base_coin_amount<BaseCoin>(
            vault_cap,
            base_coin_amount
        );
        mint_vault_coin<BaseCoin>(user, vault_cap, vault_coin_amount);
        deposit(vault_cap, base_coin);

        // emit deposit event
        let vault = borrow_global_mut<Vault>(vault_cap.vault_addr);
        event::emit_event(&mut vault.deposit_event, DepositEvent {
            user_addr: signer::address_of(user),
            base_coin_amount,
            vault_coin_amount
        });
    }

    // withdraw base_coin from the vault
    // ensure that BaseCoin is the base coin type of the vault
    public(friend) fun withdraw_as_user<BaseCoin>(
        user: &signer,
        vault_cap: &VaultCapability,
        vault_coin_amount: u64
    ): Coin<BaseCoin> acquires CoinStore, Vault, VaultCoinCaps {
        assert_base_coin_correct_for_vault_cap<BaseCoin>(vault_cap);

        let base_coin_amount = calculate_base_coin_amount_from_share<BaseCoin>(
            vault_cap,
            vault_coin_amount
        );
        burn_vault_coins<BaseCoin>(user, vault_cap, vault_coin_amount);

        let vault = borrow_global_mut<Vault>(vault_cap.vault_addr);
        event::emit_event(&mut vault.withdraw_event, WithdrawEvent {
            user_addr: signer::address_of(user),
            base_coin_amount,
            vault_coin_amount,
        });

        withdraw<BaseCoin>(vault_cap, base_coin_amount)
    }

    // calculates amount of BaseCoin to return given an amount of VaultCoin to burn
    public fun calculate_base_coin_amount_from_share<BaseCoin>(
        vault_cap: &VaultCapability,
        share: u64
    ): u64 acquires Vault, CoinStore {
        let total_assets = total_assets<BaseCoin>(vault_cap);
        let share_total_supply_option = coin::supply<VaultCoin<BaseCoin>>();
        let share_total_supply = option::get_with_default<u128>(&share_total_supply_option, 0);
        math::mul_div_u128((total_assets as u128), (share as u128), share_total_supply)
    }

    public fun calculate_share_amount_from_base_coin_amount<BaseCoin>(
        vault_cap: &VaultCapability,
        base_coin_amount: u64,
    ): u64 acquires Vault, CoinStore {
        let total_base_coin_amount = total_assets<BaseCoin>(vault_cap);
        let total_supply = option::get_with_default<u128>(&coin::supply<VaultCoin<BaseCoin>>(), 0);

        if (total_supply != 0) {
            math::mul_div_u128(total_supply, (base_coin_amount as u128), (total_base_coin_amount as u128))
        } else {
            base_coin_amount
        }
    }

    // admin functions

    // update vault fee
    public(friend) fun update_fee(
        vault_cap: &VaultCapability,
        management_fee: u64,
        performance_fee: u64
    ) acquires Vault {
        assert_fee_amounts(management_fee, performance_fee);

        let vault = borrow_global_mut<Vault>(vault_cap.vault_addr);
        vault.management_fee = management_fee;
        vault.performance_fee = performance_fee;
    }

    // for strategies

    // approves strategy for vault
    public(friend) fun approve_strategy<StrategyType: drop, StrategyCoin>(
        vault_cap: &VaultCapability,
        debt_ratio: u64,
        _witness: &StrategyType
    ) acquires Vault {
        let vault = borrow_global_mut<Vault>(vault_cap.vault_addr);

        // check if the strategy's updated debt ratio is valid
        assert!(vault.debt_ratio + debt_ratio <= MAX_DEBT_RATIO_BPS, ERR_INVALID_DEBT_RATIO);

        // create a new strategy
        let vault_acc = account::create_signer_with_capability(&vault_cap.storage_cap);
        move_to(&vault_acc, VaultStrategy<StrategyType> {
            strategy_coin_type: type_info::type_of<StrategyCoin>(),
            debt_ratio,
            total_debt: 0,
            total_gain: 0,
            total_loss: 0,
            last_report: timestamp::now_seconds()
        });

        if(!has_coin<StrategyCoin>(vault_cap)){
            add_coin<StrategyCoin>(vault_cap);
        };

        // update vault params
        vault.debt_ratio = vault.debt_ratio + debt_ratio;
    }

    // update strategy debt ratio
    public(friend) fun update_strategy_debt_ratio<StrategyType: drop>(
        vault_cap: &VaultCapability,
        debt_ratio: u64,
        _witness: &StrategyType
    ): u64 acquires Vault, VaultStrategy {
        let vault = borrow_global_mut<Vault>(vault_cap.vault_addr);
        let strategy = borrow_global_mut<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        let old_debt_ratio = strategy.debt_ratio;

        vault.debt_ratio = vault.debt_ratio - old_debt_ratio + debt_ratio;
        strategy.debt_ratio = debt_ratio;

        // check if the strategy's updated debt ratio is valid
        assert!(vault.debt_ratio <= MAX_DEBT_RATIO_BPS, ERR_INVALID_DEBT_RATIO);

        debt_ratio
    }

    public(friend) fun deposit_profit<StrategyType: drop, BaseCoin>(
        vault_cap: &VaultCapability,
        base_coin: Coin<BaseCoin>,
        witness: &StrategyType
    ) acquires Vault, CoinStore, VaultStrategy, VaultCoinCaps {
        report_gain<StrategyType>(vault_cap, coin::value(&base_coin), witness);
        assess_fees<StrategyType, BaseCoin>(
            &base_coin,
            vault_cap,
            witness
        );
        deposit_base_coin(vault_cap, base_coin, witness);
    }

    public(friend) fun debt_payment<StrategyType: drop, BaseCoin>(
        vault_cap: &VaultCapability,
        base_coin: Coin<BaseCoin>,
        witness: &StrategyType
    ) acquires Vault, CoinStore, VaultStrategy {
        update_total_debt<StrategyType>(vault_cap, 0, coin::value(&base_coin), witness);
        deposit_base_coin(vault_cap, base_coin, witness);
    }

    // deposit base_coin into Vault from StrategyType
    fun deposit_base_coin<StrategyType: drop, BaseCoin>(
        vault_cap: &VaultCapability,
        base_coin: Coin<BaseCoin>,
        _witness: &StrategyType
    ) acquires CoinStore, Vault {
        assert_base_coin_correct_for_vault_cap<BaseCoin>(vault_cap);
        deposit(vault_cap, base_coin);
    }

    // withdraw base_coin from Vault to StrategyType
    public(friend) fun withdraw_base_coin<StrategyType: drop, BaseCoin>(
        vault_cap: &VaultCapability,
        amount: u64,
        witness: &StrategyType
    ): Coin<BaseCoin> acquires CoinStore, Vault, VaultStrategy {
        assert_base_coin_correct_for_vault_cap<BaseCoin>(vault_cap);

        assert!(credit_available<StrategyType, BaseCoin>(vault_cap) >= amount, ERR_INSUFFICIENT_CREDIT);

        update_total_debt(vault_cap, amount, 0, witness);

        withdraw(vault_cap, amount)
    }

    public(friend) fun deposit_strategy_coin<StrategyType: drop, StrategyCoin>(
        vault_cap: &VaultCapability,
        strategy_coin: Coin<StrategyCoin>,
        _witness: &StrategyType
    ) acquires CoinStore, VaultStrategy {
        assert_strategy_coin_correct_for_strategy_type<StrategyType, StrategyCoin>(vault_cap);
        deposit(vault_cap, strategy_coin);
    }

    public(friend) fun withdraw_strategy_coin<StrategyType: drop, StrategyCoin>(
        vault_cap: &VaultCapability,
        strategy_coin_amount: u64,
        _witness: &StrategyType
    ): Coin<StrategyCoin> acquires CoinStore, VaultStrategy {
        assert_strategy_coin_correct_for_strategy_type<StrategyType, StrategyCoin>(vault_cap);

        let withdraw_amount = strategy_coin_amount;
        let strategy_coin_balance = balance<StrategyCoin>(vault_cap);
        if (withdraw_amount > strategy_coin_balance) {
            withdraw_amount = strategy_coin_balance;
        };

        withdraw<StrategyCoin>(
            vault_cap,
            withdraw_amount
        )
    }

    // assesses fees when strategies return a profit
    fun assess_fees<StrategyType: drop, BaseCoin>(
        profit: &Coin<BaseCoin>,
        vault_cap: &VaultCapability,
        _witness: &StrategyType
    ) acquires VaultStrategy, Vault, CoinStore, VaultCoinCaps {
        let vault = borrow_global<Vault>(vault_cap.vault_addr);
        let strategy = borrow_global_mut<VaultStrategy<StrategyType>>(vault_cap.vault_addr);

        let duration = timestamp::now_seconds() - strategy.last_report;
        let gain = coin::value(profit);

        if (duration == 0 || gain == 0) {
            return
        };

        let management_fee_amount = math::mul_div_u128(
            math::mul_to_u128(strategy.total_debt, duration),
            (vault.management_fee as u128),
            math::mul_to_u128(MAX_DEBT_RATIO_BPS, SECS_PER_YEAR)
        );
        let performance_fee_amount = math::mul_div(gain, vault.performance_fee, MAX_DEBT_RATIO_BPS);

        let total_fee_amount = management_fee_amount + performance_fee_amount;
        if (total_fee_amount > gain) {
            total_fee_amount = gain;
        };

        // calculate amount of share tokens to mint
        let share_token_amount = calculate_share_amount_from_base_coin_amount<BaseCoin>(
            vault_cap,
            total_fee_amount
        );

        // mint vault coins to dao storage
        let caps = borrow_global<VaultCoinCaps<BaseCoin>>(vault_cap.vault_addr);
        let coins = coin::mint<VaultCoin<BaseCoin>>(share_token_amount, &caps.mint_cap);
        dao_storage::deposit<VaultCoin<BaseCoin>>(vault_cap.vault_addr, coins);
    }

    // report time for StrategyType
    public(friend) fun report_timestamp<StrategyType: drop>(
        vault_cap: &VaultCapability,
        _witness: &StrategyType
    ) acquires VaultStrategy {
        let strategy = borrow_global_mut<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        strategy.last_report = timestamp::now_seconds();
    }

    // report a gain for StrategyType
    fun report_gain<StrategyType: drop>(
        vault_cap: &VaultCapability,
        profit: u64,
        _witness: &StrategyType
    ) acquires VaultStrategy {
        let strategy = borrow_global_mut<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        strategy.total_gain = strategy.total_gain + profit;
    }

    // report a loss for StrategyType
    public(friend) fun report_loss<StrategyType: drop>(
        vault_cap: &VaultCapability,
        loss: u64,
        _witness: &StrategyType
    ) acquires Vault, VaultStrategy {
        let vault = borrow_global_mut<Vault>(vault_cap.vault_addr);
        let strategy = borrow_global_mut<VaultStrategy<StrategyType>>(vault_cap.vault_addr);

        if (vault.debt_ratio != 0) {
            let ratio_change = math::mul_div(loss, vault.debt_ratio, vault.total_debt);
            if (ratio_change > strategy.debt_ratio) {
                ratio_change = strategy.debt_ratio;
            };
            strategy.debt_ratio = strategy.debt_ratio - ratio_change;
            vault.debt_ratio = vault.debt_ratio - ratio_change;
        };

        strategy.total_loss = strategy.total_loss + loss;
        strategy.total_debt = strategy.total_debt - loss;
        vault.total_debt = vault.total_debt - loss;
    }

    // getters

    // Vault fields

    public fun get_base_coin_type(
        vault_cap: &VaultCapability
    ): TypeInfo acquires Vault {
        let vault = borrow_global<Vault>(vault_cap.vault_addr);
        vault.base_coin_type
    }

    public fun get_base_coin_decimals(
        vault_cap: &VaultCapability
    ): u8 acquires Vault {
        let vault = borrow_global<Vault>(vault_cap.vault_addr);
        vault.base_coin_decimals
    }

    public fun get_fees(
        vault_cap: &VaultCapability
    ): (u64, u64) acquires Vault {
        let vault = borrow_global<Vault>(vault_cap.vault_addr);
        (vault.management_fee, vault.performance_fee)
    }

    public fun get_debt_ratio(
        vault_cap: &VaultCapability
    ): u64 acquires Vault {
        let vault = borrow_global<Vault>(vault_cap.vault_addr);
        vault.debt_ratio
    }

    public fun get_total_debt(
        vault_cap: &VaultCapability
    ): u64 acquires Vault {
        let vault = borrow_global<Vault>(vault_cap.vault_addr);
        vault.total_debt
    }

    // check if vault_id matches the vault_id of vault_cap
    public fun vault_cap_has_id(
        vault_cap: &VaultCapability,
        vault_id: u64
    ): bool {
        vault_cap.vault_id == vault_id
    }

    // check the CoinType balance of the vault
    public fun balance<CoinType>(
        vault_cap: &VaultCapability
    ): u64 acquires CoinStore {
        let store = borrow_global_mut<CoinStore<CoinType>>(vault_cap.vault_addr);
        coin::value(&store.coin)
    }

    // gets the total assets of the vault, including the stored coins and debt with strategies
    public fun total_assets<BaseCoin>(
        vault_cap: &VaultCapability
    ): u64 acquires Vault, CoinStore {
        assert_base_coin_correct_for_vault_cap<BaseCoin>(vault_cap);
        let vault = borrow_global<Vault>(vault_cap.vault_addr);

        let balance = balance<BaseCoin>(vault_cap);
        vault.total_debt + balance
    }

    // check if a vault has a CoinStore for CoinType
    public fun has_coin<CoinType>(
        vault_cap: &VaultCapability
    ): bool {
        exists<CoinStore<CoinType>>(vault_cap.vault_addr)
    }

    // gets vault address from vault_cap
    public fun get_vault_addr(
        vault_cap: &VaultCapability
    ): address {
        vault_cap.vault_addr
    }

    // strategy fields

    // check if vault of vault_cap has StrategyType
    public fun has_strategy<StrategyType: drop>(
        vault_cap: &VaultCapability
    ): bool {
        let vault_acc = account::create_signer_with_capability(&vault_cap.storage_cap);
        exists<VaultStrategy<StrategyType>>(signer::address_of(&vault_acc))
    }

    // gets amount of tokens in vault StrategyType has access to as a credit line
    public fun credit_available<StrategyType: drop, BaseCoin>(
        vault_cap: &VaultCapability
    ): u64 acquires Vault, VaultStrategy, CoinStore {
        let vault = borrow_global<Vault>(vault_cap.vault_addr);
        assert!(vault.base_coin_type == type_info::type_of<BaseCoin>(), ERR_COIN);

        let vault_debt_ratio = vault.debt_ratio;
        let vault_total_debt = vault.total_debt;
        let vault_total_assets = total_assets<BaseCoin>(vault_cap);
        let vault_debt_limit = math::mul_div(vault_debt_ratio, vault_total_assets, MAX_DEBT_RATIO_BPS);

        let strategy = borrow_global<VaultStrategy<StrategyType>>(vault_cap.vault_addr);

        let strategy_debt_limit = math::mul_div(strategy.debt_ratio, vault_total_assets, MAX_DEBT_RATIO_BPS);
        let strategy_total_debt = strategy.total_debt;

        if (strategy_debt_limit <= strategy_total_debt || vault_debt_limit <= vault_total_debt) {
            return 0
        };

        let strategy_credit_available = strategy_debt_limit - strategy_total_debt;
        let store = borrow_global<CoinStore<BaseCoin>>(vault_cap.vault_addr);
        let balance = coin::value(&store.coin);

        if (strategy_credit_available > (vault_debt_limit - vault_total_debt)) {
            strategy_credit_available = vault_debt_limit - vault_total_debt;
        };
        if (strategy_credit_available > balance) {
            strategy_credit_available = balance;
        };

        strategy_credit_available
    }

    // determines if StrategyType is past its debt limit and if any tokens should be withdrawn to the Vault
    // returns the amount of strategy debt over its limit
    public fun debt_out_standing<StrategyType: drop, BaseCoin>(
        vault_cap: &VaultCapability
    ): u64 acquires Vault, VaultStrategy, CoinStore {
        let vault = borrow_global<Vault>(vault_cap.vault_addr);
        assert!(vault.base_coin_type == type_info::type_of<BaseCoin>(), ERR_COIN);
        let strategy = borrow_global<VaultStrategy<StrategyType>>(vault_cap.vault_addr);

        if (vault.debt_ratio == 0) {
            return strategy.total_debt
        };

        let vault_total_assets = total_assets<BaseCoin>(vault_cap);
        let strategy_debt_limit = math::mul_div(strategy.debt_ratio, vault_total_assets, MAX_DEBT_RATIO_BPS);
        let strategy_total_debt = strategy.total_debt;

        if (strategy_total_debt <= strategy_debt_limit) {
            0
        } else {
            strategy_total_debt - strategy_debt_limit
        }
    }

    // gets the total debt for a given StrategyType
    public fun total_debt<StrategyType: drop>(
        vault_cap: &VaultCapability
    ): u64 acquires VaultStrategy {
        let strategy = borrow_global<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        strategy.total_debt
    }

    public fun total_gain<StrategyType: drop>(
        vault_cap: &VaultCapability
    ): u64 acquires VaultStrategy {
        let strategy = borrow_global<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        strategy.total_gain
    }

    public fun total_loss<StrategyType: drop>(
        vault_cap: &VaultCapability
    ): u64 acquires VaultStrategy {
        let strategy = borrow_global<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        strategy.total_loss
    }

    // gets the debt ratio for a given StrategyType
    public fun debt_ratio<StrategyType: drop>(
        vault_cap: &VaultCapability
    ): u64 acquires VaultStrategy {
        let strategy = borrow_global<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        strategy.debt_ratio
    }

    // gets the last report for a given StrategyType
    public fun last_report<StrategyType: drop>(
        vault_cap: &VaultCapability
    ): u64 acquires VaultStrategy {
        let strategy = borrow_global<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        strategy.last_report
    }

    public fun get_strategy_coin_type<StrategyType: drop>(
        vault_cap: &VaultCapability
    ): TypeInfo acquires VaultStrategy {
        let strategy = borrow_global_mut<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        strategy.strategy_coin_type
    }

    // user getters

    // check if user_address has store for VaultCoin
    public fun is_vault_coin_registered<CoinType>(
        user_address: address
    ): bool {
        coin::is_account_registered<VaultCoin<CoinType>>(user_address)
    }

    // gets balance of vault_coin for a particular user_address
    public fun vault_coin_balance<CoinType>(
        user_address: address
    ): u64 {
        coin::balance<VaultCoin<CoinType>>(user_address)
    }

    // gets the amount of BaseCoin a user to which user has claim
    public fun get_user_amount<BaseCoin>(
        vault_cap: &VaultCapability,
        user_addr: address
    ): u64 acquires Vault, CoinStore {
        let total_assets = total_assets<BaseCoin>(vault_cap);
        let user_share_amount = coin::balance<VaultCoin<BaseCoin>>(user_addr);
        let share_total_supply_option = coin::supply<VaultCoin<BaseCoin>>();
        let share_total_supply = option::get_with_default<u128>(&share_total_supply_option, 0);
        math::mul_div_u128((total_assets as u128), (user_share_amount as u128), share_total_supply)
    }

    public fun assert_base_coin_correct_for_vault_cap<BaseCoin> (
        vault_cap: &VaultCapability
    ) acquires Vault {
        let vault = borrow_global<Vault>(vault_cap.vault_addr);
        assert!(vault.base_coin_type == type_info::type_of<BaseCoin>(), ERR_COIN);
    }

    // private functions

    // deposit coin of CoinType into the vault
    fun deposit<CoinType>(
        vault_cap: &VaultCapability,
        coin: Coin<CoinType>
    ) acquires CoinStore {
        let store = borrow_global_mut<CoinStore<CoinType>>(vault_cap.vault_addr);
        coin::merge(&mut store.coin, coin);
    }

    // withdraw coin of CoinType from the vault
    fun withdraw<CoinType>(
        vault_cap: &VaultCapability,
        amount: u64
    ): Coin<CoinType> acquires CoinStore {
        let store = borrow_global_mut<CoinStore<CoinType>>(vault_cap.vault_addr);
        coin::extract(&mut store.coin, amount)
    }

    // mint vault coin shares to user
    // called by deposit_as_user
    fun mint_vault_coin<BaseCoin>(
        user: &signer,
        vault_cap: &VaultCapability,
        amount: u64
    ) acquires VaultCoinCaps {
        let caps = borrow_global<VaultCoinCaps<BaseCoin>>(vault_cap.vault_addr);
        let coins = coin::mint<VaultCoin<BaseCoin>>(amount, &caps.mint_cap);
        if(!is_vault_coin_registered<BaseCoin>(signer::address_of(user))){
            coin::register<VaultCoin<BaseCoin>>(user);
        };
        coin::deposit(signer::address_of(user), coins);
    }

    // burn vault coin from user
    // called by withdraw_as_user
    fun burn_vault_coins<BaseCoin>(
        user: &signer,
        vault_cap: &VaultCapability,
        amount: u64
    ) acquires VaultCoinCaps {
        let caps = borrow_global<VaultCoinCaps<BaseCoin>>(vault_cap.vault_addr);
        coin::burn(coin::withdraw<VaultCoin<BaseCoin>>(user, amount), &caps.burn_cap);
    }

    // update vault and strategy total_debt, given credit and debt_payment amounts
    fun update_total_debt<StrategyType: drop>(
        vault_cap: &VaultCapability,
        credit: u64,
        debt_payment: u64,
        _witness: &StrategyType
    ) acquires Vault, VaultStrategy {
        let vault = borrow_global_mut<Vault>(vault_cap.vault_addr);
        let strategy = borrow_global_mut<VaultStrategy<StrategyType>>(vault_cap.vault_addr);

        vault.total_debt = vault.total_debt + credit - debt_payment;
        strategy.total_debt = strategy.total_debt + credit - debt_payment;
    }

    fun assert_strategy_coin_correct_for_strategy_type<StrategyType: drop, StrategyCoin> (
        vault_cap: &VaultCapability
    ) acquires VaultStrategy {
        let strategy = borrow_global<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        assert!(strategy.strategy_coin_type == type_info::type_of<StrategyCoin>(), ERR_COIN);
    }

    fun assert_fee_amounts(
        management_fee: u64,
        performance_fee: u64
    ) {
        assert!(management_fee <= MAX_MANAGEMENT_FEE && performance_fee <= MAX_PERFORMANCE_FEE, ERR_INVALID_FEE);
    }

    // test functions

    #[test_only]
    public fun new_test<BaseCoin>(
        governance: &signer, 
        seed: vector<u8>, 
        vault_id: u64,
        management_fee: u64,
        performance_fee: u64
    ): VaultCapability {
        new<BaseCoin>(
            governance,
            seed,
            vault_id,
            management_fee,
            performance_fee
        )
    }

    #[test_only]
    public fun test_deposit_as_user<BaseCoin>(
        user: &signer,
        vault_cap: &VaultCapability,
        base_coin: Coin<BaseCoin>
    ) acquires Vault, CoinStore, VaultCoinCaps {
        deposit_as_user(user, vault_cap, base_coin);
    }

    #[test_only]
    public fun test_withdraw_as_user<BaseCoin>(
        user: &signer,
        vault_cap: &VaultCapability,
        amount: u64
    ) : Coin<BaseCoin> acquires Vault, CoinStore, VaultCoinCaps {
        withdraw_as_user(user, vault_cap, amount)
    }

    #[test_only]
    public fun test_deposit<CoinType>(
        vault_cap: &VaultCapability,
        coins: Coin<CoinType>
    ) acquires CoinStore {
        deposit(vault_cap, coins);
    }

    #[test_only]
    public fun test_withdraw<CoinType>(
        vault_cap: &VaultCapability,
        amount: u64
    ) : Coin<CoinType> acquires CoinStore {
        withdraw<CoinType>(vault_cap, amount)
    }

    #[test_only]
    public fun test_approve_strategy<StrategyType: drop, StrategyCoin>(
        vault_cap: &VaultCapability,
        debt_ratio: u64,
        witness: StrategyType
    ) acquires Vault {
        approve_strategy<StrategyType, StrategyCoin>(
            vault_cap,
            debt_ratio,
            &witness
        );
    }

    #[test_only]
    public fun test_update_fee(
        vault_cap: &VaultCapability,
        management_fee: u64,
        performance_fee: u64
    ) acquires Vault {
        update_fee(vault_cap, management_fee, performance_fee);
    }

    #[test_only]
    public fun test_deposit_base_coin<StrategyType: drop, BaseCoin>(
        vault_cap: &VaultCapability,
        base_coin: Coin<BaseCoin>,
        witness: &StrategyType
    ) acquires Vault, CoinStore {
        deposit_base_coin<StrategyType, BaseCoin>(vault_cap, base_coin, witness);
    }

    #[test_only]
    public fun test_debt_payment<StrategyType: drop, BaseCoin>(
        vault_cap: &VaultCapability,
        debt_payment: Coin<BaseCoin>,
        witness: &StrategyType
    ) acquires Vault, CoinStore, VaultStrategy {
        debt_payment<StrategyType, BaseCoin>(vault_cap, debt_payment, witness);
    }

    #[test_only]
    public fun test_deposit_profit<StrategyType: drop, BaseCoin>(
        vault_cap: &VaultCapability,
        profit: Coin<BaseCoin>,
        witness: &StrategyType
    ) acquires Vault, CoinStore, VaultStrategy, VaultCoinCaps {
        deposit_profit<StrategyType, BaseCoin>(vault_cap, profit, witness);
    }

    #[test_only]
    public fun test_withdraw_base_coin<StrategyType: drop, BaseCoin>(
        vault_cap: &VaultCapability,
        amount: u64,
        witness: &StrategyType
    ) : Coin<BaseCoin> acquires Vault, CoinStore, VaultStrategy {
        withdraw_base_coin<StrategyType, BaseCoin>(vault_cap, amount, witness)
    }

    #[test_only]
    public fun test_deposit_strategy_coin<StrategyType: drop, StrategyCoin>(
        vault_cap: &VaultCapability,
        strategy_coin: Coin<StrategyCoin>,
        witness: &StrategyType
    ) acquires CoinStore, VaultStrategy {
        deposit_strategy_coin<StrategyType, StrategyCoin>(vault_cap, strategy_coin, witness);
    }

    #[test_only]
    public fun test_withdraw_strategy_coin<StrategyType: drop, StrategyCoin>(
        vault_cap: &VaultCapability,
        amount: u64,
        witness: &StrategyType
    ) : Coin<StrategyCoin> acquires CoinStore, VaultStrategy {
        withdraw_strategy_coin<StrategyType, StrategyCoin>(vault_cap, amount, witness)
    }

    #[test_only]
    public fun test_update_strategy_debt_ratio<StrategyType: drop>(
        vault_cap: &VaultCapability,
        debt_ratio: u64,
        witness: &StrategyType
    ) acquires VaultStrategy, Vault {
        update_strategy_debt_ratio<StrategyType>(
            vault_cap,
            debt_ratio,
            witness
        );
    }

    #[test_only]
    public fun test_assess_fees<StrategyType: drop, BaseCoin>(
        profit: &Coin<BaseCoin>,
        vault_cap: &VaultCapability,
        witness: &StrategyType
    ) acquires Vault, VaultStrategy, CoinStore, VaultCoinCaps {
        assess_fees<StrategyType, BaseCoin>(profit, vault_cap, witness);
    }

    #[test_only]
    public fun test_update_total_debt<StrategyType: drop>(
        vault_cap: &VaultCapability,
        credit: u64,
        debt_payment: u64,
        witness: &StrategyType
    ) acquires Vault, VaultStrategy {
        update_total_debt<StrategyType>(vault_cap, credit, debt_payment, witness);
    }

    #[test_only]
    public fun test_report_timestamp<StrategyType: drop>(
        vault_cap: &VaultCapability,
        witness: &StrategyType
    ) acquires VaultStrategy {
        report_timestamp<StrategyType>(vault_cap, witness);
    }

    #[test_only]
    public fun test_report_gain<StrategyType: drop>(
        vault_cap: &VaultCapability,
        profit: u64,
        witness: &StrategyType
    ) acquires VaultStrategy {
        report_gain<StrategyType>(vault_cap, profit, witness);
    }

    #[test_only]
    public fun test_report_loss<StrategyType: drop>(
        vault_cap: &VaultCapability,
        loss: u64,
        witness: &StrategyType
    ) acquires Vault, VaultStrategy {
        report_loss<StrategyType>(vault_cap, loss, witness);
    }





}