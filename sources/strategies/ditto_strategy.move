module satay::ditto_strategy {

    use std::signer;
    use std::string;

    use aptos_framework::account::{Self, SignerCapability, create_signer_with_capability};
    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability, FreezeCapability};
    use aptos_framework::aptos_coin::AptosCoin;

    use satay::satay;

    use liquidswap_lp::lp_coin::LP;
    use liquidswap::curves::Stable;
    use liquidswap::router::{
        add_liquidity,
        get_reserves_for_lp_coins,
        get_amount_out,
        remove_liquidity,
        swap_exact_coin_for_coin,
        get_reserves_size
    };

    use ditto_staking::staked_coin::StakedAptos;
    use ditto_staking::ditto_staking;
    // use liquidity_mining::liquidity_mining;
    use satay::base_strategy::{Self, initialize as base_initialize};
    use satay::vault::VaultCapability;

    // witness for the strategy
    // used for checking approval when locking and unlocking vault
    struct DittoStrategy has drop {}

    // acts as signer in stake LP call
    struct StrategyCapability has key {
        strategy_cap: SignerCapability,
    }

    // coin issued upon apply strategy
    struct DittoStrategyCoin {}

    struct DittoStrategyCoinCaps has key {
        mint_cap: MintCapability<DittoStrategyCoin>,
        burn_cap: BurnCapability<DittoStrategyCoin>,
        freeze_cap: FreezeCapability<DittoStrategyCoin>
    }

    // initialize vault_id to accept strategy
    public entry fun initialize(manager: &signer, vault_id: u64, debt_ratio: u64) {
        // initialize through base_strategy_module
        base_initialize<DittoStrategy, DittoStrategyCoin>(manager, vault_id, debt_ratio, DittoStrategy {});

        // create strategy resource account and store its capability in the manager's account
        let (strategy_acc, strategy_cap) = account::create_resource_account(manager, b"ditto-strategy");
        move_to(manager, StrategyCapability {
            strategy_cap
        });

        // initailze DittoStrategyCoin, to be used as StrategyCoin in harvest
        let (
            burn_cap,
            freeze_cap,
            mint_cap
        ) = coin::initialize<DittoStrategyCoin>(
            manager,
            string::utf8(b"Ditto Strategy Coin"),
            string::utf8(b"DSC"),
            8,
            true
        );
        move_to(
            &strategy_acc,
            DittoStrategyCoinCaps {
                mint_cap,
                burn_cap,
                freeze_cap
            }
        );

        // register strategy account to hold AptosCoin and LP coin
        coin::register<AptosCoin>(&strategy_acc);
        coin::register<LP<AptosCoin, StakedAptos, Stable>>(&strategy_acc);
    }

    // called when vault does not have enough BaseCoin in reserves, and must reclaim funds from strategy
    public entry fun withdraw_for_user(
        user: &signer,
        manager_addr: address,
        vault_id: u64,
        share_amount: u64
    ) acquires StrategyCapability, DittoStrategyCoinCaps {
        let (
            amount_aptos_needed,
            vault_cap,
            stop_handle
        ) = base_strategy::open_vault_for_user_withdraw<DittoStrategy, AptosCoin, LP<AptosCoin, StakedAptos, Stable>>(
            user,
            manager_addr,
            vault_id,
            share_amount,
            DittoStrategy {}
        );

        let lp_to_burn = get_lp_for_given_aptos_amount(amount_aptos_needed);
        let strategy_coins = base_strategy::withdraw_strategy_coin<DittoStrategy, DittoStrategyCoin>(
            &vault_cap,
            lp_to_burn,
        );
        let coins = liquidate_position(manager_addr, strategy_coins);

        base_strategy::close_vault_for_user_withdraw<DittoStrategy, AptosCoin>(
            manager_addr,
            vault_cap,
            stop_handle,
            coins,
            amount_aptos_needed
        );
    }

    // harvests the Strategy, realizing any profits or losses and adjusting the Strategy's position.
    public entry fun harvest(
        manager: &signer,
        vault_id: u64
    ) acquires StrategyCapability, DittoStrategyCoinCaps {
        let (vault_cap, stop_handle) = base_strategy::open_vault_for_harvest<DittoStrategy, AptosCoin>(
            manager,
            vault_id,
            DittoStrategy {}
        );
        let manager_addr = signer::address_of(manager);

        // claim rewards and swap them into BaseCoin
        let coins = claim_rewards_from_ditto();
        if(coin::value(&coins) > 0) {
            let ditto_strategy_coins = apply_position(signer::address_of(manager), coins);
            base_strategy::deposit_strategy_coin<DittoStrategyCoin>(&vault_cap, ditto_strategy_coins);
        } else {
            coin::destroy_zero(coins);
        };

        let strategy_aptos_balance = get_strategy_aptos_balance(&vault_cap);
        let (
            to_apply,
            amount_needed,
        ) = base_strategy::process_harvest<DittoStrategy, AptosCoin, DittoStrategyCoin>(
            &mut vault_cap,
            strategy_aptos_balance,
            DittoStrategy {}
        );

        let aptos_coins = coin::zero<AptosCoin>();
        if(amount_needed > 0) {
            let lp_to_liquidate = get_lp_for_given_aptos_amount(amount_needed);
            let strategy_coins_to_liquidate = base_strategy::withdraw_strategy_coin<DittoStrategy, DittoStrategyCoin>(
                &vault_cap,
                lp_to_liquidate
            );
            let liquidated_aptos_coins = liquidate_position(manager_addr, strategy_coins_to_liquidate);
            let liquidated_aptos_coins_amount = coin::value<AptosCoin>(&liquidated_aptos_coins);

            if (liquidated_aptos_coins_amount > amount_needed) {
                coin::merge(
                    &mut to_apply,
                    coin::extract(
                        &mut liquidated_aptos_coins,
                        liquidated_aptos_coins_amount - amount_needed
                    )
                );
            };
            coin::merge(&mut aptos_coins, liquidated_aptos_coins)
        };
        let ditto_strategy_coins = apply_position(manager_addr, to_apply);

        base_strategy::close_vault_for_harvest<DittoStrategy, AptosCoin, DittoStrategyCoin>(
            signer::address_of(manager),
            vault_cap,
            stop_handle,
            // coin::zero(),
            aptos_coins,
            // coin::zero()
            ditto_strategy_coins
        )
    }

    // update the strategy debt ratio
    public entry fun update_debt_ratio(manager: &signer, vault_id: u64, debt_ratio: u64) {
        satay::update_strategy_debt_ratio<DittoStrategy>(manager, vault_id, debt_ratio);
    }

    // revoke the strategy
    public entry fun revoke(manager: &signer, vault_id: u64) {
        satay::update_strategy_debt_ratio<DittoStrategy>(manager, vault_id, 0);
    }

    // stakes AptosCoin on Ditto for StakedAptos
    // adds AptosCoin and StakedAptos to Liquidswap LP
    // stakes LP<StakedAptos, AptosCoin> to Ditto liquidity_mining
    fun apply_position(
        manager_addr: address,
        coins: Coin<AptosCoin>
    ) : Coin<DittoStrategyCoin> acquires StrategyCapability, DittoStrategyCoinCaps {
        let ditto_strategy_cap = borrow_global<StrategyCapability>(manager_addr);
        let ditto_strategy_signer = account::create_signer_with_capability(&ditto_strategy_cap.strategy_cap);
        let ditto_strategy_address = signer::address_of(&ditto_strategy_signer);

        // add residual aptos when applying strategy
        let ditto_strategy_aptos_balance = coin::balance<AptosCoin>(ditto_strategy_address);
        coin::merge(
            &mut coins,
            coin::withdraw<AptosCoin>(&ditto_strategy_signer, ditto_strategy_aptos_balance)
        );

        // 1. exchange half of APT to stAPT
        let coin_amount = coin::value<AptosCoin>(&coins);
        let (apt_reserve, st_apt_reserve) = get_reserves_size<AptosCoin, StakedAptos, Stable>();
        let apt_to_stapt = coin::extract(&mut coins, coin_amount * st_apt_reserve / (st_apt_reserve + apt_reserve));
        let st_apt = ditto_staking::exchange_aptos(apt_to_stapt, signer::address_of(&ditto_strategy_signer));

        // 2. add liquidity with APT and stAPT
        // convert stPAT using instant_exchange and send back to the vault
        let (
            rest_apt,
            rest_st_apt,
            lp
        ) = add_liquidity<AptosCoin, StakedAptos, Stable>(coins, 0, st_apt, 0);
        if(coin::value(&rest_st_apt) == 0){
            coin::destroy_zero(rest_st_apt);
        } else {
            coin::merge(&mut rest_apt, swap_stapt_for_apt(rest_st_apt));
        };
        coin::deposit(ditto_strategy_address, rest_apt);

        // 3. stake LP for Ditto pre-mine program, mint DittoStrategyCoin in proportion
        let lp_amount = coin::value(&lp);
        coin::deposit(ditto_strategy_address, lp);
        let strategy_coin_caps = borrow_global<DittoStrategyCoinCaps>(ditto_strategy_address);
        let strategy_coins = coin::mint<DittoStrategyCoin>(
            lp_amount,
            &strategy_coin_caps.mint_cap
        );
        // liquidity_mining::stake<LP<AptosCoin, StakedAptos, Stable>>(
        //     &ditto_strategy_signer,
        //     lp_amount
        // );
        strategy_coins
     }

    // removes Apto from 3rd party protocol to get yield
    // @param amount: aptos amount
    // @dev BaseCoin should be AptosCoin
    fun liquidate_position(
        manager_addr: address,
        strategy_coin: Coin<DittoStrategyCoin>
    ): Coin<AptosCoin> acquires StrategyCapability, DittoStrategyCoinCaps {
        let ditto_strategy_cap = borrow_global<StrategyCapability>(manager_addr);
        let ditto_strategy_signer = account::create_signer_with_capability(&ditto_strategy_cap.strategy_cap);
        let ditto_strategy_coin_caps = borrow_global<DittoStrategyCoinCaps>(
            signer::address_of(&ditto_strategy_signer)
        );

        let strategy_coin_amount = coin::value(&strategy_coin);
        coin::burn(strategy_coin, &ditto_strategy_coin_caps.burn_cap);

        // withdraw and get apt coin
        // 1. redeem DTO token and convert to APT
        // liquidity_mining::redeem<LP<StakedAptos, AptosCoin, Stable>, DTOCoinType>()

        // calcuate required LP token amount to withdraw
        // let (st_apt_amount, apt_amount) = get_reserves_for_lp_coins<StakedAptos, AptosCoin, Stable>(strategy_coin_amount);
        // let stapt_to_apt_amount = get_amount_out<StakedAptos, AptosCoin, Stable>(st_apt_amount);
        // let lp_to_unstake = amount * 10000 / (stapt_to_apt_amount + apt_amount);

        // reclaim staked LP coins
        // liquidity_mining::unstake<LP<AptosCoin, StakedAptos, Stable>>(&ditto_strategy_signer, strategy_coin_amount);

        // withdraw
        // let total_lp_balance = coin::balance<LP<AptosCoin, StakedAptos, Stable>>(signer::address_of(&ditto_strategy_signer));
        let lp_coins = coin::withdraw<LP<AptosCoin, StakedAptos, Stable>>(&ditto_strategy_signer, strategy_coin_amount);
        let (aptos_coin, staked_aptos) = remove_liquidity<AptosCoin, StakedAptos, Stable>(lp_coins, 1, 1);
        coin::merge(&mut aptos_coin, swap_stapt_for_apt(staked_aptos));

        // debug if there's such case
        // assert!(coin::value(&aptos_coin) >= amount, 1);
        aptos_coin
    }

    fun claim_rewards_from_ditto(): Coin<AptosCoin> {
        // claim DTO rewards from LP staking pool
        // FIXME: add DTO coin type
        // liquidity_mining::redeem<LP<StakedAptos, AptosCoin, Stable>, DTOCoinType>()
        // convert DTO to APT (DTO is not live on mainnet)
        // proceed apply_position

        coin::zero<AptosCoin>()
    }



    // get strategy signer cap for manager_addr
    fun get_strategy_signer_cap(manager_addr : address) : signer acquires StrategyCapability {
        let strategy_cap = borrow_global_mut<StrategyCapability>(manager_addr);
        create_signer_with_capability(&strategy_cap.strategy_cap)
    }

    // get total AptosCoin balance for strategy
    fun get_strategy_aptos_balance(vault_cap: &VaultCapability) : u64 {
        // 1. get user staked LP amount to ditto LP layer (interface missing from Ditto)
        let ditto_staked_lp_amount = base_strategy::balance<DittoStrategyCoin>(vault_cap);
        // 2. convert LP coin to aptos
        if(ditto_staked_lp_amount > 0) {
            let (apt_amount, st_apt_amount) = get_reserves_for_lp_coins<AptosCoin, StakedAptos, Stable>(ditto_staked_lp_amount);
            let stapt_to_apt = get_amount_out<StakedAptos, AptosCoin, Stable>(st_apt_amount);
            stapt_to_apt + apt_amount
        } else {
            0
        }
    }

    // get amount of LP to represented by am
    fun get_lp_for_given_aptos_amount(amount: u64) : u64 {
        let (apt_amount, st_apt_amount) = get_reserves_for_lp_coins<AptosCoin, StakedAptos, Stable>(100);
        let stapt_to_apt_amount = get_amount_out<StakedAptos, AptosCoin, Stable>(st_apt_amount);
        (amount * 100 + stapt_to_apt_amount + apt_amount - 1) / (stapt_to_apt_amount + apt_amount)
    }

    public fun name() : vector<u8> {
        b"Ditto LP Farming"
    }

    public fun version() : vector<u8> {
        b"0.0.1"
    }

    // simple swap from CoinType to BaseCoin on Liquidswap
    fun swap_stapt_for_apt(stAPT: Coin<StakedAptos>) : Coin<AptosCoin> {
        // swap on liquidswap AMM
        swap_exact_coin_for_coin<StakedAptos, AptosCoin, Stable>(
            stAPT,
            0
        )
    }

}
