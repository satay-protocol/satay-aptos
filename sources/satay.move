module satay::satay {
    use std::option::{Self, Option};
    use std::signer;

    use aptos_std::type_info::TypeInfo;
    use aptos_std::table::{Self, Table};

    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::account::{Self, SignerCapability};

    use satay::global_config;
    use satay::vault::{Self, VaultCapability};
    use satay_vault_coin::vault_coin::VaultCoin;
    use satay::vault_coin_account;

    friend satay::base_strategy;

    const ERR_NOT_ENOUGH_PRIVILEGES: u64 = 1;
    const ERR_MANAGER: u64 = 2;
    const ERR_STRATEGY: u64 = 3;
    const ERR_COIN: u64 = 4;
    const ERR_VAULT_CAP: u64 = 5;
    const ERR_VAULT_NO_STRATEGY: u64 = 6;

    struct ManagerAccount has key {
        next_vault_id: u64,
        vaults: Table<u64, VaultInfo>,
        vault_coin_account_signer_cap: SignerCapability
    }

    struct VaultInfo has store {
        // VaultCapability of the vault.
        // `Option` here is required to allow lending the capability object to the strategy.
        vault_cap: Option<VaultCapability>,
    }

    // returned by lock_vault to ensure a subsequent call to unlock_vault
    struct VaultCapLock<phantom StrategyType: drop> {
        vault_id: u64,
    }

    // create manager account and store in sender's account
    public entry fun initialize(
        satay: &signer
    ) {
        assert!(signer::address_of(satay) == @satay, ERR_NOT_ENOUGH_PRIVILEGES);
        let signer_cap = vault_coin_account::retrieve_signer_cap(satay);
        move_to(satay, ManagerAccount {
            vaults: table::new(),
            next_vault_id: 0,
            vault_coin_account_signer_cap: signer_cap
        });
        global_config::initialize(satay);
    }

    // governance functions

    // create new vault for BaseCoin
    public entry fun new_vault<BaseCoin>(
        governance: &signer,
        management_fee: u64,
        performance_fee: u64
    ) acquires ManagerAccount {
        global_config::assert_governance(governance);

        assert_manager_initialized();
        let account = borrow_global_mut<ManagerAccount>(@satay);

        let vault_coin_signer_cap = &account.vault_coin_account_signer_cap;
        let vault_coin_account_signer = account::create_signer_with_capability(vault_coin_signer_cap);

        // get vault id and update next id
        let vault_id = account.next_vault_id;
        account.next_vault_id = account.next_vault_id + 1;

        // create vault and add to manager vaults table
        let vault_cap = vault::new<BaseCoin>(
            &vault_coin_account_signer,
            vault_id,
            management_fee,
            performance_fee
        );
        table::add(
            &mut account.vaults,
            vault_id,
            VaultInfo {
                vault_cap: option::some(vault_cap),
            }
        );
    }

    // vault manager fucntions

    public entry fun update_vault_fee(
        vault_manager: &signer,
        vault_id: u64,
        management_fee: u64,
        performance_fee: u64
    ) acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global_mut<ManagerAccount>(@satay);

        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        let vault_cap = option::extract(&mut vault_info.vault_cap);

        let vault_manager_cap = vault::get_vault_manager_capability(vault_manager, vault_cap);
        vault::update_fee(
            &vault_manager_cap,
            management_fee,
            performance_fee
        );

        option::fill(&mut vault_info.vault_cap, vault::destroy_vault_manager_capability(vault_manager_cap));
    }

    public entry fun freeze_vault(
        vault_manager: &signer,
        vault_id: u64
    ) acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global_mut<ManagerAccount>(@satay);

        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        let vault_cap = option::extract(&mut vault_info.vault_cap);

        let vault_manager_cap = vault::get_vault_manager_capability(vault_manager, vault_cap);
        vault::freeze_vault(
            &vault_manager_cap
        );

        option::fill(&mut vault_info.vault_cap, vault::destroy_vault_manager_capability(vault_manager_cap));
    }

    public entry fun unfreeze_vault(
        vault_manager: &signer,
        vault_id: u64
    ) acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global_mut<ManagerAccount>(@satay);

        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        let vault_cap = option::extract(&mut vault_info.vault_cap);

        let vault_manager_cap = vault::get_vault_manager_capability(vault_manager, vault_cap);
        vault::unfreeze_vault(
            &vault_manager_cap
        );

        option::fill(&mut vault_info.vault_cap, vault::destroy_vault_manager_capability(vault_manager_cap));
    }

    // allows Strategy to get VaultCapability of vault_id of manager_addr
    public(friend) fun approve_strategy<StrategyType: drop, StrategyCoin>(
        vault_manager: &signer,
        vault_id: u64,
        debt_ratio: u64,
        witness: &StrategyType
    ) acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global_mut<ManagerAccount>(@satay);

        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        let vault_cap = option::extract(&mut vault_info.vault_cap);

        let vault_manager_cap = vault::get_vault_manager_capability(vault_manager, vault_cap);
        vault::approve_strategy<StrategyType, StrategyCoin>(
            &vault_manager_cap,
            debt_ratio,
            witness
        );

        option::fill(&mut vault_info.vault_cap, vault::destroy_vault_manager_capability(vault_manager_cap));
    }

    // update the strategy debt ratio
    public(friend) fun update_strategy_debt_ratio<StrategyType: drop>(
        vault_manager: &signer,
        vault_id: u64,
        debt_ratio: u64,
        witness: &StrategyType
    ): u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global_mut<ManagerAccount>(@satay);

        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        let vault_cap = option::extract(&mut vault_info.vault_cap);
        assert!(vault::has_strategy<StrategyType>(&vault_cap), ERR_VAULT_NO_STRATEGY);

        let vault_manager_cap = vault::get_vault_manager_capability(
            vault_manager,
            vault_cap
        );
        vault::update_strategy_debt_ratio<StrategyType>(
            &vault_manager_cap,
            debt_ratio,
            witness
        );

        option::fill(&mut vault_info.vault_cap, vault::destroy_vault_manager_capability(vault_manager_cap));

        debt_ratio
    }

    // user functions

    // user deposits amount of BaseCoin into vault_id of manager_addr
    public entry fun deposit<BaseCoin>(
        user: &signer,
        vault_id: u64,
        amount: u64
    ) acquires ManagerAccount {
        let base_coins = coin::withdraw<BaseCoin>(user, amount);

        let vault_coins = deposit_as_user(user, vault_id, base_coins);

        let user_addr = signer::address_of(user);
        if(!vault::is_vault_coin_registered<BaseCoin>(user_addr)){
            coin::register<VaultCoin<BaseCoin>>(user);
        };
        coin::deposit(user_addr, vault_coins);
    }

    public fun deposit_as_user<BaseCoin>(
        user: &signer,
        vault_id: u64,
        base_coins: Coin<BaseCoin>
    ): Coin<VaultCoin<BaseCoin>> acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global_mut<ManagerAccount>(@satay);
        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        let vault_cap = option::extract(&mut vault_info.vault_cap);

        let user_cap = vault::get_user_capability(
            user,
            vault_cap,
        );

        let vault_coins = vault::deposit_as_user(&user_cap, base_coins);

        let (
            vault_cap,
            _
        ) = vault::destroy_user_capability(user_cap);

        option::fill(&mut vault_info.vault_cap, vault_cap);

        vault_coins
    }

    // user withdraws amount of BaseCoin from vault_id of manager_addr
    public entry fun withdraw<BaseCoin>(
        user: &signer,
        vault_id: u64,
        amount: u64
    ) acquires ManagerAccount {
        let vault_coins = coin::withdraw<VaultCoin<BaseCoin>>(user, amount);

        let base_coins = withdraw_as_user(user, vault_id, vault_coins);

        let user_addr = signer::address_of(user);
        if(!coin::is_account_registered<BaseCoin>(user_addr)){
            coin::register<BaseCoin>(user);
        };
        coin::deposit(user_addr, base_coins);
    }

    public fun withdraw_as_user<BaseCoin>(
        user: &signer,
        vault_id: u64,
        vault_coins: Coin<VaultCoin<BaseCoin>>
    ): Coin<BaseCoin> acquires ManagerAccount {
        let account = borrow_global_mut<ManagerAccount>(@satay);
        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        let vault_cap = option::extract(&mut vault_info.vault_cap);

        let user_cap = vault::get_user_capability(
            user,
            vault_cap,
        );

        let base_coins = vault::withdraw_as_user<BaseCoin>(&user_cap, vault_coins);

        let (
            vault_cap,
            _
        ) = vault::destroy_user_capability(user_cap);
        option::fill(&mut vault_info.vault_cap, vault_cap);

        base_coins
    }

    // strategy functions

    // get VaultCapability of vault_id of manager_addr
    // StrategyType must be approved
    public(friend) fun lock_vault<StrategyType: drop>(
        vault_id: u64,
        _witness: &StrategyType
    ): (VaultCapability, VaultCapLock<StrategyType>) acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global_mut<ManagerAccount>(@satay);

        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);

        // assert that strategy is approved for vault
        assert!(
            vault::has_strategy<StrategyType>(option::borrow(&vault_info.vault_cap)),
            ERR_STRATEGY
        );

        let vault_cap = option::extract(&mut vault_info.vault_cap);
        let stop_handle = VaultCapLock {
            vault_id,
        };
        (vault_cap, stop_handle)
    }

    // returns vault_cap to vault after strategy has completed operation
    public(friend) fun unlock_vault<StrategyType: drop>(
        vault_capability: VaultCapability,
        stop_handle: VaultCapLock<StrategyType>
    ) acquires ManagerAccount {
        // assert that correct VaultCapLock for VaultCapability is passed
        assert_vault_cap_and_stop_handle_match(&vault_capability, &stop_handle);

        let VaultCapLock<StrategyType> {
            vault_id,
        } = stop_handle;

        let account = borrow_global_mut<ManagerAccount>(@satay);
        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        assert!(
            vault::has_strategy<StrategyType>(&vault_capability),
            ERR_STRATEGY
        );
        option::fill(&mut vault_info.vault_cap, vault_capability);
    }

    // getter functions

    // ManagerAccount fields

    public fun get_next_vault_id() : u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        account.next_vault_id
    }

    // vault cap lock fields

    public fun get_vault_id<StrategyType: drop>(
        vault_cap_lock: &VaultCapLock<StrategyType>
    ): u64 {
        vault_cap_lock.vault_id
    }

    // vault fields

    // get vault address for vault_id
    public fun get_vault_address_by_id(
        vault_id: u64
    ): address acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::get_vault_addr(vault_cap)
    }

    // get base coin for vault_id
    public fun get_base_coin_by_id(
        vault_id: u64
    ): TypeInfo acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::get_base_coin_type(vault_cap)
    }

    // get fees for vault_id
    public fun get_vault_fees(vault_id: u64): (u64, u64) acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        vault::get_fees(option::borrow(&vault_info.vault_cap))
    }

    // get deposits_frozen for vault_id
    public fun is_vault_frozen(vault_id: u64): bool acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        vault::is_vault_frozen(option::borrow(&vault_info.vault_cap))
    }

    // get debt ratio for vault_id
    public fun get_vault_debt_ratio(vault_id: u64): u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        vault::get_debt_ratio(option::borrow(&vault_info.vault_cap))
    }

    // get total debt for vault_id
    public fun get_total_debt(vault_id: u64): u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        vault::get_total_debt(option::borrow(&vault_info.vault_cap))
    }

    // get total assets for vault_id
    public fun get_total_assets<BaseCoin>(vault_id: u64): u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::total_assets<BaseCoin>(vault_cap)
    }

    // strategy fields

    // checks if vault_id for manager has StrategyType approved
    public fun has_strategy<StrategyType: drop>(
        vault_id: u64,
    ) : bool acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        vault::has_strategy<StrategyType>(option::borrow(&vault_info.vault_cap))
    }

    // gets total debt for StrategyType for vault_id
    public fun get_strategy_total_debt<StrategyType: drop>(
        vault_id: u64,
    ) : u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::total_debt<StrategyType>(vault_cap)
    }

    // gets debt ratio for StrategyType for vault_id
    public fun get_strategy_debt_ratio<StrategyType: drop>(
        vault_id: u64,
    ) : u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::debt_ratio<StrategyType>(vault_cap)
    }

    // gets credit availale for StrategyType for vault_id
    public fun get_credit_available<StrategyType: drop, BaseCoin>(
        vault_id: u64,
    ): u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::credit_available<StrategyType, BaseCoin>(vault_cap)
    }

    // gets outstanding debt for StrategyType for vault_id
    public fun get_debt_out_standing<StrategyType: drop, BaseCoin>(
        vault_id: u64,
    ): u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::debt_out_standing<StrategyType, BaseCoin>(vault_cap)
    }

    // gets last report for StrategyType for vault_id
    public fun get_last_report<StrategyType: drop>(
        vault_id: u64,
    ): u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::last_report<StrategyType>(vault_cap)
    }

    // gets the strategy coin type for StrategyType for vault_id
    public fun get_strategy_coin_type<StrategyType: drop>(
        vault_id: u64,
    ): TypeInfo acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::get_strategy_coin_type<StrategyType>(vault_cap)
    }

    // get total gain for StrategyType for vault_id
    public fun get_total_gain<StrategyType: drop, BaseCoin>(
        vault_id: u64,
    ): u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::total_gain<StrategyType>(vault_cap)
    }

    // get total loss for StrategyType for vault_id
    public fun get_total_loss<StrategyType: drop, BaseCoin>(
        vault_id: u64,
    ): u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::total_loss<StrategyType>(vault_cap)
    }

    // user calculations

    // get vault coin amount for base coin amount for vault_id
    public fun get_vault_coin_amount<BaseCoin>(
        vault_id: u64,
        base_coin_amount: u64,
    ): u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::calculate_vault_coin_amount_from_base_coin_amount<BaseCoin>(vault_cap, base_coin_amount)
    }

    // get base coin amount for vault coin amount for vault_id
    public fun get_base_coin_amount<BaseCoin>(
        vault_id: u64,
        vault_coin_amount: u64,
    ): u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::calculate_base_coin_amount_from_vault_coin_amount<BaseCoin>(vault_cap, vault_coin_amount)
    }

    // assert statements

    public fun assert_base_coin_correct_for_vault<BaseCoin>(
        vault_id: u64,
    ) acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global<ManagerAccount>(@satay);
        let vault_info = table::borrow(&account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::assert_base_coin_correct_for_vault_cap<BaseCoin>(vault_cap);
    }

    fun assert_manager_initialized() {
        assert!(exists<ManagerAccount>(@satay), ERR_MANAGER);
    }

    fun assert_vault_cap_and_stop_handle_match<StrategyType: drop>(
        vault_cap: &VaultCapability,
        stop_handle: &VaultCapLock<StrategyType>,
    ) {
        let vault_id = stop_handle.vault_id;
        assert!(
            vault::vault_cap_has_id(vault_cap, vault_id),
            ERR_VAULT_CAP
        );
    }

    #[test_only]
    public fun open_vault(vault_id: u64): VaultCapability acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global_mut<ManagerAccount>(@satay);
        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        option::extract(&mut vault_info.vault_cap)
    }

    #[test_only]
    public fun close_vault(vault_id: u64, vault_cap: VaultCapability) acquires ManagerAccount {
        assert!(
            vault::vault_cap_has_id(&vault_cap, vault_id),
            ERR_VAULT_CAP
        );
        let account = borrow_global_mut<ManagerAccount>(@satay);
        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        option::fill(&mut vault_info.vault_cap, vault_cap);
    }

    #[test_only]
    public fun test_lock_vault<StrategyType: drop>(
        vault_id: u64,
        witness: &StrategyType,
    ): (VaultCapability, VaultCapLock<StrategyType>) acquires ManagerAccount {
        lock_vault<StrategyType>(
            vault_id,
            witness
        )
    }

    #[test_only]
    public fun test_unlock_vault<StrategyType: drop>(
        vault_cap: VaultCapability,
        stop_handle: VaultCapLock<StrategyType>,
    ) acquires ManagerAccount {
        unlock_vault<StrategyType>(
            vault_cap,
            stop_handle,
        )
    }

    #[test_only]
    public fun test_approve_strategy<StrategyType: drop, StrategyCoin>(
        vault_manager: &signer,
        vault_id: u64,
        debt_ratio: u64,
        witness: StrategyType,
    ) acquires ManagerAccount {
        approve_strategy<StrategyType, StrategyCoin>(
            vault_manager,
            vault_id,
            debt_ratio,
            &witness
        );
    }

    #[test_only]
    public fun test_update_strategy_debt_ratio<StrategyType: drop>(
        vault_manager: &signer,
        vault_id: u64,
        debt_ratio: u64,
        witness: StrategyType
    ) acquires ManagerAccount {
        update_strategy_debt_ratio<StrategyType>(
            vault_manager,
            vault_id,
            debt_ratio,
            &witness
        );
    }

    #[test_only]
    public fun balance<CoinType>(manager_addr: address, vault_id: u64) : u64 acquires ManagerAccount {
        assert_manager_initialized();
        let account = borrow_global_mut<ManagerAccount>(manager_addr);
        let vault_info = table::borrow_mut(&mut account.vaults, vault_id);
        let vault_cap = option::borrow(&vault_info.vault_cap);
        vault::balance<CoinType>(vault_cap)
    }

    #[test_only]
    public fun test_assert_manager_initialized() {
        assert_manager_initialized();
    }

    #[test_only]
    public fun test_assert_vault_cap_and_stop_handle_match<StrategyType: drop>(
        vault_cap: &VaultCapability,
        stop_handle: &VaultCapLock<StrategyType>,
    ) {
        assert_vault_cap_and_stop_handle_match<StrategyType>(vault_cap, stop_handle);
    }

    #[test_only]
    public fun test_get_vault_address_by_id(vault_id: u64) : address acquires ManagerAccount {
        get_vault_address_by_id(vault_id)
    }
}