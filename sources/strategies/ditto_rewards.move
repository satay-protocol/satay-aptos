module satay::ditto_rewards {

    use std::signer;

    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability, FreezeCapability};
    use aptos_framework::aptos_coin::AptosCoin;

    use liquidswap_lp::lp_coin::LP;
    use liquidswap::curves::Stable;
    use liquidswap::router::{
        add_liquidity,
        remove_liquidity,
        swap_exact_coin_for_coin,
        get_reserves_size
    };

    use ditto_staking::staked_coin::StakedAptos;
    use ditto_staking::ditto_staking;
    use aptos_framework::account::SignerCapability;
    use aptos_framework::account;
    use std::string;
    use satay::base_strategy;
    use satay::vault::VaultCapability;
    use liquidity_mining::liquidity_mining;

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

    const MAX_BPS: u64 = 10000; // 100%
    const ERR_NOT_ADMIN: u64 = 1;
    const ERR_NO_FEE: u64 = 2;

    // initialize vault_id to accept strategy
    public entry fun initialize(manager: &signer) {
        // initialize through base_strategy_module
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

    public entry fun deposit(
        user: &signer,
        manager_addr: address,
        amount: u64
    ) acquires StrategyCapability, DittoStrategyCoinCaps {
        let user_addr = signer::address_of(user);

        if(!coin::is_account_registered<LP<AptosCoin, StakedAptos, Stable>>(user_addr)){
            coin::register<LP<AptosCoin, StakedAptos, Stable>>(user);
        };

        let aptos_coin = coin::withdraw<AptosCoin>(user, amount);
        let (ditto_strategy_coins, residual_aptos_coins) = apply_position(aptos_coin, user_addr, manager_addr);

        coin::deposit(signer::address_of(user), ditto_strategy_coins);
        coin::deposit(signer::address_of(user), residual_aptos_coins);
    }

    public entry fun deposit_coin(
        user: &signer,
        manager_addr: address,
        aptos_coin: Coin<AptosCoin>
    ): Coin<DittoStrategyCoin> acquires StrategyCapability, DittoStrategyCoinCaps {
        let user_addr = signer::address_of(user);

        if(!coin::is_account_registered<LP<AptosCoin, StakedAptos, Stable>>(user_addr)){
            coin::register<LP<AptosCoin, StakedAptos, Stable>>(user);
        };

        let (ditto_strategy_coins, residual_aptos_coins) = apply_position(aptos_coin, user_addr, manager_addr);

        coin::deposit(signer::address_of(user), residual_aptos_coins);
        ditto_strategy_coins
    }

    public entry fun withdraw(
        user: &signer,
        manager_addr: address,
        amount: u64
    ) acquires StrategyCapability, DittoStrategyCoinCaps {
        let ditto_strategy_coin = coin::withdraw<DittoStrategyCoin>(user, amount);
        let aptos_coin = liquidate_position(manager_addr, ditto_strategy_coin);
        coin::deposit<AptosCoin>(signer::address_of(user), aptos_coin);
    }

    public entry fun withdraw_strategy_coin_from_vault<StrategyType: drop>(
        vault_cap: &VaultCapability,
        lp_to_burn: u64,
        witness: StrategyType
    ): Coin<DittoStrategyCoin> {
        base_strategy::withdraw_strategy_coin<StrategyType, DittoStrategyCoin>(
            vault_cap,
            lp_to_burn,
            witness
        )
    }

    // stakes AptosCoin on Ditto for StakedAptos
    // adds AptosCoin and StakedAptos to Liquidswap LP
    // stakes LP<StakedAptos, AptosCoin> to Ditto liquidity_mining
    public fun apply_position(
        coins: Coin<AptosCoin>,
        user_addr: address,
        manager_addr: address
    ): (Coin<DittoStrategyCoin>, Coin<AptosCoin>) acquires StrategyCapability, DittoStrategyCoinCaps {
        let ditto_strategy_cap = borrow_global<StrategyCapability>(manager_addr);
        let ditto_strategy_address = account::get_signer_capability_address(&ditto_strategy_cap.strategy_cap);
        let ditto_strategy_signer = account::create_signer_with_capability(&ditto_strategy_cap.strategy_cap);
        let strategy_coin_caps = borrow_global<DittoStrategyCoinCaps>(ditto_strategy_address);

        // 1. exchange half of APT to stAPT
        let coin_amount = coin::value<AptosCoin>(&coins);
        // STAPT and APT decimals are all 8
        let (apt_reserve, st_apt_reserve) = get_reserves_size<AptosCoin, StakedAptos, Stable>();
        let apt_to_swap = coin_amount * st_apt_reserve / (apt_reserve + st_apt_reserve);
        let apt_to_stapt = coin::extract(&mut coins, apt_to_swap);
        let st_apt = ditto_staking::exchange_aptos(apt_to_stapt, user_addr);

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
            coin::merge(&mut rest_apt, ditto_staking::exchange_staptos(rest_st_apt, user_addr));
        };

        // 3. stake LP for Ditto pre-mine program, mint DittoStrategyCoin in proportion
        let lp_amount = coin::value(&lp);
        coin::deposit(ditto_strategy_address, lp);
        let strategy_coins = coin::mint<DittoStrategyCoin>(
            lp_amount,
            &strategy_coin_caps.mint_cap
        );

        liquidity_mining::stake<LP<AptosCoin, StakedAptos, Stable>>(
            &ditto_strategy_signer,
            lp_amount
        );

        (strategy_coins, rest_apt)
    }

    // removes Apto from 3rd party protocol to get yield
    // @param amount: aptos amount
    // @dev BaseCoin should be AptosCoin
    public fun liquidate_position(
        manager_addr: address,
        strategy_coin: Coin<DittoStrategyCoin>
    ): Coin<AptosCoin> acquires StrategyCapability, DittoStrategyCoinCaps {
        let ditto_strategy_cap = borrow_global<StrategyCapability>(manager_addr);
        let ditto_strategy_signer = account::create_signer_with_capability(&ditto_strategy_cap.strategy_cap);
        let ditto_strategy_coin_caps = borrow_global<DittoStrategyCoinCaps>(
            signer::address_of(&ditto_strategy_signer)
        );

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
        let total_lp_balance = coin::balance<LP<AptosCoin, StakedAptos, Stable>>(signer::address_of(&ditto_strategy_signer));
        let lp_coins = coin::withdraw<LP<AptosCoin, StakedAptos, Stable>>(&ditto_strategy_signer, total_lp_balance);
        let (aptos_coin, staked_aptos) = remove_liquidity<AptosCoin, StakedAptos, Stable>(lp_coins, 1, 1);
        coin::merge(&mut aptos_coin, swap_stapt_for_apt(staked_aptos));

        // debug if there's such case
        // assert!(coin::value(&aptos_coin) >= amount, 1);
        aptos_coin
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