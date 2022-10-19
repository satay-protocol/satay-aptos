module satay::vault {
    use std::signer;
    use std::string;
    use std::option;

    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability, FreezeCapability};
    use aptos_std::type_info::TypeInfo;
    use aptos_std::type_info;
    use satay::aptos_usdt_strategy;
    use aptos_framework::timestamp;

    const SECS_PER_YEAR: u64 = 31556952; // 365.2425 days
    const MAX_BPS: u64 = 10000; // 100%
    const MANAGEMENT_FEE: u64 = 200; // 2%

    const ERR_NO_USER_POSITION: u64 = 101;
    const ERR_NOT_ENOUGH_USER_POSITION: u64 = 102;
    const ERR_COIN: u64 = 103;

    struct CoinStore<phantom CoinType> has key {
        coin: Coin<CoinType>
    }

    struct Vault has key {
        base_coin_type: TypeInfo,
        last_report: u64,
        total_debt: u64
    }

    struct VaultCapability has store, drop {
        storage_cap: SignerCapability,
        vault_id: u64,
        vault_addr: address,
        // token amount taken by strategy
    }

    struct Caps<phantom CoinType> has key {
        mint_cap: MintCapability<CoinType>,
        freeze_cap: FreezeCapability<CoinType>,
        burn_cap: BurnCapability<CoinType>
    }

    struct VaultCoin<phantom BaseCoin> has key {}

    struct VaultStrategy<phantom StrategyType> has key, store {
        base_coin_type: TypeInfo
    }

    // create new vault with BaseCoin as its base coin type
    public fun new<BaseCoin>(vault_owner: &signer, seed: vector<u8>, vault_id: u64): VaultCapability {
        // create a resource account for the vault managed by the sender
        let (vault_acc, storage_cap) = account::create_resource_account(vault_owner, seed);

        // create a new vault and move it to the vault account
        move_to(
            &vault_acc,
            Vault {
                base_coin_type: type_info::type_of<BaseCoin>(),
                total_debt: 0,
                last_report: 0
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
            vault_id
        };
        add_coin<BaseCoin>(&vault_cap);
        vault_cap
    }

    // check if a vault has a CoinStore for CoinType
    public fun has_coin<CoinType>(vault_cap: &VaultCapability): bool {
        exists<CoinStore<CoinType>>(vault_cap.vault_addr)
    }

    // create a new CoinStore for CoinType
    public fun add_coin<CoinType>(vault_cap: &VaultCapability) {
        let owner = account::create_signer_with_capability(&vault_cap.storage_cap);
        move_to(
            &owner,
            CoinStore<CoinType> { coin: coin::zero() }
        );
    }

    // // deposit coin of CoinType into the vault
    public fun deposit<CoinType>(vault_cap: &VaultCapability, coin: Coin<CoinType>) acquires CoinStore {
        let store = borrow_global_mut<CoinStore<CoinType>>(vault_cap.vault_addr);
        coin::merge(&mut store.coin, coin);
    }
    //
    // // withdraw coin of CoinType from the vault
    public fun withdraw<CoinType>(vault_cap: &VaultCapability, amount: u64): Coin<CoinType> acquires CoinStore {
        let store = borrow_global_mut<CoinStore<CoinType>>(vault_cap.vault_addr);
        coin::extract(&mut store.coin, amount)
    }
    //
    // // add amount to user_addr position in the vault table associated with vault_cap
    fun mint_vault_coin<BaseCoin>(user: &signer, vault_cap: &VaultCapability, amount: u64) acquires Caps {
        let caps = borrow_global<Caps<VaultCoin<BaseCoin>>>(vault_cap.vault_addr);
        let coins = coin::mint<VaultCoin<BaseCoin>>(amount, &caps.mint_cap);
        if(!is_vault_coin_registered<BaseCoin>(signer::address_of(user))){
            coin::register<VaultCoin<BaseCoin>>(user);
        };
        coin::deposit(signer::address_of(user), coins);
    }

    // remove amount from user_addr position in the vault table associated with vault_cap
    fun burn_vault_coins<BaseCoin>(user: &signer, vault_cap: &VaultCapability, amount: u64) acquires Caps {
        let caps = borrow_global<Caps<VaultCoin<BaseCoin>>>(vault_cap.vault_addr);
        coin::burn(coin::withdraw(user, amount), &caps.burn_cap);
    }

    // for satay

    // deposit base_coin into the vault
    // ensure that BaseCoin is the base coin type of the vault
    // update pending coins amount
    public fun deposit_as_user<BaseCoin>(
        user: &signer,
        vault_cap: &mut VaultCapability,
        base_coin: Coin<BaseCoin>
    ) acquires Vault, CoinStore, Caps {
        {
            let vault = borrow_global_mut<Vault>(vault_cap.vault_addr);
            assert!(vault.base_coin_type == type_info::type_of<BaseCoin>(), ERR_COIN);
        };
        issue_shares<BaseCoin>(user, coin::value(&base_coin), vault_cap);
        deposit(vault_cap, base_coin);
    }

    // withdraw base_coin from the vault
    // ensure that BaseCoin is the base coin type of the vault
    public fun withdraw_as_user<BaseCoin>(
        user: &signer,
        vault_cap: &mut VaultCapability,
        share_amount: u64
    ): Coin<BaseCoin> acquires CoinStore, Vault, Caps {
        {
            let vault = borrow_global<Vault>(vault_cap.vault_addr);
            assert!(vault.base_coin_type == type_info::type_of<BaseCoin>(), ERR_COIN);
        };

        assessFees<BaseCoin>(vault_cap);
        // calculate token amount per share
        let share_total_supply = option::extract(&mut coin::supply<VaultCoin<BaseCoin>>());
        let amount = asset_total_balance<BaseCoin>(vault_cap) * share_amount / (share_total_supply as u64);
        let vault_balance = balance<BaseCoin>(vault_cap);
        if (amount > vault_balance) {
            // withdraw from strategy
            withdraw_from_strategy(vault_cap.vault_id, amount - vault_balance);
        };
        burn_vault_coins<BaseCoin>(user, vault_cap, amount);

        withdraw<BaseCoin>(vault_cap, amount)
    }

    public fun assessFees<BaseCoin>(vault_cap: &VaultCapability) acquires Vault, Caps {
        // management fee
        let vault = borrow_global_mut<Vault>(vault_cap.vault_addr);
        let caps = borrow_global<Caps<VaultCoin<BaseCoin>>>(vault_cap.vault_addr);
        let management_fee_amount = vault.total_debt * (vault.last_report - timestamp::now_seconds()) * MANAGEMENT_FEE / MAX_BPS / SECS_PER_YEAR;
        let coins = coin::mint<VaultCoin<BaseCoin>>(management_fee_amount, &caps.mint_cap);

        // transfer to manager
        coin::deposit<VaultCoin<BaseCoin>>(@manager, coins)
    }

    public fun approve_strategy<StrategyType: drop>(
        vault_cap: &VaultCapability,
        position_type: TypeInfo
    ) {
        let vault_acc = account::create_signer_with_capability(&vault_cap.storage_cap);
        move_to(&vault_acc, VaultStrategy<StrategyType>{ base_coin_type: position_type});
    }

    fun withdraw_from_strategy(vault_id: u64, amount: u64) {
        aptos_usdt_strategy::liquidate_strategy(vault_id, amount);
    }

    public fun issue_shares<CoinType>(user: &signer, amount: u64, vault_cap: &VaultCapability) acquires CoinStore, Caps, Vault {
        // share token calculation logic
        // share amount = base coin amount * vault coin total supply / current baseToken value in total
        let _share_amount;
        let share_total_supply = option::extract<u128>(&mut coin::supply<VaultCoin<CoinType>>());
        let vault = borrow_global_mut<Vault>(vault_cap.vault_addr);

        if (share_total_supply == 0) {
            _share_amount = amount;
            vault.last_report = timestamp::now_seconds();
        } else {
            _share_amount = asset_total_balance<CoinType>(vault_cap);
        };
        mint_vault_coin<CoinType>(user, vault_cap, amount);
    }

    public fun has_strategy<StrategyType: drop>(
        vault_cap: &VaultCapability
    ) : bool {
        let vault_acc = account::create_signer_with_capability(&vault_cap.storage_cap);
        exists<VaultStrategy<StrategyType>>(signer::address_of(&vault_acc))
    }

    // check if vault_id matches the vault_id of vault_cap
    public fun vault_cap_has_id(vault_cap: &VaultCapability, vault_id: u64): bool {
        vault_cap.vault_id == vault_id
    }

    // check the CoinType balance of the vault
    public fun balance<CoinType>(vault_cap: &VaultCapability): u64 acquires CoinStore {
        let store = borrow_global_mut<CoinStore<CoinType>>(vault_cap.vault_addr);
        coin::value(&store.coin)
    }

    public fun lp_balance<CoinType>(vault_cap: &VaultCapability): u64 {
        coin::balance<CoinType>(vault_cap.vault_addr)
    }

    public fun asset_total_balance<CoinType>(vault_cap: &VaultCapability): u64 acquires CoinStore, Vault {
        let store = borrow_global_mut<CoinStore<CoinType>>(vault_cap.vault_addr);
        total_debt(vault_cap) + coin::value(&store.coin)
    }

    public fun increase_total_debt(vault_cap: &mut VaultCapability, amount: u64) acquires Vault {
        let vault = borrow_global_mut<Vault>(vault_cap.vault_addr);
        vault.total_debt = vault.total_debt + amount;
    }

    public fun decrease_total_debt(vault_cap: &mut VaultCapability, amount: u64) acquires Vault {
        let vault = borrow_global_mut<Vault>(vault_cap.vault_addr);
        vault.total_debt = vault.total_debt - amount;
    }

    public fun total_debt(vault_cap: &VaultCapability): u64 acquires Vault {
        let vault = borrow_global_mut<Vault>(vault_cap.vault_addr);
        vault.total_debt
    }

    public fun is_vault_coin_registered<CoinType>(user_address : address): bool {
        coin::is_account_registered<VaultCoin<CoinType>>(user_address)
    }

    public fun vault_coin_balance<CoinType>(user_address : address): u64 {
        coin::balance<VaultCoin<CoinType>>(user_address)
    }

    #[test_only]
    public fun new_test<BaseCoin>(vault_owner: &signer, seed: vector<u8>, vault_id: u64): VaultCapability {
        // create a resource account for the vault managed by the sender
        let (vault_acc, storage_cap) = account::create_resource_account(vault_owner, seed);

        // create a new vault and move it to the vault account
        move_to(
            &vault_acc,
            Vault {
                base_coin_type: type_info::type_of<BaseCoin>(),
                total_debt: 0,
                last_report: 0
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
}