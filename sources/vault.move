/// core logic for vault creation and operations
module satay::vault {
    use std::signer;
    use std::string;
    use std::option;

    use aptos_std::type_info::{Self, TypeInfo};

    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability, FreezeCapability};
    use aptos_framework::timestamp;
    use aptos_framework::event::{Self, EventHandle};

    use satay_vault_coin::vault_coin::{VaultCoin};
    use satay::dao_storage;
    use satay::math;
    use satay::vault_config;
    use satay::strategy_config;
    use satay::global_config;
    use satay::vault_coin_account;
    use std::bcs::to_bytes;

    friend satay::satay;
    friend satay::base_strategy;

    // constants

    /// maximum debt ratio in BPS
    const MAX_DEBT_RATIO_BPS: u64 = 10000; // 100%
    /// maximum management fee in BPS
    const MAX_MANAGEMENT_FEE: u64 = 5000; // 50%
    /// maximum performance fee in BPS
    const MAX_PERFORMANCE_FEE: u64 = 5000; // 50%
    /// seconds per year
    const SECS_PER_YEAR: u64 = 31556952; // 365.2425 days

    // error codes

    /// when BaseCoin does not match the vault's base coin
    const ERR_INCORRECT_BASE_COIN: u64 = 101;

    /// when StrategyCoin does not match the strategy coin of StrategyType
    const ERR_INCORRECT_STRATEGY_COIN: u64 = 102;

    /// when StrategyType does not match the strategy type of StrategyType
    const ERR_INVALID_DEBT_RATIO: u64 = 103;

    /// when fees are greater than the maximum allowed
    const ERR_INVALID_FEE: u64 = 104;

    /// when StrategyType tries to withdraw more than it is allowed
    const ERR_INSUFFICIENT_CREDIT: u64 = 105;

    /// when a user depoisits to a frozen vault
    const ERR_VAULT_FROZEN: u64 = 106;

    /// when the vault manager tries to unfreeze a frozen vault
    const ERR_VAULT_NOT_FROZEN: u64 = 107;

    /// when a strategy reports a loss greater than its total debt
    const ERR_LOSS: u64 = 108;

    /// when a vault has enough balance to cover a user withdraw
    const ERR_ENOUGH_BALANCE_ON_VAULT: u64 = 109;

    /// when the strategy does not return enough BaseCoin for a user withdraw
    const ERR_INSUFFICIENT_USER_RETURN: u64 = 110;

    /// holds Coin<CoinType> for a vault account
    /// @field coin - the stored coins
    /// @field deposit_events - event handle for deposit events
    /// @field withdraw_events - event handle for withdraw events
    struct VaultCoinCap has key {
        vault_coin_account_cap: SignerCapability
    }

    struct CoinStore<phantom CoinType> has key {
        coin: Coin<CoinType>,
        deposit_events: EventHandle<DepositEvent>,
        withdraw_events: EventHandle<WithdrawEvent>,
    }

    /// holds the information about a vault
    /// @field base_coin_type - the type of the base coin of the vault
    /// @field management_fee - the management fee of the vault in BPS
    /// @field performance_fee - the performance fee of the vault in BPS
    /// @field debt_ratio - the total debt ratio of the vault in BPS
    /// @field total_debt - the total debt of the vault
    /// @field deposits_frozen - whether deposits are frozen
    /// @field user_deposit_events - event handle for user deposit events
    /// @field user_withdraw_events - event handle for user withdraw events
    /// @field update_fees_events - event handle for update fees events
    /// @field freeze_events - event handle for freeze events
    struct Vault has key {
        base_coin_type: TypeInfo,
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

    struct VaultCoinCaps<phantom BaseCoin> has key {
        mint_cap: MintCapability<VaultCoin<BaseCoin>>,
        freeze_cap: FreezeCapability<VaultCoin<BaseCoin>>,
        burn_cap: BurnCapability<VaultCoin<BaseCoin>>
    }

    /// holds the information about a strategy approved on a vault
    /// @field strategy_coin_type - the type of the strategy coin of the strategy
    /// @field debt_ratio - the debt ratio of the strategy in BPS
    /// @field total_debt - the total debt of the strategy
    /// @field total_gain - the total gain of the strategy
    /// @field total_loss - the total loss of the strategy
    /// @field last_report - the last report timestamp of the strategy
    /// @field debt_ratio_change_events - event handle for debt ratio change events
    /// @field debt_change_events - event handle for debt change events
    /// @field gain_events - event handle for gain events
    /// @field loss_events - event handle for loss events
    /// @field harvest_events - event handle for harvest events
    /// @field assess_fees_events - event handle for assess fees events
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

    /// capability to perform vault operations
    /// @field storage_cap - signer capability to access the storage
    /// @field vault_id - the id of the vault
    /// @field vault_addr - the address of the vault
    struct VaultCapability has store {
        storage_cap: SignerCapability,
        vault_id: u64,
        vault_addr: address,
    }

    /// capability to perform vault manager operations
    /// @field vault_cap - a VaultCapability
    struct VaultManagerCapability {
        vault_cap: VaultCapability
    }

    /// capability to perform keeper operations
    /// @field vault_cap - a VaultCapability
    /// @field witness - a StrategyType instance
    struct KeeperCapability<StrategyType: drop> {
        vault_cap: VaultCapability,
        witness: StrategyType
    }

    /// capability to perform user operations
    /// @field vault_cap - a VaultCapability
    /// @field user_addr - the address of the user
    struct UserCapability {
        vault_cap: VaultCapability,
        user_addr: address,
    }

    // user liquidation struct

    /// holds the VaultCoins and amount needed for a user strategy liquidation
    /// @field vault_coins - the VaultCoins of the user
    /// @field amount_needed - the amount of BaseCoin needed to fill VaultCoin liquidation
    struct UserLiquidationLock<phantom BaseCoin> {
        vault_coins: Coin<VaultCoin<BaseCoin>>,
        amount_needed: u64,
    }

    // events

    // coin store events

    /// event emitted when a coin is deposited to a CoinStore
    /// @field amount - the amount of the coin deposited
    struct DepositEvent has drop, store {
        amount: u64,
    }

    /// event emitted when a coin is withdrawn from a CoinStore
    /// @field amount - the amount of the coin withdrawn
    struct WithdrawEvent has drop, store {
        amount: u64,
    }

    // vault events

    /// event emitted when a user deposits to a vault
    /// @field user_addr - the address of the user
    /// @field base_coin_amount - the amount of the base coin deposited
    /// @field vault_coin_amount - the amount of the vault coin minted
    struct UserDepositEvent has drop, store {
        user_addr: address,
        base_coin_amount: u64,
        vault_coin_amount: u64,
    }

    /// event emitted when a user withdraws from a vault
    /// @field user_addr - the address of the user
    /// @field base_coin_amount - the amount of the base coin withdrawn
    struct UserWithdrawEvent has drop, store {
        user_addr: address,
        base_coin_amount: u64,
        vault_coin_amount: u64,
    }

    /// event emitted when the fees of a vault are updated
    /// @field management_fee - the new management fee of the vault
    /// @field performance_fee - the new performance fee of the vault
    struct UpdateFeesEvent has drop, store {
        management_fee: u64,
        performance_fee: u64,
    }

    /// event emitted when the deposits of a vault are frozen or unfrozen
    /// @field frozen - true if the vault is frozen, false otherwise
    struct FreezeEvent has drop, store {
        frozen: bool,
    }

    // vault strategy events

    /// event emitted when the debt ratio of a strategy is changed
    /// @field debt_ratio - the new debt ratio of the strategy
    struct DebtRatioChangeEvent has drop, store {
        debt_ratio: u64,
    }

    /// event emitted when the debt of a strategy is changed
    /// @field debt_payment - the amount of debt paid
    /// @field credit - the amount of debt credited
    struct DebtChangeEvent has drop, store {
        debt_payment: u64,
        credit: u64,
    }

    /// event emitted when a strategy realizes a profit
    /// @field gain - the amount of gain
    struct GainEvent has drop, store {
        gain: u64,
    }

    /// event emitted when a strategy realizes a loss
    /// @field loss - the amount of loss
    struct LossEvent has drop, store {
        loss: u64,
    }

    /// event emitted when a strategy is harvested
    /// @field timestamp - the timestamp of the harvest
    struct HarvestEvent has drop, store {
        timestamp: u64,
    }

    /// event emitted when fees are assessed on a strategy
    /// @field vault_coin_amount - the amount of vault coin minted to DAO storage
    struct AssessFeesEvent has drop, store {
        vault_coin_amount: u64
    }

    public(friend) fun initialize(
        satay_admin: &signer
    ) {
        let vault_coin_account_cap = vault_coin_account::retrieve_signer_cap(satay_admin);
        move_to(satay_admin, VaultCoinCap {
            vault_coin_account_cap
        });
    }

    /// creates a VaultManagerCapability
    /// @param vault_manager - the transaction signer; must be the vault manager of the vault at vault_cap.vault_addr
    /// @param vault_cap - the VaultCapability of the vault
    public(friend) fun get_vault_manager_capability(
        vault_manager: &signer,
        vault_cap: VaultCapability
    ): VaultManagerCapability {
        vault_config::assert_vault_manager(vault_manager, vault_cap.vault_addr);
        VaultManagerCapability { vault_cap }
    }

    /// destroys a VaultManagerCapability
    /// @param vault_manager_cap - a VaultManagerCapability
    public(friend) fun destroy_vault_manager_capability(vault_manager_cap: VaultManagerCapability): VaultCapability {
        let VaultManagerCapability {
            vault_cap
        } = vault_manager_cap;
        vault_cap
    }

    /// creates a KeeperCapability for StrategyType
    /// @param keeper - the transaction signer; must be the keeper of StrategyType on the vault at vault_cap.vault_addr
    /// @param vault_cap - the VaultCapability of the vault
    /// @param witness - a StrategyType instance
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

    /// destroys a KeeperCapability
    /// @param keeper_cap - a KeeperCapability
    public(friend) fun destroy_keeper_capability<StrategyType: drop>(
        keeper_cap: KeeperCapability<StrategyType>
    ): VaultCapability {
        let KeeperCapability<StrategyType> {
            vault_cap,
            witness: _
        } = keeper_cap;
        vault_cap
    }

    /// creates a UserCapability for the vault
    /// @param user - the transaction signer
    /// @param vault_cap - the VaultCapability of the vault
    public(friend) fun get_user_capability(user: &signer, vault_cap: VaultCapability): UserCapability {
        UserCapability {
            vault_cap,
            user_addr: signer::address_of(user),
        }
    }

    /// destroys a UserCapability
    /// @param user_cap - a UserCapability
    public(friend) fun destroy_user_capability(user_cap: UserCapability): (VaultCapability, address) {
        let UserCapability {
            vault_cap,
            user_addr,
        } = user_cap;
        (vault_cap, user_addr)
    }

    // governance functions

    /// creates a new vault for BaseCoin with the given management and performance fees
    /// @param governance - the transaction signer; must be the governance account
    /// @param vault_id - the id of the vault
    /// @param management_fee - the management fee of the vault in BPS
    /// @param performance_fee - the performance fee of the vault in BPS
    public(friend) fun new<BaseCoin>(
        governance: &signer,
        vault_id: u64,
        management_fee: u64,
        performance_fee: u64
    ): VaultCapability acquires VaultCoinCap {
        global_config::assert_governance(governance);
        assert_fee_amounts(management_fee, performance_fee);

        let vault_coin_cap = borrow_global<VaultCoinCap>(@satay);
        let vault_coin_account = account::create_signer_with_capability(
            &vault_coin_cap.vault_coin_account_cap
        );

        // create vault coin name
        let vault_coin_name = coin::name<BaseCoin>();
        string::append_utf8(&mut vault_coin_name, b" Vault");
        let seed = copy vault_coin_name;
        string::append_utf8(&mut seed, to_bytes(&vault_id));

        // create a resource account for the vault managed by the sender
        let (vault_acc, storage_cap) = account::create_resource_account(
            &vault_coin_account,
            *string::bytes(&seed),
        );

        // create a new vault and move it to the vault account
        let base_coin_type = type_info::type_of<BaseCoin>();
        let base_coin_decimals = coin::decimals<BaseCoin>();
        let vault = Vault {
            base_coin_type,
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

        // create vault coin symbol
        let vault_coin_symbol = string::utf8(b"s");
        string::append(&mut vault_coin_symbol, coin::symbol<BaseCoin>());

        // initialize vault coin and move vault caps to vault owner
        let (burn_cap,
            freeze_cap,
            mint_cap
        ) = coin::initialize<VaultCoin<BaseCoin>>(
            &vault_coin_account,
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

    /// deposits BaseCoin into the vault and returns VaultCoin<BaseCoin>
    /// @param user_cap - a UserCapability
    /// @param base_coins - the Coin<BaseCoin> to deposit
    public(friend) fun deposit_as_user<BaseCoin>(
        user_cap: &UserCapability,
        base_coins: Coin<BaseCoin>
    ): Coin<VaultCoin<BaseCoin>>
    acquires Vault, CoinStore, VaultCoinCaps {
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

    /// burns VaultCoin<BaseCoin> and withdraws BaseCoin from the vault
    /// @param user_cap - a UserCapability
    /// @param vault_coins - the Coin<VaultCoin<BaseCoin>> to burn
    public(friend) fun withdraw_as_user<BaseCoin>(
        user_cap: &UserCapability,
        vault_coins: Coin<VaultCoin<BaseCoin>>
    ): Coin<BaseCoin>
    acquires CoinStore, Vault, VaultCoinCaps {
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

    /// get the amount of BaseCoin needed for liquidation of VaultCoin<BaseCoin>
    /// @param vault_cap - the VaultCapability of the vault
    /// @param vault_coins - a reference to the Coin<VaultCoin<BaseCoin>> to liquidate
    public(friend) fun get_liquidation_lock<StrategyType: drop, BaseCoin>(
        vault_cap: &VaultCapability,
        vault_coins: Coin<VaultCoin<BaseCoin>>
    ): UserLiquidationLock<BaseCoin>
    acquires CoinStore, Vault, VaultStrategy {
        // check if vault has enough balance
        let vault_coin_amount = coin::value(&vault_coins);
        let vault_balance = balance<BaseCoin>(vault_cap);
        let value = calculate_base_coin_amount_from_vault_coin_amount<BaseCoin>(
            vault_cap,
            vault_coin_amount
        );
        assert!(vault_balance < value, ERR_ENOUGH_BALANCE_ON_VAULT);

        let amount_needed = value - vault_balance;
        let total_debt = total_debt<StrategyType>(vault_cap);
        assert!(total_debt >= amount_needed, ERR_INSUFFICIENT_USER_RETURN);
        UserLiquidationLock<BaseCoin> {
            vault_coins,
            amount_needed,
        }
    }

    /// withdraws StrategyCoin for user liquidation
    /// @param user_cap - a UserCapability
    /// @param strategy_coin_amount - the amount of StrategyCoin to withdraw
    /// @param _witness - a reference to a StrategyType instance
    public(friend) fun withdraw_strategy_coin_for_liquidation<StrategyType: drop, StrategyCoin, BaseCoin>(
        user_cap: &UserCapability,
        strategy_coin_amount: u64,
        _witness: &StrategyType
    ): Coin<StrategyCoin>
    acquires CoinStore, VaultStrategy {
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

    /// deposits BaseCoin debt from StrategyType to vault and liquidates VaultCoin<BaseCoin> for user
    /// @param user_cap - a UserCapability
    /// @param base_coins - the Coin<BaseCoin> debt to deposit
    /// @param user_liq_lock - the UserLiquidationLock<BaseCoin> to liquidate
    /// @param witness - a reference to a StrategyType instance
    public(friend) fun checked_user_liquidation<StrategyType: drop, BaseCoin>(
        user_cap: &UserCapability,
        base_coins: Coin<BaseCoin>,
        user_liq_lock: UserLiquidationLock<BaseCoin>,
        witness: &StrategyType
    )
    acquires Vault, CoinStore, VaultStrategy, VaultCoinCaps {
        let UserLiquidationLock<BaseCoin> {
            amount_needed,
            vault_coins,
        } = user_liq_lock;
        assert!(coin::value(&base_coins) >= amount_needed, ERR_INSUFFICIENT_USER_RETURN);

        user_liquidation(
            user_cap,
            base_coins,
            vault_coins,
            witness
        );
    }

    /// deposits BaseCoin debt from StrategyType to vault and liquidates VaultCoin<BaseCoin> for user
    /// @param user_cap - a UserCapability
    /// @param debt_payment - the Coin<BaseCoin> debt to deposit
    /// @param vault_coins - the Coin<VaultCoin<BaseCoin>> to liquidate
    /// @param witness - a reference to a StrategyType instance
    fun user_liquidation<StrategyType: drop, BaseCoin>(
        user_cap: &UserCapability,
        debt_payment: Coin<BaseCoin>,
        vault_coins: Coin<VaultCoin<BaseCoin>>,
        witness: &StrategyType
    )
    acquires Vault, CoinStore, VaultStrategy, VaultCoinCaps {
        update_total_debt<StrategyType>(&user_cap.vault_cap, 0, coin::value(&debt_payment), witness);
        deposit_base_coin(&user_cap.vault_cap, debt_payment, witness);
        let base_coins = withdraw_as_user(user_cap, vault_coins);
        coin::deposit<BaseCoin>(user_cap.user_addr, base_coins);
    }



    // vault manager functions

    /// updates the vault's management and performance fees
    /// @param vault_manager_cap - a VaultManagerCapability
    /// @param management_fee - the new management fee
    /// @param performance_fee - the new performance fee
    public(friend) fun update_fee(vault_manager_cap: &VaultManagerCapability, management_fee: u64, performance_fee: u64)
    acquires Vault {
        assert_fee_amounts(management_fee, performance_fee);

        let vault = borrow_global_mut<Vault>(vault_manager_cap.vault_cap.vault_addr);
        vault.management_fee = management_fee;
        vault.performance_fee = performance_fee;

        event::emit_event(&mut vault.update_fees_events, UpdateFeesEvent {
            management_fee,
            performance_fee,
        });
    }

    /// freezes the vault's deposits
    /// @param vault_manager_cap - a VaultManagerCapability
    public(friend) fun freeze_vault(vault_manager_cap: &VaultManagerCapability)
    acquires Vault {
        assert_vault_active(&vault_manager_cap.vault_cap);
        let vault = borrow_global_mut<Vault>(vault_manager_cap.vault_cap.vault_addr);
        vault.deposits_frozen = true;
        event::emit_event(&mut vault.freeze_events, FreezeEvent {
            frozen: true,
        });
    }

    /// unfreezes the vault's deposits
    /// @param vault_manager_cap - a VaultManagerCapability
    public(friend) fun unfreeze_vault(vault_manager_cap: &VaultManagerCapability)
    acquires Vault {
        assert_vault_not_active(&vault_manager_cap.vault_cap);
        let vault = borrow_global_mut<Vault>(vault_manager_cap.vault_cap.vault_addr);
        vault.deposits_frozen = false;
        event::emit_event(&mut vault.freeze_events, FreezeEvent {
            frozen: false,
        });
    }

    /// approves StrategyType for vault
    /// @param vault_manager_cap - a VaultManagerCapability
    /// @param debt_ratio - the initial debt ratio for the strategy
    /// @param witness - a reference to a StrategyType instance
    public(friend) fun approve_strategy<StrategyType: drop, StrategyCoin>(
        vault_manager_cap: &VaultManagerCapability,
        debt_ratio: u64,
        witness: &StrategyType
    )
    acquires Vault, VaultStrategy {
        let vault_cap = &vault_manager_cap.vault_cap;
        let vault = borrow_global_mut<Vault>(vault_cap.vault_addr);

        // check if the strategy's updated debt ratio is valid
        assert_debt_ratio(vault.debt_ratio + debt_ratio);

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

    /// updates the debt ratio for StrategyType
    /// @param vault_manager_cap - a VaultManagerCapability
    /// @param debt_ratio - the new debt ratio for the strategy
    /// @param witness - a reference to a StrategyType instance
    public(friend) fun update_strategy_debt_ratio<StrategyType: drop>(
        vault_manager_cap: &VaultManagerCapability,
        debt_ratio: u64,
        _witness: &StrategyType
    ): u64
    acquires Vault, VaultStrategy {
        let vault_cap = &vault_manager_cap.vault_cap;
        let vault = borrow_global_mut<Vault>(vault_cap.vault_addr);
        let strategy = borrow_global_mut<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        let old_debt_ratio = strategy.debt_ratio;

        vault.debt_ratio = vault.debt_ratio - old_debt_ratio + debt_ratio;
        strategy.debt_ratio = debt_ratio;

        // check if the strategy's updated debt ratio is valid
        assert_debt_ratio(vault.debt_ratio);

        // emit debt ratio change event
        event::emit_event(&mut strategy.debt_ratio_change_events, DebtRatioChangeEvent {
            debt_ratio,
        });

        debt_ratio
    }

    // for keeper

    /// deposits profit into the vault
    /// @param keeper_cap - a KeeperCapability
    /// @param base_coin - the Coin<BaseCoin> profit to deposit
    public(friend) fun deposit_profit<StrategyType: drop, BaseCoin>(
        keeper_cap: &KeeperCapability<StrategyType>,
        base_coin: Coin<BaseCoin>,
    )
    acquires Vault, CoinStore, VaultStrategy, VaultCoinCaps {
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

    /// makes a debt payment to the vault
    /// @param keeper_cap - a KeeperCapability
    /// @param base_coin - the Coin<BaseCoin> debt payment to make
    public(friend) fun debt_payment<StrategyType: drop, BaseCoin>(
        keeper_cap: &KeeperCapability<StrategyType>,
        base_coin: Coin<BaseCoin>,
    )
    acquires Vault, CoinStore, VaultStrategy {
        let vault_cap = &keeper_cap.vault_cap;
        update_total_debt<StrategyType>(
            vault_cap,
            0,
            coin::value(&base_coin),
            &keeper_cap.witness
        );
        deposit_base_coin(vault_cap, base_coin, &keeper_cap.witness);
    }

    /// deposits a strategy coin into the vault
    /// @param keeper_cap - a KeeperCapability
    /// @param strategy_coin - the Coin<StrategyCoin> to deposit
    public(friend) fun deposit_strategy_coin<StrategyType: drop, StrategyCoin>(
        keeper_cap: &KeeperCapability<StrategyType>,
        strategy_coin: Coin<StrategyCoin>,
    )
    acquires CoinStore, VaultStrategy {
        let vault_cap = &keeper_cap.vault_cap;
        assert_strategy_coin_correct_for_strategy_type<StrategyType, StrategyCoin>(vault_cap);
        deposit(vault_cap, strategy_coin);
    }

    /// withdraws a strategy coin from the vault
    /// @param keeper_cap - a KeeperCapability
    /// @param strategy_coin_amount - the amount of StrategyCoin to withdraw
    public(friend) fun withdraw_strategy_coin<StrategyType: drop, StrategyCoin>(
        keeper_cap: &KeeperCapability<StrategyType>,
        strategy_coin_amount: u64,
    ): Coin<StrategyCoin>
    acquires CoinStore, VaultStrategy {
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

    /// updates the debt reporting for the vault and StrategyType, returns the Coin<BaseCoin> to apply in the strategy and the profit/loss since the last harvest
    /// @param keeper_cap - a KeeperCapability
    /// @param strategy_balance - the current BaseCoin balance of the strategy
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

    /// calculates the profit, loss, and debt payment for a harvest
    /// @param vault_cap - the VaultCapability of the vault
    /// @param strategy_balance - the current BaseCoin balance of the strategy
    fun prepare_return<StrategyType: drop, BaseCoin>(
        vault_cap: &VaultCapability,
        strategy_balance: u64
    ): (u64, u64, u64)
    acquires VaultStrategy, Vault, CoinStore {

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

    // vault fields

    /// returns the address of the vault
    /// @param vault_cap - the VaultCapability of the vault
    public fun get_vault_addr(vault_cap: &VaultCapability): address {
        vault_cap.vault_addr
    }

    /// returns the base coin type of the vault
    /// @param vault_cap - the VaultCapability of the vault
    public fun get_base_coin_type(vault_cap: &VaultCapability): TypeInfo
    acquires Vault {
        let vault = borrow_global<Vault>(vault_cap.vault_addr);
        vault.base_coin_type
    }

    /// returns the performance and management fee of the vault
    /// @param vault_cap - the VaultCapability of the vault
    public fun get_fees(vault_cap: &VaultCapability): (u64, u64)
    acquires Vault {
        let vault = borrow_global<Vault>(vault_cap.vault_addr);
        (vault.management_fee, vault.performance_fee)
    }

    /// returns whether the vault is frozen for deposits
    /// @param vault_cap - the VaultCapability of the vault
    public fun is_vault_frozen(vault_cap: &VaultCapability): bool
    acquires Vault {
        let vault = borrow_global<Vault>(vault_cap.vault_addr);
        vault.deposits_frozen
    }

    /// returns the debt ratio of the vault
    /// @param vault_cap - the VaultCapability of the vault
    public fun get_debt_ratio(vault_cap: &VaultCapability): u64
    acquires Vault {
        let vault = borrow_global<Vault>(vault_cap.vault_addr);
        vault.debt_ratio
    }

    /// returns the total debt of the vault
    /// @param vault_cap - the VaultCapability of the vault
    public fun get_total_debt(vault_cap: &VaultCapability): u64
    acquires Vault {
        let vault = borrow_global<Vault>(vault_cap.vault_addr);
        vault.total_debt
    }

    /// returns whether vault_cap.vault_id == vault_id
    /// @param vault_cap - the VaultCapability of the vault
    /// @param vault_id - a vault id
    public fun vault_cap_has_id(vault_cap: &VaultCapability, vault_id: u64): bool {
        vault_cap.vault_id == vault_id
    }

    /// returns the StrategyCoin balance of the vault referenced by keeper_cap.vault_cap
    /// @param keeper_cap - a KeeperCapability
    public fun harvest_balance<StrategyType: drop, StrategyCoin>(keeper_cap: &KeeperCapability<StrategyType>): u64
    acquires CoinStore {
        balance<StrategyCoin>(&keeper_cap.vault_cap)
    }

    /// returns the balance of CoinType of the vault
    /// @param vault_cap - the VaultCapability of the vault
    public fun balance<CoinType>(vault_cap: &VaultCapability): u64
    acquires CoinStore {
        let store = borrow_global_mut<CoinStore<CoinType>>(vault_cap.vault_addr);
        coin::value(&store.coin)
    }

    /// gets the total assets of the vault, including the stored coins and debt from strategies
    /// @param vault_cap - the VaultCapability of the vault
    public fun total_assets<BaseCoin>(vault_cap: &VaultCapability): u64
    acquires Vault, CoinStore {
        assert_base_coin_correct_for_vault_cap<BaseCoin>(vault_cap);
        let vault = borrow_global<Vault>(vault_cap.vault_addr);

        let balance = balance<BaseCoin>(vault_cap);
        vault.total_debt + balance
    }

    /// returns whether the vault has a CoinStore<CoinType>
    /// @param vault_cap - the VaultCapability of the vault
    public fun has_coin<CoinType>(vault_cap: &VaultCapability): bool {
        exists<CoinStore<CoinType>>(vault_cap.vault_addr)
    }

    // strategy fields

    /// returns whether the vault has a VaultStrategy<StrategyType>
    /// @param vault_cap - the VaultCapability of the vault
    public fun has_strategy<StrategyType: drop>(vault_cap: &VaultCapability): bool {
        exists<VaultStrategy<StrategyType>>(vault_cap.vault_addr)
    }

    /// gets amount of BaseCoin StrategyType has access to as a credit line from the vault
    /// @param vault_cap - the VaultCapability of the vault
    public fun credit_available<StrategyType: drop, BaseCoin>(vault_cap: &VaultCapability): u64
    acquires Vault, VaultStrategy, CoinStore {
        assert_base_coin_correct_for_vault_cap<BaseCoin>(vault_cap);
        let vault = borrow_global<Vault>(vault_cap.vault_addr);

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

    /// determines if StrategyType is past its debt limit and returns the amount of tokens to repay
    /// @param vault_cap - the VaultCapability of the vault
    public fun debt_out_standing<StrategyType: drop, BaseCoin>(vault_cap: &VaultCapability): u64
    acquires Vault, VaultStrategy, CoinStore {
        assert_base_coin_correct_for_vault_cap<BaseCoin>(vault_cap);
        let vault = borrow_global<Vault>(vault_cap.vault_addr);
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

    /// gets the total debt for a given StrategyType
    /// @param vault_cap - the VaultCapability for the Vault
    public fun total_debt<StrategyType: drop>(vault_cap: &VaultCapability): u64
    acquires VaultStrategy {
        let strategy = borrow_global<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        strategy.total_debt
    }

    /// gets the total gain for a given StrategyType
    /// @param vault_cap - the VaultCapability for the Vault
    public fun total_gain<StrategyType: drop>(vault_cap: &VaultCapability): u64
    acquires VaultStrategy {
        let strategy = borrow_global<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        strategy.total_gain
    }

    /// gets the total loss for a given StrategyType
    /// @param vault_cap - the VaultCapability for the Vault
    public fun total_loss<StrategyType: drop>(vault_cap: &VaultCapability): u64
    acquires VaultStrategy {
        let strategy = borrow_global<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        strategy.total_loss
    }

    /// gets the debt ratio for a given StrategyType
    /// @param vault_cap - the VaultCapability for the Vault
    public fun debt_ratio<StrategyType: drop>(vault_cap: &VaultCapability): u64
    acquires VaultStrategy {
        let strategy = borrow_global<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        strategy.debt_ratio
    }

    /// gets the last report timestamp for a given StrategyType
    /// @param vault_cap - the VaultCapability for the Vault
    public fun last_report<StrategyType: drop>(vault_cap: &VaultCapability): u64
    acquires VaultStrategy {
        let strategy = borrow_global<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        strategy.last_report
    }

    /// gets the strategy coin type for a given StrategyType
    /// @param vault_cap - the VaultCapability for the Vault
    public fun get_strategy_coin_type<StrategyType: drop>(vault_cap: &VaultCapability): TypeInfo
    acquires VaultStrategy {
        let strategy = borrow_global_mut<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        strategy.strategy_coin_type
    }

    // user getters

    /// calculates amount of BaseCoin to withdraw given an amount of VaultCoin to burn
    /// @param vault_cap - the VaultCapability for the Vault
    /// @param vault_coin_amount - the amount of VaultCoin to burn
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

    /// calculates amount of VaultCoin to mint given an amount of BaseCoin to deposit
    /// @param vault_cap - the VaultCapability for the Vault
    /// @param base_coin_amount - the amount of BaseCoin to deposit
    public fun calculate_vault_coin_amount_from_base_coin_amount<BaseCoin>(
        vault_cap: &VaultCapability,
        base_coin_amount: u64
    ): u64
    acquires Vault, CoinStore {
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

    /// check if user_address has CoinStore for VaultCoin<CoinType>
    /// @param user_address - the address of the user
    public fun is_vault_coin_registered<CoinType>(user_address: address): bool {
        coin::is_account_registered<VaultCoin<CoinType>>(user_address)
    }

    /// returns the balance of VaultCoin for user_address
    /// @param user_address - the address of the user
    public fun vault_coin_balance<CoinType>(user_address: address): u64 {
        coin::balance<VaultCoin<CoinType>>(user_address)
    }

    /// returns the amount needed from a user liquidation lock
    /// @param user_liq_lock - the UserLiquidationLock
    public fun get_amount_needed<BaseCoin>(user_liq_lock: &UserLiquidationLock<BaseCoin>): u64 {
        user_liq_lock.amount_needed
    }

    // helpers

    /// creates a CoinStore for CoinType in the vault
    /// @param vault_cap - the VaultCapability for the vault
    fun add_coin<CoinType>(vault_cap: &VaultCapability) {
        let vault_acc = account::create_signer_with_capability(&vault_cap.storage_cap);
        move_to(&vault_acc, CoinStore<CoinType> {
            coin: coin::zero(),
            deposit_events: account::new_event_handle<DepositEvent>(&vault_acc),
            withdraw_events: account::new_event_handle<WithdrawEvent>(&vault_acc),
        });
    }

    /// deposits coin of CoinType into the vault
    /// @param vault_cap - the VaultCapability for the vault
    /// @param coin - the Coin<CoinType> to deposit
    fun deposit<CoinType>(vault_cap: &VaultCapability, coin: Coin<CoinType>)
    acquires CoinStore {
        let store = borrow_global_mut<CoinStore<CoinType>>(vault_cap.vault_addr);
        event::emit_event(&mut store.deposit_events, DepositEvent {
            amount: coin::value(&coin)
        });
        coin::merge(&mut store.coin, coin);
    }

    /// withdraws coin of CoinType from the vault
    /// @param vault_cap - the VaultCapability for the vault
    /// @param amount - the amount of CoinType to withdraw
    fun withdraw<CoinType>(vault_cap: &VaultCapability, amount: u64): Coin<CoinType>
    acquires CoinStore {
        let store = borrow_global_mut<CoinStore<CoinType>>(vault_cap.vault_addr);
        event::emit_event(&mut store.deposit_events, DepositEvent {
            amount
        });
        coin::extract(&mut store.coin, amount)
    }

    /// deposits BaseCoin into Vault from StrategyType
    /// @param vault_cap - the VaultCapability for the vault
    /// @param base_coin - the Coin<BaseCoin> to deposit
    /// @param witness - a reference to a StrategyType instance
    fun deposit_base_coin<StrategyType: drop, BaseCoin>(
        vault_cap: &VaultCapability,
        base_coin: Coin<BaseCoin>,
        _witness: &StrategyType
    )
    acquires CoinStore, Vault {
        assert_base_coin_correct_for_vault_cap<BaseCoin>(vault_cap);
        deposit(vault_cap, base_coin);
    }

    /// withdraws base_coin from Vault to StrategyType, updates total debt
    /// @param vault_cap - the VaultCapability for the vault
    /// @param amount - the amount of BaseCoin to withdraw
    /// @param witness - a reference to a StrategyType instance
    fun withdraw_base_coin<StrategyType: drop, BaseCoin>(
        vault_cap: &VaultCapability,
        amount: u64,
        witness: &StrategyType
    ): Coin<BaseCoin>
    acquires CoinStore, Vault, VaultStrategy {
        assert_base_coin_correct_for_vault_cap<BaseCoin>(vault_cap);

        assert!(credit_available<StrategyType, BaseCoin>(vault_cap) >= amount, ERR_INSUFFICIENT_CREDIT);

        update_total_debt(vault_cap, amount, 0, witness);

        withdraw(vault_cap, amount)
    }

    /// updates the total debt of the vault and strategy
    /// @param vault_cap - the VaultCapability for the vault
    /// @param credit - the amount of BaseCoin credited to StrategyType
    /// @param debt_payment - the amount of BaseCoin debt paid back to the vault
    /// @param witness - a reference to a StrategyType instance
    fun update_total_debt<StrategyType: drop>(
        vault_cap: &VaultCapability,
        credit: u64,
        debt_payment: u64,
        _witness: &StrategyType
    )
    acquires Vault, VaultStrategy {
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

    /// assesses fees for a given profit, updates the StrategyType last_report timestamp and total gain for the vault
    /// @param profit - a reference to the Coin<BaseCoin> representing the profit
    /// @param vault_cap - the VaultCapability for the vault
    /// @param witness - a reference to a StrategyType instance
    fun assess_fees<StrategyType: drop, BaseCoin>(
        profit: &Coin<BaseCoin>,
        vault_cap: &VaultCapability,
        witness: &StrategyType
    )
    acquires VaultStrategy, Vault, CoinStore, VaultCoinCaps {
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

    /// report a gain for StrategyType on the vault
    /// @param vault_cap - the VaultCapability for the vault
    /// @param gain - the amount of gain to report
    /// @param _witness - a reference to a StrategyType instance
    fun report_gain<StrategyType: drop>(vault_cap: &VaultCapability, gain: u64, _witness: &StrategyType)
    acquires VaultStrategy {
        let strategy = borrow_global_mut<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        strategy.total_gain = strategy.total_gain + gain;
        // emit gain event
        event::emit_event(&mut strategy.gain_events, GainEvent {
            gain,
        });
    }

    /// report a loss for StrategyType on the vault
    /// @param vault_cap - the VaultCapability for the vault
    /// @param loss - the amount of loss to report
    /// @param _witness - a reference to a StrategyType instance
    fun report_loss<StrategyType: drop>(vault_cap: &VaultCapability, loss: u64, _witness: &StrategyType)
    acquires Vault, VaultStrategy {
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

    /// report harvest timestamp for StrategyType on the vault
    /// @param vault_cap - the VaultCapability for the vault
    /// @param _witness - a reference to a StrategyType instance
    fun report_timestamp<StrategyType: drop>(vault_cap: &VaultCapability, _witness: &StrategyType)
    acquires VaultStrategy {
        let timestamp = timestamp::now_seconds();
        let strategy = borrow_global_mut<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        strategy.last_report = timestamp;
        event::emit_event(&mut strategy.harvest_events, HarvestEvent {
            timestamp
        });
    }

    // asserts

    /// asserts that BaseCoin is correct for the vault
    /// @param vault_cap - the VaultCapability for the vault
    fun assert_base_coin_correct_for_vault_cap<BaseCoin> (vault_cap: &VaultCapability)
    acquires Vault {
        let vault = borrow_global<Vault>(vault_cap.vault_addr);
        assert!(vault.base_coin_type == type_info::type_of<BaseCoin>(), ERR_INCORRECT_BASE_COIN);
    }

    /// asserts that StrategyCoin is correct for StrategyType on the vault
    /// @param vault_cap - the VaultCapability for the vault
    fun assert_strategy_coin_correct_for_strategy_type<StrategyType: drop, StrategyCoin> (vault_cap: &VaultCapability)
    acquires VaultStrategy {
        let strategy = borrow_global<VaultStrategy<StrategyType>>(vault_cap.vault_addr);
        assert!(strategy.strategy_coin_type == type_info::type_of<StrategyCoin>(), ERR_INCORRECT_STRATEGY_COIN);
    }

    /// asserts that the debt ratio is valid
    /// @param debt_ratio - the debt ratio in BPS
    fun assert_debt_ratio(debt_ratio: u64) {
        assert!(debt_ratio <= MAX_DEBT_RATIO_BPS, ERR_INVALID_DEBT_RATIO);
    }

    /// asserts that the fee amounts are valid
    /// @param management_fee - the management fee in BPS
    /// @param performance_fee - the performance fee in BPS
    fun assert_fee_amounts(management_fee: u64, performance_fee: u64) {
        assert!(management_fee <= MAX_MANAGEMENT_FEE && performance_fee <= MAX_PERFORMANCE_FEE, ERR_INVALID_FEE);
    }

    /// asserts that the vault is active
    /// @param vault_cap - the VaultCapability for the vault
    fun assert_vault_active(vault_cap: &VaultCapability)
    acquires Vault {
        assert!(!is_vault_frozen(vault_cap), ERR_VAULT_FROZEN);
    }

    /// asserts that the vault is not active
    /// @param vault_cap - the VaultCapability for the vault
    fun assert_vault_not_active(vault_cap: &VaultCapability)
    acquires Vault {
        assert!(is_vault_frozen(vault_cap), ERR_VAULT_NOT_FROZEN);
    }

    // test functions

    #[test_only]
    public fun new_test<BaseCoin>(
        governance: &signer,
        vault_id: u64,
        management_fee: u64,
        performance_fee: u64
    ): VaultCapability acquires VaultCoinCap {
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
        vault_manager_cap: &VaultManagerCapability,
        debt_ratio: u64,
        witness: &StrategyType
    ) acquires VaultStrategy, Vault {
        update_strategy_debt_ratio<StrategyType>(
            vault_manager_cap,
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