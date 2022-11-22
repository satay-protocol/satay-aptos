module satay::vault {
    use std::signer;
    use std::string;
    use std::option;

    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability, FreezeCapability};
    use aptos_std::type_info::{TypeInfo};
    use aptos_std::type_info;
    use satay::dao_storage;
    use aptos_framework::timestamp;
    use liquidswap::math;

    friend satay::satay;
    friend satay::base_strategy;

    const MAX_BPS: u64 = 10000; // 100%
    const MAX_MANAGEMENT_FEE: u64 = 5000; // 30%
    const MAX_PERFORMANCE_FEE: u64 = 5000; // 30%
    const SECS_PER_YEAR: u64 = 31556952; // 365.2425 days

    const ERR_NO_USER_POSITION: u64 = 101;
    const ERR_NOT_ENOUGH_USER_POSITION: u64 = 102;
    const ERR_COIN: u64 = 103;
    const ERR_NOT_REGISTERED_USER: u64 = 104;
    const ERR_STRATEGY_NOT_REGISTERED: u64 = 105;
    const ERR_INVALID_DEBT_RATIO: u64 = 106;
    const ERR_INVALID_FEE: u64 = 107;

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
    }

    struct VaultCapability has store, drop {
        storage_cap: SignerCapability,
        vault_id: u64,
        vault_addr: address,
    }

    struct Caps<phantom CoinType> has key {
        mint_cap: MintCapability<CoinType>,
        freeze_cap: FreezeCapability<CoinType>,
        burn_cap: BurnCapability<CoinType>
    }

    struct VaultCoin<phantom BaseCoin> has key {}

    struct VaultStrategy<phantom StrategyType> has key, store {
        strategy_coin_type: TypeInfo,
        debt_ratio: u64,
        total_debt: u64,
        total_gain: u64,
        total_loss: u64,
        last_report: u64,
        max_report_delay: u64,
        force_harvest_trigger_once: bool,
        credit_threshold: u64
    }

    // for satay

    // create new vault with BaseCoin as its base coin type
    public(friend) fun new<BaseCoin>(
        vault_owner: &signer, 
        seed: vector<u8>, 
        vault_id: u64,
        management_fee: u64,
        performance_fee: u64
    ): VaultCapability {
        assert!(management_fee <= MAX_MANAGEMENT_FEE && performance_fee <= MAX_PERFORMANCE_FEE, ERR_INVALID_FEE);

        // create a resource account for the vault managed by the sender
        let (vault_acc, storage_cap) = account::create_resource_account(vault_owner, seed);

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
        };
        move_to(&vault_acc, vault);

        // initialize vault coin and move vault caps to vault owner
        let (burn_cap,
            freeze_cap,
            mint_cap
        ) = coin::initialize<VaultCoin<BaseCoin>>(
            vault_owner,
            string::utf8(b"Vault Token"),
            string::utf8(b"Vault"),
            8,
            true
        );
        move_to(&vault_acc, Caps<VaultCoin<BaseCoin>> { mint_cap, freeze_cap, burn_cap});

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

    // deposit base_coin into the vault
    // called by satay module
    public(friend) fun deposit_as_user<BaseCoin>(
        user: &signer,
        vault_cap: &VaultCapability,
        base_coin: Coin<BaseCoin>
    ) acquires Vault, CoinStore, Caps {
        let vault = borrow_global_mut<Vault>(vault_cap.vault_addr);

        // ensure that BaseCoin is the base coin type of the vault
        assert!(vault.base_coin_type == type_info::type_of<BaseCoin>(), ERR_COIN);

        // mint share amount
        let share_token_amount = coin::value(&base_coin);
        let total_base_coin_amount = total_assets<BaseCoin>(vault_cap);
        let total_supply = option::get_with_default<u128>(&coin::supply<VaultCoin<BaseCoin>>(), 0);
        if (total_supply != 0) {
            share_token_amount = (total_supply as u64) * coin::value(&base_coin) / total_base_coin_amount;
        };
        mint_vault_coin<BaseCoin>(user, vault_cap, share_token_amount);
        deposit(vault_cap, base_coin);
    }

    // withdraw base_coin from the vault
    // ensure that BaseCoin is the base coin type of the vault
    public(friend) fun withdraw_as_user<BaseCoin>(
        user: &signer,
        vault_cap: &VaultCapability,
        amount: u64
    ): Coin<BaseCoin> acquires CoinStore, Vault, Caps {
        let vault = borrow_global_mut<Vault>(vault_cap.vault_addr);

        assert!(vault.base_coin_type == type_info::type_of<BaseCoin>(), ERR_COIN);

        let total_supply = option::get_with_default<u128>(&coin::supply<VaultCoin<BaseCoin>>(), 0);
        let withdraw_amount = total_assets<BaseCoin>(vault_cap) * amount / (total_supply as u64);
        burn_vault_coins<BaseCoin>(user, vault_cap, amount);
        withdraw<BaseCoin>(vault_cap, withdraw_amount)
    }

    // approves strategy for vault
    public(friend) fun approve_strategy<StrategyType: drop>(
        vault_cap: &VaultCapability,
        strategy_coin_type: TypeInfo,
        debt_ratio: u64
    ) acquires Vault {
        let vault = borrow_global_mut<Vault>(vault_cap.vault_addr);

        // check if the strategy's updated debt ratio is valid
        assert!(vault.debt_ratio + debt_ratio <= MAX_BPS, ERR_INVALID_DEBT_RATIO);

        // create a new strategy
        let vault_acc = account::create_signer_with_capability(&vault_cap.storage_cap);
        move_to(&vault_acc, VaultStrategy<StrategyType> { 
            strategy_coin_type,
            debt_ratio,
            total_debt: 0,
            total_gain: 0,
            total_loss: 0,
            last_report: timestamp::now_seconds(),
            max_report_delay: 30 * 24 * 3600, // 30 days
            force_harvest_trigger_once: false,
            credit_threshold: 1000000 * math::pow_10(vault.base_coin_decimals)
        });

        // update vault params
        vault.debt_ratio = vault.debt_ratio + debt_ratio;
    }

    // update vault fee
    public(friend) fun update_fee(
        vault_cap: &VaultCapability,
        management_fee: u64,
        performance_fee: u64
    ) acquires Vault {
        assert!(management_fee <= MAX_MANAGEMENT_FEE && performance_fee <= MAX_PERFORMANCE_FEE, ERR_INVALID_FEE);

        let vault = borrow_global_mut<Vault>(vault_cap.vault_addr);
        vault.management_fee = management_fee;
        vault.performance_fee = performance_fee;
    }

    // for strategies

    // update strategy debt ratio
    public(friend) fun update_strategy_debt_ratio<StrategyType: drop>(
        vault_cap: &VaultCapability,
        debt_ratio: u64
    ): u64 acquires Vault, VaultStrategy {
        let vault = borrow_global_mut<Vault>(vault_cap.vault_addr);
        let strategy = borrow_global_mut<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        let old_debt_ratio = strategy.debt_ratio;

        vault.debt_ratio = vault.debt_ratio - old_debt_ratio + debt_ratio;
        strategy.debt_ratio = debt_ratio;

        // check if the strategy's updated debt ratio is valid
        assert!(vault.debt_ratio <= MAX_BPS, ERR_INVALID_DEBT_RATIO);

        old_debt_ratio
    }

    // update strategy max report delay
    public(friend) fun update_strategy_max_report_delay<StrategyType: drop>(
        vault_cap: &VaultCapability,
        max_report_delay: u64
    ) acquires VaultStrategy {
        let strategy = borrow_global_mut<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        strategy.max_report_delay = max_report_delay;
    }

    // update strategy credit threshold
    public(friend) fun update_strategy_credit_threshold<StrategyType: drop>(
        vault_cap: &VaultCapability,
        credit_threshold: u64
    ) acquires VaultStrategy {
        let strategy = borrow_global_mut<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        strategy.credit_threshold = credit_threshold;
    }

    // set strategy force harvest trigger once
    public(friend) fun set_strategy_force_harvest_trigger_once<StrategyType: drop>(
        vault_cap: &VaultCapability
    ) acquires VaultStrategy {
        let strategy = borrow_global_mut<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        strategy.force_harvest_trigger_once = true;
    }

    // create a new CoinStore for CoinType
    public(friend) fun add_coin<CoinType>(vault_cap: &VaultCapability) {
        let owner = account::create_signer_with_capability(&vault_cap.storage_cap);
        move_to(
            &owner,
            CoinStore<CoinType> { coin: coin::zero() }
        );
    }

    // deposit coin of CoinType into the vault
    public(friend) fun deposit<CoinType>(vault_cap: &VaultCapability, coin: Coin<CoinType>) acquires CoinStore {
        let store = borrow_global_mut<CoinStore<CoinType>>(vault_cap.vault_addr);
        coin::merge(&mut store.coin, coin);
    }

    // withdraw coin of CoinType from the vault
    public(friend) fun withdraw<CoinType>(vault_cap: &VaultCapability, amount: u64): Coin<CoinType> acquires CoinStore {
        let store = borrow_global_mut<CoinStore<CoinType>>(vault_cap.vault_addr);
        coin::extract(&mut store.coin, amount)
    }

    // assesses fees when strategies return a profit
    public(friend) fun assess_fees<StrategyType: drop, BaseCoin>(
        gain: u64,
        delegated_assets: u64,
        vault_cap: &VaultCapability,
        _witness: StrategyType
    ) acquires VaultStrategy, Vault, CoinStore, Caps {
        let vault = borrow_global<Vault>(vault_cap.vault_addr);
        let strategy = borrow_global_mut<VaultStrategy<StrategyType>>(vault_cap.vault_addr);

        let duration = timestamp::now_seconds() - strategy.last_report;

        if (duration == 0 || gain == 0) {
            return
        };

        let management_fee_amount = (
            (
                (strategy.total_debt - delegated_assets)
                    * duration
                    * vault.management_fee
            )
                / MAX_BPS
                / SECS_PER_YEAR
        );
        let performance_fee_amount = gain * vault.performance_fee / MAX_BPS;

        let total_fee_amount = management_fee_amount + performance_fee_amount;
        if (total_fee_amount > gain) {
            total_fee_amount = gain;
        };

        // calculate amount of share tokens to mint
        let share_token_amount = 0;
        let total_supply = option::get_with_default<u128>(&coin::supply<VaultCoin<BaseCoin>>(), 0);
        if (total_supply != 0) {
            share_token_amount =  total_fee_amount * (total_supply as u64) / total_assets<BaseCoin>(vault_cap);
        };

        // mint vault coins to dao storage
        let caps = borrow_global<Caps<VaultCoin<BaseCoin>>>(vault_cap.vault_addr);
        let coins = coin::mint<VaultCoin<BaseCoin>>(share_token_amount, &caps.mint_cap);
        dao_storage::deposit<VaultCoin<BaseCoin>>(vault_cap.vault_addr, coins);
    }

    // update vault and strategy total_debt, given credit and debt_payment amounts
    public(friend) fun update_total_debt<StrategyType: drop>(vault_cap: &mut VaultCapability, credit: u64, debt_payment: u64) acquires Vault, VaultStrategy {
        let vault = borrow_global_mut<Vault>(vault_cap.vault_addr);
        let strategy = borrow_global_mut<VaultStrategy<StrategyType>>(vault_cap.vault_addr);

        vault.total_debt = vault.total_debt + credit - debt_payment;
        strategy.total_debt = strategy.total_debt + credit - debt_payment;
    }

    // report a gain for StrategyType
    public(friend) fun report_gain<StrategyType: drop>(vault_cap: &mut VaultCapability, profit: u64) acquires VaultStrategy {
        let strategy = borrow_global_mut<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        strategy.total_gain = strategy.total_gain + profit;
    }

    // report a loss for StrategyType
    public(friend) fun report_loss<StrategyType: drop>(vault_cap: &mut VaultCapability, loss: u64) acquires Vault, VaultStrategy {
        let vault = borrow_global_mut<Vault>(vault_cap.vault_addr);
        let strategy = borrow_global_mut<VaultStrategy<StrategyType>>(vault_cap.vault_addr);

        if (vault.debt_ratio != 0) {
            let ratio_change = loss * vault.debt_ratio / vault.total_debt;
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

    // report time for StrategyType
    public(friend) fun report_timestamp<StrategyType: drop>(vault_cap: &mut VaultCapability) acquires VaultStrategy {
        let strategy = borrow_global_mut<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        strategy.last_report = timestamp::now_seconds();
        strategy.force_harvest_trigger_once = false;
    }

    // getters

    // check if a vault has a CoinStore for CoinType
    public fun has_coin<CoinType>(vault_cap: &VaultCapability): bool {
        exists<CoinStore<CoinType>>(vault_cap.vault_addr)
    }

    // check if vault of vault_cap has StrategyType
    public fun has_strategy<StrategyType: drop>(vault_cap: &VaultCapability) : bool {
        let vault_acc = account::create_signer_with_capability(&vault_cap.storage_cap);
        exists<VaultStrategy<StrategyType>>(signer::address_of(&vault_acc))
    }

    // check if vault_id matches the vault_id of vault_cap
    public fun vault_cap_has_id(vault_cap: &VaultCapability, vault_id: u64): bool {
        vault_cap.vault_id == vault_id
    }

    // gets the total assets of the vault, including the stored coins and debt with strategies
    public fun total_assets<CoinType>(vault_cap: &VaultCapability): u64 acquires Vault, CoinStore {
        let vault = borrow_global<Vault>(vault_cap.vault_addr);

        let store = borrow_global<CoinStore<CoinType>>(vault_cap.vault_addr);
        vault.total_debt + coin::value(&store.coin)
    }

    // gets amount of tokens in vault StrategyType has access to as a credit line
    public fun credit_available<StrategyType: drop, CoinType>(vault_cap: &VaultCapability): u64 acquires Vault, VaultStrategy, CoinStore {
        let vault = borrow_global<Vault>(vault_cap.vault_addr);
        let strategy = borrow_global<VaultStrategy<StrategyType>>(vault_cap.vault_addr);

        let vault_debt_ratio = vault.debt_ratio;
        let vault_total_debt = vault.total_debt;
        let vault_total_assets = total_assets<CoinType>(vault_cap);
        let vault_debt_limit = vault_debt_ratio * vault_total_assets / MAX_BPS;
        let strategy_debt_limit = strategy.debt_ratio * vault_total_assets / MAX_BPS;
        let strategy_total_debt = strategy.total_debt;

        if (strategy_debt_limit <= strategy_total_debt || vault_debt_limit <= vault_total_debt) {
            return 0
        };

        let strategy_credit_available = strategy_debt_limit - strategy_total_debt;
        let store = borrow_global<CoinStore<CoinType>>(vault_cap.vault_addr);
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
    public fun debt_out_standing<StrategyType: drop, CoinType>(vault_cap: &VaultCapability): u64 acquires Vault, VaultStrategy, CoinStore {
        let vault = borrow_global<Vault>(vault_cap.vault_addr);
        let strategy = borrow_global<VaultStrategy<StrategyType>>(vault_cap.vault_addr);

        if (vault.debt_ratio == 0) {
            return strategy.total_debt
        };

        let vault_total_assets = total_assets<CoinType>(vault_cap);
        let strategy_debt_limit = strategy.debt_ratio * vault_total_assets / MAX_BPS;
        let strategy_total_debt = strategy.total_debt;

        if (strategy_total_debt <= strategy_debt_limit) {
            0
        } else {
            strategy_total_debt - strategy_debt_limit
        }
    }

    // gets the total debt for a given StrategyType
    public fun total_debt<StrategyType: drop>(vault_cap: &VaultCapability) : u64 acquires VaultStrategy {
        let strategy = borrow_global<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        strategy.total_debt
    }

    // gets the debt ratio for a given StrategyType
    public fun debt_ratio<StrategyType: drop>(vault_cap: &VaultCapability) : u64 acquires VaultStrategy {
        let strategy = borrow_global<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        strategy.debt_ratio
    }

    // gets the last report for a given StrategyType
    public fun last_report<StrategyType: drop>(vault_cap: &VaultCapability) : u64 acquires VaultStrategy {
        let strategy = borrow_global<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        strategy.last_report
    }

    // gets the max report delay for a given StrategyType
    public fun max_report_delay<StrategyType: drop>(vault_cap: &VaultCapability) : u64 acquires VaultStrategy {
        let strategy = borrow_global<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        strategy.max_report_delay
    }

    // gets the force harvest trigger once for a given StrategyType
    public fun force_harvest_trigger_once<StrategyType: drop>(vault_cap: &VaultCapability) : bool acquires VaultStrategy {
        let strategy = borrow_global<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        strategy.force_harvest_trigger_once
    }

    // gets the credit threshold for a given StrategyType
    public fun credit_threshold<StrategyType: drop>(vault_cap: &VaultCapability) : u64 acquires VaultStrategy {
        let strategy = borrow_global<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        strategy.credit_threshold
    }

    // check the CoinType balance of the vault
    public fun balance<CoinType>(vault_cap: &VaultCapability): u64 acquires CoinStore {
        let store = borrow_global_mut<CoinStore<CoinType>>(vault_cap.vault_addr);
        coin::value(&store.coin)
    }

    // check if user_address has store for VaultCoin
    public fun is_vault_coin_registered<CoinType>(user_address : address): bool {
        coin::is_account_registered<VaultCoin<CoinType>>(user_address)
    }

    // gets balance of vault_coin for a particular user_address
    public fun vault_coin_balance<CoinType>(user_address : address): u64 {
        coin::balance<VaultCoin<CoinType>>(user_address)
    }

    // gets the amount of BaseCoin a user to which user has claim
    public fun get_user_amount<BaseCoin>(vault_cap: &VaultCapability, user_addr: address) : u64 acquires Vault, CoinStore {
        let total_assets = total_assets<BaseCoin>(vault_cap);
        let user_share_amount = coin::balance<VaultCoin<BaseCoin>>(user_addr);
        let share_total_supply_option = coin::supply<VaultCoin<BaseCoin>>();
        let share_total_supply = option::get_with_default<u128>(&share_total_supply_option, 0);
        total_assets * user_share_amount / (share_total_supply as u64)
    }

    // calculates amount of BaseCoin to return given an amount of VaultCoin to burn
    public fun calculate_base_coin_amount_from_share<BaseCoin>(vault_cap: &VaultCapability, share: u64) : u64 acquires Vault, CoinStore {
        let total_assets = total_assets<BaseCoin>(vault_cap);
        let share_total_supply_option = coin::supply<VaultCoin<BaseCoin>>();
        let share_total_supply = option::get_with_default<u128>(&share_total_supply_option, 0);
        total_assets * share / (share_total_supply as u64)
    }

    // calculates proportion of StrategyCoin to liquidate given an amount of VaultCoin
    public fun calculate_strategy_coin_amount_from_share<BaseCoin, StrategyCoin>(
        vault_cap: &VaultCapability,
        share: u64
    ) : u64 acquires CoinStore {
        let total_assets = balance<StrategyCoin>(vault_cap);
        let share_total_supply_option = coin::supply<VaultCoin<BaseCoin>>();
        let share_total_supply = option::get_with_default<u128>(&share_total_supply_option, 0);
        total_assets * share / (share_total_supply as u64)
    }

    // gets vault address from vault_cap
    public fun get_vault_addr(vault_cap: &VaultCapability): address {
        vault_cap.vault_addr
    }

    public fun get_strategy_coin_type<StrategyType: drop>(vault_cap: &VaultCapability) : TypeInfo acquires VaultStrategy {
        let strategy = borrow_global_mut<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        strategy.strategy_coin_type
    }

    // private functions

    // mint vault coin shares to user
    // called by deposit_as_user
    fun mint_vault_coin<BaseCoin>(user: &signer, vault_cap: &VaultCapability, amount: u64) acquires Caps {
        let caps = borrow_global<Caps<VaultCoin<BaseCoin>>>(vault_cap.vault_addr);
        let coins = coin::mint<VaultCoin<BaseCoin>>(amount, &caps.mint_cap);
        if(!is_vault_coin_registered<BaseCoin>(signer::address_of(user))){
            coin::register<VaultCoin<BaseCoin>>(user);
        };
        coin::deposit(signer::address_of(user), coins);
    }

    // burn vault coin from user
    // called by withdraw_as_user
    fun burn_vault_coins<BaseCoin>(user: &signer, vault_cap: &VaultCapability, amount: u64) acquires Caps {
        let caps = borrow_global<Caps<VaultCoin<BaseCoin>>>(vault_cap.vault_addr);
        coin::burn(coin::withdraw<VaultCoin<BaseCoin>>(user, amount), &caps.burn_cap);
    }

    // test functions

    #[test_only]
    public fun new_test<BaseCoin>(
        vault_owner: &signer, 
        seed: vector<u8>, 
        vault_id: u64,
        management_fee: u64,
        performance_fee: u64
    ): VaultCapability {
        // create a resource account for the vault managed by the sender
        let (vault_acc, storage_cap) = account::create_resource_account(vault_owner, seed);

        // create a new vault and move it to the vault account
        let base_coin_type = type_info::type_of<BaseCoin>();
        let base_coin_decimals = coin::decimals<BaseCoin>();
        move_to(
            &vault_acc,
            Vault {
                base_coin_type,
                base_coin_decimals,
                management_fee,
                performance_fee,
                debt_ratio: 0,
                total_debt: 0
            }
        );

        // initialize vault coin and destroy freeze cap
        let (
            burn_cap,
            freeze_cap,
            mint_cap
        ) = coin::initialize<VaultCoin<BaseCoin>>(
            vault_owner,
            string::utf8(b"Vault Token"),
            string::utf8(b"Vault"),
            8,
            true
        );
        move_to(&vault_acc, Caps<VaultCoin<BaseCoin>> { mint_cap, freeze_cap, burn_cap});

        // create vault capability with storage cap and mint/burn capability
        let vault_cap = VaultCapability {
            storage_cap,
            vault_addr: signer::address_of(&vault_acc),
            vault_id,
        };
        add_coin<BaseCoin>(&vault_cap);
        vault_cap
    }

    #[test_only]
    public fun test_deposit_as_user<BaseCoin>(
        user: &signer,
        vault_cap: &VaultCapability,
        base_coin: Coin<BaseCoin>
    ) acquires Vault, CoinStore, Caps {
        deposit_as_user(user, vault_cap, base_coin);
    }

    #[test_only]
    public fun test_withdraw_as_user<BaseCoin>(
        user: &signer,
        vault_cap: &VaultCapability,
        amount: u64
    ) : Coin<BaseCoin> acquires Vault, CoinStore, Caps {
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
    public fun test_approve_strategy<StrategyType: drop>(
        vault_cap: &VaultCapability,
        position_type: TypeInfo,
        debt_ratio: u64
    ) acquires Vault {
        approve_strategy<StrategyType>(vault_cap, position_type, debt_ratio);
    }

    #[test_only]
    public fun test_update_fee(
        vault_cap: &VaultCapability,
        management_fee: u64,
        performance_fee: u64
    ) acquires Vault {
        update_fee(vault_cap, management_fee, performance_fee);
    }
}