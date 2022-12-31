#[test_only]
module ditto_staking::mock_ditto_staking {

    use std::signer;
    use std::string;

    use aptos_framework::coin::{Self, MintCapability, BurnCapability, FreezeCapability, Coin};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_std::math64::pow;

    struct StakedAptos {}

    struct StakedAptosCaps has key {
        mint_cap: MintCapability<StakedAptos>,
        burn_cap: BurnCapability<StakedAptos>,
        freeze_cap: FreezeCapability<StakedAptos>,
    }

    // acts as signer in stake LP call
    struct AccountCapability has key {
        signer_cap: SignerCapability,
        apt_per_st_apt: u64,
    }

    const ERR_UNAUTHORIZED_INITIALIZE: u64 = 1;

    public fun initialize_staked_aptos(ditto: &signer){
        assert!(signer::address_of(ditto) == @ditto_staking, ERR_UNAUTHORIZED_INITIALIZE);

        let (account, signer_cap) = account::create_resource_account(ditto, b"ditto-strategy");
        move_to(ditto, AccountCapability {
            signer_cap,
            apt_per_st_apt: 1 * pow(10, 8),
        });

        coin::register<AptosCoin>(&account);

        let (
            burn_cap,
            freeze_cap,
            mint_cap,
        ) = coin::initialize<StakedAptos>(
            ditto,
            string::utf8(b"Ditto Staked Aptos"),
            string::utf8(b"stAPT"),
            8,
            true
        );
        move_to(&account, StakedAptosCaps {
            mint_cap,
            burn_cap,
            freeze_cap,
        });
    }

    public fun stake(
        user: &signer,
        amount: u64
    ) acquires StakedAptosCaps, AccountCapability {
        let apt = coin::withdraw<AptosCoin>(user, amount);
        let stapt = exchange_aptos(apt, signer::address_of(user));

        if(!coin::is_account_registered<StakedAptos>(signer::address_of(user))){
            coin::register<StakedAptos>(user);
        };

        coin::deposit<StakedAptos>(signer::address_of(user), stapt);
    }

    public fun unstake(
        user: &signer,
        amount: u64
    ) acquires StakedAptosCaps, AccountCapability {
        let stapt = coin::withdraw<StakedAptos>(user, amount);
        let apt = exchange_staptos(stapt, signer::address_of(user));
        coin::deposit<AptosCoin>(signer::address_of(user), apt);
    }

    public fun exchange_aptos(
        aptos: coin::Coin<AptosCoin>,
        _user_address: address
    ) : Coin<StakedAptos> acquires StakedAptosCaps, AccountCapability {
        let account_capability = borrow_global<AccountCapability>(@ditto_staking);
        let account_address = account::get_signer_capability_address(&account_capability.signer_cap);
        let aptos_amount = coin::value(&aptos);
        let caps = borrow_global_mut<StakedAptosCaps>(account_address);
        coin::deposit(account_address, aptos);
        coin::mint(
            aptos_amount * account_capability.apt_per_st_apt / pow(10, 8),
            &mut caps.mint_cap
        )
    }

    public fun exchange_staptos(
        staptos: coin::Coin<StakedAptos>,
        _user_address: address
    ) : Coin<AptosCoin> acquires StakedAptosCaps, AccountCapability {
        let account_capability = borrow_global<AccountCapability>(@ditto_staking);
        let account_signer = account::create_signer_with_capability(&account_capability.signer_cap);

        let staked_aptos_amount = coin::value(&staptos);
        let caps = borrow_global_mut<StakedAptosCaps>(signer::address_of(&account_signer));
        coin::burn(staptos, &mut caps.burn_cap);
        coin::withdraw(&account_signer, staked_aptos_amount)
    }

    public fun mint_staked_aptos(
        amount: u64
    ) : Coin<StakedAptos> acquires StakedAptosCaps, AccountCapability {
        let account_capability = borrow_global<AccountCapability>(@ditto_staking);
        let account_address = account::get_signer_capability_address(&account_capability.signer_cap);
        let caps = borrow_global_mut<StakedAptosCaps>(account_address);
        coin::mint(amount, &mut caps.mint_cap)
    }

    public fun get_stapt_index(): u64   acquires AccountCapability {
        let account_capability = borrow_global<AccountCapability>(@ditto_staking);
        account_capability.apt_per_st_apt
    }
}