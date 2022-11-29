module satay_tortuga_farming::tortuga_farming {

    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::coin::{Self, MintCapability, BurnCapability, FreezeCapability, Coin};
    use std::signer;
    use std::string;
    use aptos_framework::aptos_coin::AptosCoin;

    use tortuga_staking::stake_router;
    use tortuga_staking::staked_coin::StakedAptos;
    use liquidswap::router_v2::get_amount_out;
    use liquidswap::curves::Stable;
    use aries_interface::controller;
    use aries_interface::profile;
    use aries_interface::decimal;
    use aptos_std::type_info;
    use std::option;

    // acts as signer in loans
    struct FarmingAccountCapability has key {
        signer_cap: SignerCapability,
    }

    // coin issued upon apply_position
    struct TortugaFarmingCoin {}

    struct TortugaFarmingCoinCaps has key {
        mint_cap: MintCapability<TortugaFarmingCoin>,
        burn_cap: BurnCapability<TortugaFarmingCoin>,
        freeze_cap: FreezeCapability<TortugaFarmingCoin>
    }

    const ERR_NOT_ADMIN: u64 = 1;
    const MAX_COUNT: u64 = 4;
    const SATAY_STRATGY:vector<u8> = b"satay-strategy";
    // initialize resource account and TortugaFarmingCoin
    public entry fun initialize(manager: &signer) {
        // only module publisher can initialize
        assert!(signer::address_of(manager) == @satay_tortuga_farming, ERR_NOT_ADMIN);

        // create resource account and store its SignerCapability in the manager's account
        let (farming_acc, signer_cap) = account::create_resource_account(manager, b"tortuga-strategy");
        move_to(manager, FarmingAccountCapability {
            signer_cap
        });

        // initailze TortugaFarmingCoin
        // store mint, burn and freeze capabilities in the resource account
        let (
            burn_cap,
            freeze_cap,
            mint_cap
        ) = coin::initialize<TortugaFarmingCoin>(
            manager,
            string::utf8(b"Tortuga Farming Coin"),
            string::utf8(b"TFC"),
            6,
            true
        );
        move_to(
            &farming_acc,
            TortugaFarmingCoinCaps {
                mint_cap,
                burn_cap,
                freeze_cap
            }
        );

        // register strategy account to hold AptosCoin and LP<APT, stAPT> coin
        coin::register<AptosCoin>(&farming_acc);
    }

    // deposit amount of AptosCoin into the product
    // mints TortugaFarmingCoin and deposits to caller account
    // called by users
    public entry fun deposit(
        user: &signer,
        amount: u64
    ) acquires FarmingAccountCapability, TortugaFarmingCoinCaps {
        let user_addr = signer::address_of(user);

        if(!coin::is_account_registered<TortugaFarmingCoin>(user_addr)){
            coin::register<TortugaFarmingCoin>(user);
        };

        let aptos_coin = coin::withdraw<AptosCoin>(user, amount);
        let (tortuga_strategy_coins, residual_aptos_coins) = apply_position(aptos_coin, user_addr);

        coin::deposit(signer::address_of(user), tortuga_strategy_coins);
        coin::deposit(signer::address_of(user), residual_aptos_coins);
    }

    // mint TortugaFarmingCoin for AptosCoin
    public fun apply_position(
        aptos_coins: Coin<AptosCoin>,
        _user_addr: address,
    ): (Coin<TortugaFarmingCoin>, Coin<AptosCoin>) acquires FarmingAccountCapability, TortugaFarmingCoinCaps {
        let tortuga_farming_cap = borrow_global<FarmingAccountCapability>(@satay_tortuga_farming);
        let tortuga_farming_signer = account::create_signer_with_capability(&tortuga_farming_cap.signer_cap);
        let tortuga_farming_address = signer::address_of(&tortuga_farming_signer);
        let tortuga_farming_coin_cap = borrow_global<TortugaFarmingCoinCaps>(tortuga_farming_address);

        let deposit_amount = coin::value(&aptos_coins);
        let count  = 0;

        let tortuga_farming_coins = coin::mint<TortugaFarmingCoin>(deposit_amount, &tortuga_farming_coin_cap.mint_cap);

        while (count < MAX_COUNT) {
            let aptos_value = coin::value(&aptos_coins);
            coin::deposit(signer::address_of(&tortuga_farming_signer), aptos_coins);
            stake_router::stake(&tortuga_farming_signer, aptos_value);

            // borrow apt
            let aptos_amount = aries_loan(&tortuga_farming_signer);
            aptos_coins = coin::withdraw<AptosCoin>(&tortuga_farming_signer, aptos_amount);
            count = count + 1;
        };
        (tortuga_farming_coins, aptos_coins)
    }

    public fun liquidate_position(tortuga_farm_coin: Coin<TortugaFarmingCoin>): Coin<AptosCoin> acquires FarmingAccountCapability, TortugaFarmingCoinCaps {
        let tortuga_farming_cap = borrow_global<FarmingAccountCapability>(@satay_tortuga_farming);
        let tortuga_farming_signer = account::create_signer_with_capability(&tortuga_farming_cap.signer_cap);
        let farming_account_addr = signer::address_of(&tortuga_farming_signer);
        let farming_coin_caps = borrow_global<TortugaFarmingCoinCaps>(farming_account_addr);

        let tapt_needed = get_apt_amount_for_farming_coin_amount(farming_account_addr, coin::value(&tortuga_farm_coin));
        coin::burn(tortuga_farm_coin, &farming_coin_caps.burn_cap);
        // method 1: deleverage
        let tapt_coin = coin::zero<StakedAptos>();
        while(coin::value(&tapt_coin) < tapt_needed) {
            // let tapt = aries_deleverage(&tortuga_farming_signer);
        };
        // method 2: flash loan

        // swap tAPT to APT
        coin::destroy_zero(tapt_coin);
        coin::zero<AptosCoin>()
    }

    // get amount of TortugaFarmingCoin to burn to return aptos_amount of AptosCoin
    /// NOTE: use AUX dex
    public fun get_farming_coin_amount_for_apt_amount(amount_aptos: u64) : u64 {
        let stapt_amount = get_amount_out<AptosCoin, StakedAptos, Stable>(amount_aptos);
        stapt_amount
    }

    // get amount of AptosCoin returned from burning farming_coin_amount of TortugaFarmingCoin
    public fun get_apt_amount_for_farming_coin_amount(farming_account_addr: address, farming_coin_amount: u64) : u64 {
        if(farming_coin_amount > 0) {
            let total_tapt_amount = profile::get_deposited_amount(farming_account_addr, string::utf8(SATAY_STRATGY), type_info::type_of<StakedAptos>());
            let tortuga_farming_coin_supply = option::borrow<u128>(&coin::supply<TortugaFarmingCoin>());
            total_tapt_amount * farming_coin_amount / (*tortuga_farming_coin_supply as u64)
        } else {
            0
        }
    }

    fun aries_loan(tortuga_farming_signer: &signer): u64  {
        controller::deposit<StakedAptos>(tortuga_farming_signer, b"satay-strategy", false);
        let tortuga_farming_address = signer::address_of(tortuga_farming_signer);

        let available_borrow_power = profile::available_borrowing_power(tortuga_farming_address, string::utf8(SATAY_STRATGY));
        controller::withdraw<AptosCoin>(tortuga_farming_signer, SATAY_STRATGY, decimal::as_u64(available_borrow_power),  true);
        decimal::as_u64(available_borrow_power)
    }

    fun aries_deleverage(tortuga_farming_signer: &signer) {
        let total_apt_amount = coin::balance<AptosCoin>(signer::address_of(tortuga_farming_signer));
        controller::withdraw<AptosCoin>(tortuga_farming_signer, SATAY_STRATGY,total_apt_amount, false);

    }
}
