module satay::vault {
    use std::signer;
    use std::string;

    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability};
    use aptos_std::table::{Self, Table};
    use aptos_std::type_info::TypeInfo;
    use aptos_std::type_info;

    // friend satay::satay;

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

    struct VaultCapability has store, drop {
        storage_cap: SignerCapability,
        vault_id: u64,
        vault_addr: address,
    }

    struct Caps<phantom CoinType> has key {
        mint_cap: MintCapability<CoinType>,
        burn_cap: BurnCapability<CoinType>
    }

    struct VaultCoin<phantom BaseCoin> {}

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
        coin::destroy_freeze_cap(freeze_cap);
        move_to(&vault_acc, Caps<VaultCoin<BaseCoin>> { mint_cap, burn_cap});

        // create vault capability with storage cap and mint/burn capability
        let vault_cap = VaultCapability {
            storage_cap,
            vault_addr: signer::address_of(&vault_acc),
            vault_id,
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

    // for strategies
    // get all coins pending strategy application
    // public fun fetch_pending_coins<BaseCoin>(vault_cap: &VaultCapability): Coin<BaseCoin> acquires Vault, CoinStore {
    //     let vault = borrow_global_mut<Vault>(vault_cap.vault_addr);
    //     let pending_coin_amount = vault.pending_coins_amount;
    //     // fast tracking special case
    //     if (pending_coin_amount == 0) {
    //         return coin::zero()
    //     };
    //     vault.pending_coins_amount = 0;
    //
    //     withdraw(vault_cap, pending_coin_amount)
    // }
    //
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
        let vault_acc = account::create_signer_with_capability(&vault_cap.storage_cap);
        let vault_addr = signer::address_of(&vault_acc);
        let caps = borrow_global<Caps<VaultCoin<BaseCoin>>>(vault_addr);
        let coins = coin::mint<VaultCoin<BaseCoin>>(amount, &caps.mint_cap);
        if(!is_vault_coin_registered<BaseCoin>(signer::address_of(user))){
            coin::register<VaultCoin<BaseCoin>>(user);
        };
        coin::deposit(signer::address_of(user), coins);
    }

    // remove amount from user_addr position in the vault table associated with vault_cap
    fun burn_vault_coins<BaseCoin>(user: &signer, vault_cap: &VaultCapability, amount: u64) acquires Caps {
        let vault_acc = account::create_signer_with_capability(&vault_cap.storage_cap);
        let vault_addr = signer::address_of(&vault_acc);

        let caps = borrow_global<Caps<VaultCoin<BaseCoin>>>(vault_addr);
        coin::burn(coin::withdraw(user, amount), &caps.burn_cap);
    }

    // for satay

    // deposit base_coin into the vault
    // ensure that BaseCoin is the base coin type of the vault
    // update pending coins amount
    public fun deposit_as_user<BaseCoin>(
        user: &signer,
        vault_cap: &VaultCapability,
        base_coin: Coin<BaseCoin>
    ) acquires Vault, CoinStore, Caps {
        {
            let vault = borrow_global_mut<Vault>(vault_cap.vault_addr);
            assert!(vault.base_coin_type == type_info::type_of<BaseCoin>(), ERR_COIN);
        };
        mint_vault_coin<BaseCoin>(user, vault_cap, coin::value(&base_coin));
        deposit(vault_cap, base_coin);
    }

    // withdraw base_coin from the vault
    // ensure that BaseCoin is the base coin type of the vault
    public fun withdraw_as_user<BaseCoin>(
        user: &signer,
        vault_cap: &VaultCapability,
        amount: u64
    ): Coin<BaseCoin> acquires CoinStore, Vault, Caps {
        {
            let vault = borrow_global<Vault>(vault_cap.vault_addr);
            assert!(vault.base_coin_type == type_info::type_of<BaseCoin>(), ERR_COIN);
        };

        burn_vault_coins<BaseCoin>(user, vault_cap, amount);

        withdraw<BaseCoin>(vault_cap, amount)
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

    public fun is_vault_coin_registered<CoinType>(user_address : address): bool {
        coin::is_account_registered<VaultCoin<CoinType>>(user_address)
    }

    public fun vault_coin_balance<CoinType>(user_address : address): u64 {
        coin::balance<VaultCoin<CoinType>>(user_address)
    }
}
















