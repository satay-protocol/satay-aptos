module satay::vault {
    use std::signer;

    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::coin::{Self, Coin};
    use aptos_std::table::{Self, Table};
    use aptos_std::type_info::TypeInfo;
    use aptos_std::type_info;

    friend satay::satay;

    const ERR_NO_USER_POSITION: u64 = 101;
    const ERR_NOT_ENOUGH_USER_POSITION: u64 = 102;
    const ERR_COIN: u64 = 103;

    struct CoinStore<phantom CoinType> has key {
        coin: Coin<CoinType>
    }

    struct Vault has key {
        // mapping from user address to input amount
        user_positions: Table<address, u64>,
        // input and withdraw token
        base_coin_type: TypeInfo,
        // amount of tokens pending strategy application
        pending_coins_amount: u64,
    }

    struct VaultCapability has drop, store {
        storage_cap: SignerCapability,
        vault_id: u64,
        vault_addr: address,
    }

    // create new vault with BaseCoin as its base coin type
    public fun new<BaseCoin>(vault_owner: &signer, seed: vector<u8>, vault_id: u64): VaultCapability {
        // create a resource account for the vault managed by the sender
        let (vault_acc, storage_cap) = account::create_resource_account(vault_owner, seed);
        // create a new vault and move it to the vault account
        move_to(
            &vault_acc,
            Vault {
                user_positions: table::new(),
                base_coin_type: type_info::type_of<BaseCoin>(),
                pending_coins_amount: 0
            }
        );
        VaultCapability { storage_cap, vault_addr: signer::address_of(&vault_acc), vault_id }
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

    // for strategies
    // get all coins pending strategy application
    public fun fetch_pending_coins<BaseCoin>(vault_cap: &VaultCapability): Coin<BaseCoin> acquires Vault, CoinStore {
        let vault = borrow_global_mut<Vault>(vault_cap.vault_addr);
        let pending_coin_amount = vault.pending_coins_amount;
        // fast tracking special case
        if (pending_coin_amount == 0) {
            return coin::zero()
        };
        vault.pending_coins_amount = 0;

        withdraw(vault_cap, pending_coin_amount)
    }

    // deposit coin of CoinType into the vault
    public fun deposit<CoinType>(vault_cap: &VaultCapability, coin: Coin<CoinType>) acquires CoinStore {
        let store = borrow_global_mut<CoinStore<CoinType>>(vault_cap.vault_addr);
        coin::merge(&mut store.coin, coin);
    }

    // withdraw coin of CoinType from the vault
    public fun withdraw<CoinType>(vault_cap: &VaultCapability, amount: u64): Coin<CoinType> acquires CoinStore {
        let store = borrow_global_mut<CoinStore<CoinType>>(vault_cap.vault_addr);
        coin::extract(&mut store.coin, amount)
    }

    // add amount to user_addr position in the vault table associated with vault_cap
    public fun add_user_position(vault_cap: &VaultCapability, user_addr: address, amount: u64) acquires Vault {
        let vault_acc = account::create_signer_with_capability(&vault_cap.storage_cap);
        let vault_addr = signer::address_of(&vault_acc);
        let vault = borrow_global_mut<Vault>(vault_addr);
        let user_position =
            table::borrow_mut_with_default(&mut vault.user_positions, user_addr, 0);
        *user_position = *user_position + amount;
    }

    // remove amount from user_addr position in the vault table associated with vault_cap
    public fun remove_user_position(vault_cap: &VaultCapability, user_addr: address, amount: u64) acquires Vault {
        let vault_acc = account::create_signer_with_capability(&vault_cap.storage_cap);
        let vault_addr = signer::address_of(&vault_acc);

        let vault = borrow_global_mut<Vault>(vault_addr);
        assert!(
            table::contains(&vault.user_positions, user_addr),
            ERR_NO_USER_POSITION
        );

        let user_position = table::borrow_mut(&mut vault.user_positions, user_addr);
        assert!(*user_position >= amount, ERR_NOT_ENOUGH_USER_POSITION);

        *user_position = *user_position - amount;
    }

    // for satay

    // deposit base_coin into the vault
    // ensure that BaseCoin is the base coin type of the vault
    // update pending coins amount
    public(friend) fun deposit_as_user<BaseCoin>(
        vault_cap: &VaultCapability,
        user_addr: address,
        base_coin: Coin<BaseCoin>
    ) acquires Vault, CoinStore {
        {
            let vault = borrow_global_mut<Vault>(vault_cap.vault_addr);
            assert!(vault.base_coin_type == type_info::type_of<BaseCoin>(), ERR_COIN);

            vault.pending_coins_amount = vault.pending_coins_amount + coin::value(&base_coin);
        };

        add_user_position(vault_cap, user_addr, coin::value(&base_coin));

        deposit(vault_cap, base_coin);
    }

    // withdraw base_coin from the vault
    // ensure that BaseCoin is the base coin type of the vault
    public(friend) fun withdraw_as_user<BaseCoin>(
        vault_cap: &VaultCapability,
        user_addr: address,
        amount: u64
    ): Coin<BaseCoin> acquires CoinStore, Vault {
        {
            let vault = borrow_global<Vault>(vault_cap.vault_addr);
            assert!(vault.base_coin_type == type_info::type_of<BaseCoin>(), ERR_COIN);
        };

        remove_user_position(vault_cap, user_addr, amount);

        withdraw(vault_cap, amount)
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
}
















