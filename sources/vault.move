module satay::vault {
    use std::signer;
    use std::string;
    use std::option;

    use aptos_std::type_info::{Self, TypeInfo};

    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability, FreezeCapability};
    use aptos_framework::timestamp;
    use aptos_framework::event::{Self, EventHandle};

    use satay::dao_storage;
    use satay::math;
    use satay::vault_config;
    use satay::strategy_config;
    use satay::global_config;

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
    const ERR_VAULT_FROZEN: u64 = 109;
    const ERR_VAULT_NOT_FROZEN: u64 = 110;
    const ERR_LOSS: u64 = 111;

    struct CoinStore<phantom CoinType> has key {
        coin: Coin<CoinType>,
        deposit_events: EventHandle<DepositEvent>,
        withdraw_events: EventHandle<WithdrawEvent>,
    }

    struct Vault has key {
        base_coin_type: TypeInfo,
        base_coin_decimals: u8,
        management_fee: u64,
        performance_fee: u64,
        debt_ratio: u64,
        total_debt: u64,
        deposits_frozen: bool,
        user_deposit_events: EventHandle<UserDepositEvent>,
        user_withdraw_events: EventHandle<UserWithdrawEvent>,
        update_fees_events: EventHandle<UpdateFeesEvent>,
        freeze_events: EventHandle<FreezeEvent>,
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
        debt_ratio_change_events: EventHandle<DebtRatioChangeEvent>,
        debt_change_events: EventHandle<DebtChangeEvent>,
        gain_events: EventHandle<GainEvent>,
        loss_events: EventHandle<LossEvent>,
        harvest_events: EventHandle<HarvestEvent>,
        assess_fees_events: EventHandle<AssessFeesEvent>,
    }

    // capabilities

    struct VaultCapability has store {
        storage_cap: SignerCapability,
        vault_id: u64,
        vault_addr: address,
    }

    struct VaultManagerCapability {
        vault_cap: VaultCapability
    }

    struct KeeperCapability<StrategyType: drop> {
        vault_cap: VaultCapability,
        witness: StrategyType
    }

    struct UserCapability {
        vault_cap: VaultCapability,
        user_addr: address,
    }

    // events

    // coin store events

    struct DepositEvent has drop, store {
        amount: u64,
    }

    struct WithdrawEvent has drop, store {
        amount: u64,
    }

    // vault events

    struct UserDepositEvent has drop, store {
        user_addr: address,
        base_coin_amount: u64,
        vault_coin_amount: u64,
    }

    struct UserWithdrawEvent has drop, store {
        user_addr: address,
        base_coin_amount: u64,
        vault_coin_amount: u64,
    }

    struct UpdateFeesEvent has drop, store {
        management_fee: u64,
        performance_fee: u64,
    }

    struct FreezeEvent has drop, store {
        frozen: bool,
    }

    // vault strategy events

    struct DebtRatioChangeEvent has drop, store {
        debt_ratio: u64,
    }

    struct DebtChangeEvent has drop, store {
        debt_payment: u64,
        credit: u64,
    }

    struct GainEvent has drop, store {
        gain: u64,
    }

    struct LossEvent has drop, store {
        loss: u64,
    }

    struct HarvestEvent has drop, store {
        timestamp: u64,
    }

    struct AssessFeesEvent has drop, store {
        vault_coin_amount: u64
    }

    // capability functions

    public(friend) fun get_vault_manager_capability(
        vault_manager: &signer,
        vault_cap: VaultCapability
    ): VaultManagerCapability {
        vault_config::assert_vault_manager(vault_manager, vault_cap.vault_addr);
        VaultManagerCapability { vault_cap }
    }

    public(friend) fun destroy_vault_manager_capability(
        vault_manager_cap: VaultManagerCapability
    ): VaultCapability {
        let VaultManagerCapability {
            vault_cap
        } = vault_manager_cap;
        vault_cap
    }

    public(friend) fun get_keeper_capability<StrategyType: drop>(
        keeper: &signer,
        vault_cap: VaultCapability,
        witness: StrategyType
    ): KeeperCapability<StrategyType> {
        strategy_config::assert_keeper<StrategyType>(keeper, vault_cap.vault_addr);
        KeeperCapability<StrategyType> {
            vault_cap,
            witness
        }
    }

    public(friend) fun destroy_keeper_capability<StrategyType: drop>(
        keeper_cap: KeeperCapability<StrategyType>
    ): VaultCapability {
        let KeeperCapability<StrategyType> {
            vault_cap,
            witness: _
        } = keeper_cap;
        vault_cap
    }

    public(friend) fun get_user_capability(
        user: &signer,
        vault_cap: VaultCapability,
    ): UserCapability {
        UserCapability {
            vault_cap,
            user_addr: signer::address_of(user),
        }
    }

    public(friend) fun destroy_user_capability(
        user_cap: UserCapability
    ): (VaultCapability, address) {
        let UserCapability {
            vault_cap,
            user_addr,
        } = user_cap;
        (vault_cap, user_addr)
    }

    // governance functions

    // create new vault with BaseCoin as its base coin type
    public(friend) fun new<BaseCoin>(
        governance: &signer,
        vault_id: u64,
        management_fee: u64,
        performance_fee: u64
    ): VaultCapability {
        global_config::assert_governance(governance);
        assert_fee_amounts(management_fee, performance_fee);

        // create vault coin name
        let vault_coin_name = coin::name<BaseCoin>();
        string::append_utf8(&mut vault_coin_name, b" Vault");
        let seed = *string::bytes(&vault_coin_name);

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
            deposits_frozen: false,
            debt_ratio: 0,
            total_debt: 0,
            user_deposit_events: account::new_event_handle<UserDepositEvent>(&vault_acc),
            user_withdraw_events: account::new_event_handle<UserWithdrawEvent>(&vault_acc),
            update_fees_events: account::new_event_handle<UpdateFeesEvent>(&vault_acc),
            freeze_events: account::new_event_handle<FreezeEvent>(&vault_acc),
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

        // initialize vault config
        vault_config::initialize(&vault_acc);

        // return vault_cap to be stored in vaults table on Satay module
        vault_cap
    }

    // user functions

    // deposit base_coin into the vault
    // called by satay module
    public(friend) fun deposit_as_user<BaseCoin>(
        user_cap: &UserCapability,
        base_coins: Coin<BaseCoin>
    ): Coin<VaultCoin<BaseCoin>> acquires Vault, CoinStore, VaultCoinCaps {
        let vault_cap = &user_cap.vault_cap;
        assert_vault_active(vault_cap);
        assert_base_coin_correct_for_vault_cap<BaseCoin>(vault_cap);

        let base_coin_amount = coin::value(&base_coins);
        let vault_coin_amount = calculate_vault_coin_amount_from_base_coin_amount<BaseCoin>(
            vault_cap,
            coin::value(&base_coins)
        );

        // emit deposit event
        let vault = borrow_global_mut<Vault>(vault_cap.vault_addr);
        event::emit_event(&mut vault.user_deposit_events, UserDepositEvent {
            user_addr: user_cap.user_addr,
            base_coin_amount,
            vault_coin_amount
        });

        // deposit base coin and mint vault coin
        deposit(vault_cap, base_coins);
        let caps = borrow_global<VaultCoinCaps<BaseCoin>>(vault_cap.vault_addr);
        coin::mint<VaultCoin<BaseCoin>>(vault_coin_amount, &caps.mint_cap)
    }

    // withdraw base_coin from the vault
    // ensure that BaseCoin is the base coin type of the vault
    public(friend) fun withdraw_as_user<BaseCoin>(
        user_cap: &UserCapability,
        vault_coins: Coin<VaultCoin<BaseCoin>>
    ): Coin<BaseCoin> acquires CoinStore, Vault, VaultCoinCaps {
        let vault_cap = &user_cap.vault_cap;
        assert_base_coin_correct_for_vault_cap<BaseCoin>(vault_cap);

        let vault_coin_amount = coin::value(&vault_coins);
        let base_coin_amount = calculate_base_coin_amount_from_vault_coin_amount<BaseCoin>(
            vault_cap,
            coin::value(&vault_coins)
        );



        let vault = borrow_global_mut<Vault>(vault_cap.vault_addr);
        event::emit_event(&mut vault.user_withdraw_events, UserWithdrawEvent {
            user_addr: user_cap.user_addr,
            base_coin_amount,
            vault_coin_amount,
        });

        let caps = borrow_global<VaultCoinCaps<BaseCoin>>(vault_cap.vault_addr);
        coin::burn(vault_coins, &caps.burn_cap);
        withdraw(vault_cap, base_coin_amount)
    }

    public(friend) fun withdraw_strategy_coin_for_liquidation<StrategyType: drop, StrategyCoin, BaseCoin>(
        user_cap: &UserCapability,
        strategy_coin_amount: u64,
        _witness: &StrategyType
    ): Coin<StrategyCoin> acquires CoinStore, VaultStrategy {
        let vault_cap = &user_cap.vault_cap;
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

    public(friend) fun user_liquidation<StrategyType: drop, BaseCoin>(
        user_cap: UserCapability,
        debt_payment: Coin<BaseCoin>,
        vault_coins: Coin<VaultCoin<BaseCoin>>,
        witness: &StrategyType
    ): VaultCapability acquires Vault, CoinStore, VaultStrategy, VaultCoinCaps {
        update_total_debt<StrategyType>(&user_cap.vault_cap, 0, coin::value(&debt_payment), witness);
        deposit_base_coin(&user_cap.vault_cap, debt_payment, witness);
        let base_coins = withdraw_as_user(&user_cap, vault_coins);
        let (
            vault_cap,
            user_addr
        ) = destroy_user_capability(user_cap);
        coin::deposit<BaseCoin>(user_addr, base_coins);
        vault_cap
    }

    // vault manager functions

    // update vault fee
    public(friend) fun update_fee(
        vault_manager_cap: &VaultManagerCapability,
        management_fee: u64,
        performance_fee: u64
    ) acquires Vault {
        assert_fee_amounts(management_fee, performance_fee);

        let vault = borrow_global_mut<Vault>(vault_manager_cap.vault_cap.vault_addr);
        vault.management_fee = management_fee;
        vault.performance_fee = performance_fee;

        event::emit_event(&mut vault.update_fees_events, UpdateFeesEvent {
            management_fee,
            performance_fee,
        });
    }

    public(friend) fun freeze_vault(
       vault_manager_cap: &VaultManagerCapability
    ) acquires Vault {
        assert_vault_active(&vault_manager_cap.vault_cap);
        let vault = borrow_global_mut<Vault>(vault_manager_cap.vault_cap.vault_addr);
        vault.deposits_frozen = true;
        event::emit_event(&mut vault.freeze_events, FreezeEvent {
            frozen: true,
        });
    }

    public(friend) fun unfreeze_vault(
        vault_manager_cap: &VaultManagerCapability
    ) acquires Vault {
        assert_vault_not_active(&vault_manager_cap.vault_cap);
        let vault = borrow_global_mut<Vault>(vault_manager_cap.vault_cap.vault_addr);
        vault.deposits_frozen = false;
        event::emit_event(&mut vault.freeze_events, FreezeEvent {
            frozen: false,
        });
    }

    // approves strategy for vault
    public(friend) fun approve_strategy<StrategyType: drop, StrategyCoin>(
        vault_manager_cap: &VaultManagerCapability,
        debt_ratio: u64,
        witness: &StrategyType
    ) acquires Vault, VaultStrategy {
        let vault_cap = &vault_manager_cap.vault_cap;
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
            last_report: timestamp::now_seconds(),
            debt_ratio_change_events: account::new_event_handle<DebtRatioChangeEvent>(&vault_acc),
            debt_change_events: account::new_event_handle<DebtChangeEvent>(&vault_acc),
            gain_events: account::new_event_handle<GainEvent>(&vault_acc),
            loss_events: account::new_event_handle<LossEvent>(&vault_acc),
            harvest_events: account::new_event_handle<HarvestEvent>(&vault_acc),
            assess_fees_events: account::new_event_handle<AssessFeesEvent>(&vault_acc),
        });

        strategy_config::initialize<StrategyType>(
            &vault_acc,
            witness
        );

        // emit debt ratio change event
        let vault_strategy = borrow_global_mut<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        event::emit_event(&mut vault_strategy.debt_ratio_change_events, DebtRatioChangeEvent {
            debt_ratio,
        });

        if(!has_coin<StrategyCoin>(vault_cap)){
            add_coin<StrategyCoin>(vault_cap);
        };

        // update vault params
        vault.debt_ratio = vault.debt_ratio + debt_ratio;
    }

    // update strategy debt ratio
    public(friend) fun update_strategy_debt_ratio<StrategyType: drop>(
        vault_manager: &signer,
        vault_cap: &VaultCapability,
        debt_ratio: u64,
        _witness: &StrategyType
    ): u64 acquires Vault, VaultStrategy {
        vault_config::assert_vault_manager(vault_manager, vault_cap.vault_addr);

        let vault = borrow_global_mut<Vault>(vault_cap.vault_addr);
        let strategy = borrow_global_mut<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        let old_debt_ratio = strategy.debt_ratio;

        vault.debt_ratio = vault.debt_ratio - old_debt_ratio + debt_ratio;
        strategy.debt_ratio = debt_ratio;

        // check if the strategy's updated debt ratio is valid
        assert!(vault.debt_ratio <= MAX_DEBT_RATIO_BPS, ERR_INVALID_DEBT_RATIO);

        // emit debt ratio change event
        event::emit_event(&mut strategy.debt_ratio_change_events, DebtRatioChangeEvent {
            debt_ratio,
        });

        debt_ratio
    }

    // for keeper

    public(friend) fun deposit_profit<StrategyType: drop, BaseCoin>(
        keeper_cap: &KeeperCapability<StrategyType>,
        base_coin: Coin<BaseCoin>,
    ) acquires Vault, CoinStore, VaultStrategy, VaultCoinCaps {
        let vault_cap = &keeper_cap.vault_cap;
        let witness = &keeper_cap.witness;
        report_gain<StrategyType>(vault_cap, coin::value(&base_coin), witness);
        assess_fees<StrategyType, BaseCoin>(
            &mut base_coin,
            vault_cap,
            witness
        );
        deposit_base_coin(vault_cap, base_coin, witness);
    }

    public(friend) fun debt_payment<StrategyType: drop, BaseCoin>(
        keeper_cap: &KeeperCapability<StrategyType>,
        base_coin: Coin<BaseCoin>,
    ) acquires Vault, CoinStore, VaultStrategy {
        let vault_cap = &keeper_cap.vault_cap;
        update_total_debt<StrategyType>(
            vault_cap,
            0,
            coin::value(&base_coin),
            &keeper_cap.witness
        );
        deposit_base_coin(vault_cap, base_coin, &keeper_cap.witness);
    }

    public(friend) fun deposit_strategy_coin<StrategyType: drop, StrategyCoin>(
        keeper_cap: &KeeperCapability<StrategyType>,
        strategy_coin: Coin<StrategyCoin>,
    ) acquires CoinStore, VaultStrategy {
        let vault_cap = &keeper_cap.vault_cap;
        assert_strategy_coin_correct_for_strategy_type<StrategyType, StrategyCoin>(vault_cap);
        deposit(vault_cap, strategy_coin);
    }

    public(friend) fun withdraw_strategy_coin<StrategyType: drop, StrategyCoin>(
        keeper_cap: &KeeperCapability<StrategyType>,
        strategy_coin_amount: u64,
    ): Coin<StrategyCoin> acquires CoinStore, VaultStrategy {
        let vault_cap = &keeper_cap.vault_cap;
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

    public(friend) fun process_harvest<StrategyType: drop, BaseCoin, StrategyCoin>(
        keeper_cap: &KeeperCapability<StrategyType>,
        strategy_balance: u64,
    ) : (Coin<BaseCoin>, u64, u64) acquires VaultStrategy, Vault, CoinStore {

        let vault_cap = &keeper_cap.vault_cap;
        let witness = &keeper_cap.witness;

        let (profit, loss, debt_payment) = prepare_return<StrategyType, BaseCoin>(
            vault_cap,
            strategy_balance
        );

        // loss to report, do it before the rest of the calculation
        if (loss > 0) {
            let total_debt = total_debt<StrategyType>(vault_cap);
            assert!(total_debt >= loss, ERR_LOSS);
            report_loss<StrategyType>(vault_cap, loss, witness);
        };

        let debt = debt_out_standing<StrategyType, BaseCoin>(vault_cap);
        if (debt_payment > debt) {
            debt_payment = debt;
        };

        let credit = credit_available<StrategyType, BaseCoin>(vault_cap);
        let to_apply= coin::zero<BaseCoin>();
        if(credit > 0){
            coin::merge(
                &mut to_apply,
                withdraw_base_coin<StrategyType, BaseCoin>(
                    vault_cap,
                    credit,
                    witness
                )
            );
        };

        (to_apply, profit, debt_payment)
    }

    fun prepare_return<StrategyType: drop, BaseCoin>(
        vault_cap: &VaultCapability,
        strategy_balance: u64
    ): (u64, u64, u64) acquires VaultStrategy, Vault, CoinStore {

        // get amount of strategy debt over limit
        let debt_out_standing = debt_out_standing<StrategyType, BaseCoin>(vault_cap);
        let debt_payment: u64;
        if (strategy_balance > debt_out_standing) {
            debt_payment = debt_out_standing;
            strategy_balance = strategy_balance - debt_payment;
        } else {
            debt_payment = strategy_balance;
            strategy_balance = 0;
        };

        // calculate profit and loss
        let profit = 0;
        let loss = 0;

        // strategy's total debt
        let total_debt = total_debt<StrategyType>(vault_cap);

        total_debt = total_debt - debt_payment;

        if (strategy_balance > total_debt) {
            profit = strategy_balance - total_debt;
        } else {
            loss = total_debt - strategy_balance;
        };

        (profit, loss, debt_payment)
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

    public fun is_vault_frozen(
        vault_cap: &VaultCapability
    ): bool acquires Vault {
        let vault = borrow_global<Vault>(vault_cap.vault_addr);
        vault.deposits_frozen
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

    public fun harvest_balance<StrategyType: drop, StrategyCoin>(
        keeper_cap: &KeeperCapability<StrategyType>
    ): u64 acquires CoinStore {
        balance<StrategyCoin>(&keeper_cap.vault_cap)
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
        let vault_debt_limit = math::calculate_proportion_of_u64_with_u64_denominator(
            vault_total_assets,
            vault_debt_ratio,
            MAX_DEBT_RATIO_BPS
        );

        let strategy = borrow_global<VaultStrategy<StrategyType>>(vault_cap.vault_addr);

        let strategy_debt_limit = math::calculate_proportion_of_u64_with_u64_denominator(
            vault_total_assets,
            strategy.debt_ratio,
            MAX_DEBT_RATIO_BPS
        );
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
        let strategy_debt_limit = math::calculate_proportion_of_u64_with_u64_denominator(
            vault_total_assets,
            strategy.debt_ratio,
            MAX_DEBT_RATIO_BPS
        );
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

    // calculates amount of BaseCoin to return given an amount of VaultCoin to burn
    public fun calculate_base_coin_amount_from_vault_coin_amount<BaseCoin>(
        vault_cap: &VaultCapability,
        vault_coin_amount: u64
    ): u64 acquires Vault, CoinStore {
        let total_assets = total_assets<BaseCoin>(vault_cap);
        let share_total_supply_option = coin::supply<VaultCoin<BaseCoin>>();
        let share_total_supply = option::get_with_default<u128>(&share_total_supply_option, 0);
        math::calculate_proportion_of_u64_with_u128_denominator(
            total_assets,
            vault_coin_amount,
            share_total_supply
        )
    }

    public fun calculate_vault_coin_amount_from_base_coin_amount<BaseCoin>(
        vault_cap: &VaultCapability,
        base_coin_amount: u64
    ): u64 acquires Vault, CoinStore {
        let total_base_coin_amount = total_assets<BaseCoin>(vault_cap);
        let total_supply = option::get_with_default<u128>(&coin::supply<VaultCoin<BaseCoin>>(), 0);

        if (total_supply != 0) {
            // this function will abort if total_supply * base_coin_amount > u128::max_value()
            // in practice, this should never happen. If it does, base_coin_amount should be reduced and split into
            // two transactions
            math::mul_u128_u64_div_u64_result_u64(
                total_supply,
                base_coin_amount,
                total_base_coin_amount
            )
        } else {
            base_coin_amount
        }
    }

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

    // test getters

    // gets vault address from vault_cap
    #[test_only]
    public fun get_vault_addr(
        vault_cap: &VaultCapability
    ): address {
        vault_cap.vault_addr
    }

    // private functions

    // create a new CoinStore for CoinType
    fun add_coin<CoinType>(
        vault_cap: &VaultCapability
    ) {
        let vault_acc = account::create_signer_with_capability(&vault_cap.storage_cap);
        move_to(&vault_acc, CoinStore<CoinType> {
            coin: coin::zero(),
            deposit_events: account::new_event_handle<DepositEvent>(&vault_acc),
            withdraw_events: account::new_event_handle<WithdrawEvent>(&vault_acc),
        });
    }

    // deposit coin of CoinType into the vault
    fun deposit<CoinType>(
        vault_cap: &VaultCapability,
        coin: Coin<CoinType>
    ) acquires CoinStore {
        let store = borrow_global_mut<CoinStore<CoinType>>(vault_cap.vault_addr);
        event::emit_event(&mut store.deposit_events, DepositEvent {
            amount: coin::value(&coin)
        });
        coin::merge(&mut store.coin, coin);
    }

    // withdraw coin of CoinType from the vault
    fun withdraw<CoinType>(
        vault_cap: &VaultCapability,
        amount: u64
    ): Coin<CoinType> acquires CoinStore {
        let store = borrow_global_mut<CoinStore<CoinType>>(vault_cap.vault_addr);
        event::emit_event(&mut store.deposit_events, DepositEvent {
            amount
        });
        coin::extract(&mut store.coin, amount)
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
    fun withdraw_base_coin<StrategyType: drop, BaseCoin>(
        vault_cap: &VaultCapability,
        amount: u64,
        witness: &StrategyType
    ): Coin<BaseCoin> acquires CoinStore, Vault, VaultStrategy {
        assert_base_coin_correct_for_vault_cap<BaseCoin>(vault_cap);

        assert!(credit_available<StrategyType, BaseCoin>(vault_cap) >= amount, ERR_INSUFFICIENT_CREDIT);

        update_total_debt(vault_cap, amount, 0, witness);

        withdraw(vault_cap, amount)
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

        // emit debt change event
        event::emit_event(&mut strategy.debt_change_events, DebtChangeEvent {
            debt_payment,
            credit
        })
    }

    // assesses fees when strategies return a profit
    fun assess_fees<StrategyType: drop, BaseCoin>(
        profit: &Coin<BaseCoin>,
        vault_cap: &VaultCapability,
        witness: &StrategyType
    ) acquires VaultStrategy, Vault, CoinStore, VaultCoinCaps {
        let vault = borrow_global<Vault>(vault_cap.vault_addr);
        let strategy = borrow_global_mut<VaultStrategy<StrategyType>>(vault_cap.vault_addr);

        let duration = timestamp::now_seconds() - strategy.last_report;
        let gain = coin::value(profit);

        if (duration == 0 || gain == 0) {
            return
        };

        // management_fee is at most 5000, so u64 numerator will not overflow for durations < (2^64 - 1) / 5000
        // (2^64 - 1) / 5000 seconds equals roughly 5.8 million years
        // denominator is constant 3.2 * 10 ^ 11, which is less than 2^64 - 1, and cannot overflow
        let management_fee_amount = math::mul_div(
            strategy.total_debt,
            vault.management_fee * duration,
            MAX_DEBT_RATIO_BPS * SECS_PER_YEAR
        );
        let performance_fee_amount = math::calculate_proportion_of_u64_with_u64_denominator(
            gain,
            vault.performance_fee,
            MAX_DEBT_RATIO_BPS
        );

        let total_fee_amount = management_fee_amount + performance_fee_amount;
        if (total_fee_amount > gain) {
            total_fee_amount = gain;
        };


        // calculate amount of share tokens to mint
        let vault_coin_amount = calculate_vault_coin_amount_from_base_coin_amount<BaseCoin>(
            vault_cap,
            total_fee_amount
        );


        // mint vault coins to dao storage
        let caps = borrow_global<VaultCoinCaps<BaseCoin>>(vault_cap.vault_addr);
        let coins = coin::mint<VaultCoin<BaseCoin>>(vault_coin_amount, &caps.mint_cap);
        dao_storage::deposit<VaultCoin<BaseCoin>>(vault_cap.vault_addr, coins);

        // emit fee event
        event::emit_event(&mut strategy.assess_fees_events, AssessFeesEvent {
            vault_coin_amount
        });

        report_timestamp(vault_cap, witness);
    }

    // report a gain for StrategyType
    fun report_gain<StrategyType: drop>(
        vault_cap: &VaultCapability,
        gain: u64,
        _witness: &StrategyType
    ) acquires VaultStrategy {
        let strategy = borrow_global_mut<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        strategy.total_gain = strategy.total_gain + gain;
        // emit gain event
        event::emit_event(&mut strategy.gain_events, GainEvent {
            gain,
        });
    }

    // report a loss for StrategyType
    fun report_loss<StrategyType: drop>(
        vault_cap: &VaultCapability,
        loss: u64,
        _witness: &StrategyType
    ) acquires Vault, VaultStrategy {
        let vault = borrow_global_mut<Vault>(vault_cap.vault_addr);
        let strategy = borrow_global_mut<VaultStrategy<StrategyType>>(vault_cap.vault_addr);

        if (vault.debt_ratio != 0) {
            let ratio_change = math::calculate_proportion_of_u64_with_u64_denominator(
                vault.debt_ratio,
                loss,
                vault.total_debt
            );
            if (ratio_change > strategy.debt_ratio) {
                ratio_change = strategy.debt_ratio;
            };
            strategy.debt_ratio = strategy.debt_ratio - ratio_change;
            vault.debt_ratio = vault.debt_ratio - ratio_change;
        };

        strategy.total_loss = strategy.total_loss + loss;
        strategy.total_debt = strategy.total_debt - loss;
        vault.total_debt = vault.total_debt - loss;

        // emit loss event
        event::emit_event(&mut strategy.loss_events, LossEvent {
            loss,
        });
    }

    // report time for StrategyType
    fun report_timestamp<StrategyType: drop>(
        vault_cap: &VaultCapability,
        _witness: &StrategyType
    ) acquires VaultStrategy {
        let timestamp = timestamp::now_seconds();
        let strategy = borrow_global_mut<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        strategy.last_report = timestamp;
        event::emit_event(&mut strategy.harvest_events, HarvestEvent {
            timestamp
        });
    }

    // asserts

    public fun assert_base_coin_correct_for_vault_cap<BaseCoin> (
        vault_cap: &VaultCapability
    ) acquires Vault {
        let vault = borrow_global<Vault>(vault_cap.vault_addr);
        assert!(vault.base_coin_type == type_info::type_of<BaseCoin>(), ERR_COIN);
    }

    public fun assert_keeper<StrategyType: drop>(keeper: &signer, vault_cap: &VaultCapability) {
        strategy_config::assert_keeper<StrategyType>(keeper, vault_cap.vault_addr);
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

    fun assert_vault_active(vault_cap: &VaultCapability) acquires Vault {
        assert!(!is_vault_frozen(vault_cap), ERR_VAULT_FROZEN);
    }

    fun assert_vault_not_active(vault_cap: &VaultCapability) acquires Vault {
        assert!(is_vault_frozen(vault_cap), ERR_VAULT_NOT_FROZEN);
    }

    // test functions

    #[test_only]
    public fun new_test<BaseCoin>(
        governance: &signer, 
        vault_id: u64,
        management_fee: u64,
        performance_fee: u64
    ): VaultCapability {
        new<BaseCoin>(
            governance,
            vault_id,
            management_fee,
            performance_fee
        )
    }

    #[test_only]
    public fun test_deposit_as_user<BaseCoin>(
        user: &signer,
        vault_cap: VaultCapability,
        base_coins: Coin<BaseCoin>
    ): VaultCapability acquires Vault, CoinStore, VaultCoinCaps {
        let user_cap = get_user_capability(user, vault_cap);
        let vault_coins = deposit_as_user(&user_cap, base_coins);
        let (vault_cap, user_addr) = destroy_user_capability(user_cap);
        coin::deposit(user_addr, vault_coins);
        vault_cap
    }

    #[test_only]
    public fun test_withdraw_as_user<BaseCoin>(
        user: &signer,
        vault_cap: VaultCapability,
        vault_coins: Coin<VaultCoin<BaseCoin>>
    ): VaultCapability acquires Vault, CoinStore, VaultCoinCaps {
        let user_cap = get_user_capability(user, vault_cap);
        let base_coins = withdraw_as_user(&user_cap, vault_coins);
        let (vault_cap, user_addr) = destroy_user_capability(user_cap);
        coin::deposit(user_addr, base_coins);
        vault_cap
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
    public fun test_destroy_vault_cap(vault_cap: VaultCapability) {
        let VaultCapability {
            storage_cap: _,
            vault_addr: _,
            vault_id: _
        } = vault_cap;
    }

    #[test_only]
    public fun test_get_vault_manager_cap(vault_manager: &signer, vault_cap: VaultCapability): VaultManagerCapability {
        get_vault_manager_capability(vault_manager, vault_cap)
    }

    #[test_only]
    public fun test_destroy_vault_manager_cap(vault_manager_cap: VaultManagerCapability): VaultCapability {
        destroy_vault_manager_capability(vault_manager_cap)
    }

    #[test_only]
    public fun test_get_keeper_cap<StrategyType: drop>(
        keeper: &signer,
        vault_cap: VaultCapability,
        witness: StrategyType
    ): KeeperCapability<StrategyType> {
        get_keeper_capability<StrategyType>(keeper, vault_cap, witness)
    }

    #[test_only]
    public fun test_destroy_keeper_cap<StrategyType: drop>(keeper_cap: KeeperCapability<StrategyType>): VaultCapability {
        destroy_keeper_capability(keeper_cap)
    }

    #[test_only]
    public fun test_approve_strategy<StrategyType: drop, StrategyCoin>(
        vault_manager_cap: &VaultManagerCapability,
        debt_ratio: u64,
        witness: StrategyType
    ) acquires Vault, VaultStrategy {
        approve_strategy<StrategyType, StrategyCoin>(
            vault_manager_cap,
            debt_ratio,
            &witness
        );
    }

    #[test_only]
    public fun test_update_fee(
        vault_manager_cap: &VaultManagerCapability,
        management_fee: u64,
        performance_fee: u64
    ) acquires Vault {
        update_fee(
            vault_manager_cap,
            management_fee,
            performance_fee
        );
    }

    #[test_only]
    public fun test_freeze_vault(
        vault_manager_cap: &VaultManagerCapability,
    ) acquires Vault {
        freeze_vault(
            vault_manager_cap
        );
    }

    #[test_only]
    public fun test_unfreeze_vault(
        vault_manager_cap: &VaultManagerCapability,
    ) acquires Vault {
        unfreeze_vault(
            vault_manager_cap
        );
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
        keeper_cap: &KeeperCapability<StrategyType>,
        debt_payment_coins: Coin<BaseCoin>,
    ) acquires Vault, CoinStore, VaultStrategy {
        debt_payment<StrategyType, BaseCoin>(keeper_cap, debt_payment_coins);
    }

    #[test_only]
    public fun test_deposit_profit<StrategyType: drop, BaseCoin>(
        keeper_cap: &KeeperCapability<StrategyType>,
        profit: Coin<BaseCoin>,
    ) acquires Vault, CoinStore, VaultStrategy, VaultCoinCaps {
        deposit_profit<StrategyType, BaseCoin>(keeper_cap, profit);
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
    public fun test_keeper_withdraw_base_coin<StrategyType: drop, BaseCoin>(
        keeper_cap: &KeeperCapability<StrategyType>,
        amount: u64,
    ) : Coin<BaseCoin> acquires Vault, CoinStore, VaultStrategy {
        withdraw_base_coin<StrategyType, BaseCoin>(&keeper_cap.vault_cap, amount, &keeper_cap.witness)
    }

    #[test_only]
    public fun test_deposit_strategy_coin<StrategyType: drop, StrategyCoin>(
        keeper_cap: &KeeperCapability<StrategyType>,
        strategy_coin: Coin<StrategyCoin>,
    ) acquires CoinStore, VaultStrategy {
        deposit_strategy_coin<StrategyType, StrategyCoin>(keeper_cap, strategy_coin);
    }

    #[test_only]
    public fun test_withdraw_strategy_coin<StrategyType: drop, StrategyCoin>(
        keeper_cap: &KeeperCapability<StrategyType>,
        amount: u64,
    ) : Coin<StrategyCoin> acquires CoinStore, VaultStrategy {
        withdraw_strategy_coin<StrategyType, StrategyCoin>(keeper_cap, amount)
    }

    #[test_only]
    public fun test_update_strategy_debt_ratio<StrategyType: drop>(
        vault_manager: &signer,
        vault_cap: &VaultCapability,
        debt_ratio: u64,
        witness: &StrategyType
    ) acquires VaultStrategy, Vault {
        update_strategy_debt_ratio<StrategyType>(
            vault_manager,
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

    #[test_only]
    public fun test_prepare_return<StrategyType: drop, BaseCoin>(
        vault_cap: &VaultCapability,
        strategy_balance: u64
    ): (u64, u64, u64) acquires VaultStrategy, Vault, CoinStore {
        prepare_return<StrategyType, BaseCoin>(vault_cap, strategy_balance)
    }

    #[test_only]
    public fun keeper_credit_available<StrategyType: drop, BaseCoin>(
        keeper_cap: &KeeperCapability<StrategyType>,
    ): u64 acquires Vault, VaultStrategy, CoinStore {
        credit_available<StrategyType, BaseCoin>(&keeper_cap.vault_cap)
    }

    #[test_only]
    public fun keeper_debt_out_standing<StrategyType: drop, BaseCoin>(
        keeper_cap: &KeeperCapability<StrategyType>,
    ): u64 acquires Vault, VaultStrategy, CoinStore {
        debt_out_standing<StrategyType, BaseCoin>(&keeper_cap.vault_cap)
    }
}