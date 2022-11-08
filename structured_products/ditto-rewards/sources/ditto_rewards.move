module satay_ditto_rewards::ditto_rewards_product {

    use std::signer;
    use std::string;

    use aptos_framework::account::{Self, SignerCapability, create_signer_with_capability};
    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability, FreezeCapability};
    use aptos_framework::aptos_coin::AptosCoin;

    use liquidswap_lp::lp_coin::LP;
    use liquidswap::curves::Stable;
    use liquidswap::router::{
        add_liquidity,
        get_reserves_for_lp_coins,
        get_amount_out,
        remove_liquidity,
        swap_exact_coin_for_coin
    };

    use ditto_staking::staked_coin::StakedAptos;
    use ditto_staking::ditto_staking;
    use liquidity_mining::liquidity_mining;
    use std::option;

    // witness for the strategy
    // used for checking approval when locking and unlocking vault
    struct DittoStrategy has drop {}

    // acts as signer in stake LP call
    struct StrategyCapability has key {
        strategy_cap: SignerCapability,
        total_deposit: u64
    }

    // coin issued upon apply strategy
    struct DittoStrategyCoin {}

    struct DittoStrategyCoinCaps has key {
        mint_cap: MintCapability<DittoStrategyCoin>,
        burn_cap: BurnCapability<DittoStrategyCoin>,
        freeze_cap: FreezeCapability<DittoStrategyCoin>
    }

    // initialize vault_id to accept strategy
    public entry fun initialize(manager: &signer) {
        // create strategy resource account and store its capability in the manager's account
        let (strategy_acc, strategy_cap) = account::create_resource_account(manager, b"ditto-strategy");
        move_to(manager, StrategyCapability {
            strategy_cap,
            total_deposit: 0
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
        if(!coin::is_account_registered<DittoStrategyCoin>(signer::address_of(user))) {
            coin::register<DittoStrategyCoin>(user);
        };

        let aptos_coin = coin::withdraw<AptosCoin>(user, amount);
        apply_position_for_deposit(user, manager_addr, aptos_coin);
    }

    public entry fun withdraw(
        user: &signer,
        manager_addr: address,
        amount: u64
    ) acquires StrategyCapability, DittoStrategyCoinCaps {
        let strategy_coin = coin::withdraw<DittoStrategyCoin>(user, amount);
        let aptos_coin = liquidate_position(manager_addr, strategy_coin);
        coin::deposit(signer::address_of(user), aptos_coin);
    }

    // harvests the Strategy, realizing any profits or losses and adjusting the Strategy's position.
    public entry fun harvest(
        manager: &signer
    ) acquires StrategyCapability {
        // claim rewards and swap them into BaseCoin
        let coins = claim_rewards_from_ditto();
        apply_position(signer::address_of(manager), coins);
    }

    // stakes AptosCoin on Ditto for StakedAptos
    // adds AptosCoin and StakedAptos to Liquidswap LP
    // stakes LP<StakedAptos, AptosCoin> to Ditto liquidity_mining
    fun apply_position(
        manager_addr: address,
        coins: Coin<AptosCoin>
    ) acquires StrategyCapability {
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
        let half_aptos = coin::extract(&mut coins, coin_amount / 2);
        let st_apt = ditto_staking::exchange_aptos(half_aptos, signer::address_of(&ditto_strategy_signer));

        // 2. add liquidity with APT and stAPT
        // convert stPAT using instant_exchange and send back to the vault
        let (
            rest_apt,
            rest_st_apt,
            lp
        ) = add_liquidity<AptosCoin, StakedAptos, Stable>(coins, 0, st_apt, 0);
        coin::merge(&mut rest_apt, swap_stapt_for_apt(rest_st_apt));
        coin::deposit(ditto_strategy_address, rest_apt);

        // 3. stake LP for Ditto pre-mine program, mint DittoStrategyCoin in proportion
        let lp_amount = coin::value(&lp);
        coin::deposit(ditto_strategy_address, lp);
        liquidity_mining::stake<LP<AptosCoin, StakedAptos, Stable>>(
            &ditto_strategy_signer,
            lp_amount
        );
    }

    fun apply_position_for_deposit(
        user: &signer,
        manager_addr: address,
        coins: Coin<AptosCoin>
    ) acquires StrategyCapability, DittoStrategyCoinCaps {
        let ditto_strategy_cap = borrow_global<StrategyCapability>(manager_addr);
        let ditto_strategy_signer = account::create_signer_with_capability(&ditto_strategy_cap.strategy_cap);
        let ditto_strategy_address = signer::address_of(&ditto_strategy_signer);
        let strategy_coin_caps = borrow_global<DittoStrategyCoinCaps>(ditto_strategy_address);

        // 1. exchange half of APT to stAPT
        let coin_amount = coin::value<AptosCoin>(&coins);
        let half_aptos = coin::extract(&mut coins, coin_amount / 2);
        let st_apt = ditto_staking::exchange_aptos(half_aptos, signer::address_of(&ditto_strategy_signer));

        // 2. add liquidity with APT and stAPT
        // convert stPAT using instant_exchange and send back to the vault
        let (
            rest_apt,
            rest_st_apt,
            lp
        ) = add_liquidity<AptosCoin, StakedAptos, Stable>(coins, 0, st_apt, 0);
        coin::merge(&mut rest_apt, swap_stapt_for_apt(rest_st_apt));
        coin::deposit(ditto_strategy_address, rest_apt);

        // 3. stake LP for Ditto pre-mine program, mint DittoStrategyCoin in proportion
        let lp_amount = coin::value(&lp);
        coin::deposit(ditto_strategy_address, lp);
        liquidity_mining::stake<LP<AptosCoin, StakedAptos, Stable>>(
            &ditto_strategy_signer,
            lp_amount
        );

        let ditto_strategy_total_supply = option::get_with_default<u128>(&coin::supply<DittoStrategyCoin>(), 0);

        let strategy_coin_amount;
        if (ditto_strategy_cap.total_deposit == 0) {
            strategy_coin_amount = lp_amount;
        } else {
            strategy_coin_amount = (ditto_strategy_total_supply as u64) * coin_amount / ditto_strategy_cap.total_deposit;
        };
        let strategy_coin = coin::mint<DittoStrategyCoin>(strategy_coin_amount, &strategy_coin_caps.mint_cap);
        coin::deposit(signer::address_of(user), strategy_coin);
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

        let total_supply = option::get_with_default<u128>(&coin::supply<DittoStrategyCoin>(), 0);

        // DITTO: get total deposited amount
        let ditto_total_deposited = 0;

        let lp_to_withdraw = ditto_total_deposited / (total_supply as u64) * strategy_coin_amount;
        // reclaim staked LP coins
        liquidity_mining::unstake<LP<AptosCoin, StakedAptos, Stable>>(&ditto_strategy_signer, lp_to_withdraw);
        // withdraw
        let total_lp_balance = coin::balance<LP<AptosCoin, StakedAptos, Stable>>(signer::address_of(&ditto_strategy_signer));
        let lp_coins = coin::withdraw<LP<AptosCoin, StakedAptos, Stable>>(&ditto_strategy_signer, total_lp_balance);
        let (aptos_coin, staked_aptos) = remove_liquidity<AptosCoin, StakedAptos, Stable>(lp_coins, 1, 1);
        coin::merge(&mut aptos_coin, swap_stapt_for_apt(staked_aptos));

        // debug if there's such case
        // assert!(coin::value(&aptos_coin) >= amount, 1);
        aptos_coin
    }

    // DITTO:
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
    fun get_strategy_aptos_balance() : u64 {
        // 1. get user staked LP amount to ditto LP layer (interface missing from Ditto)
        // DITTO: call getter function from ditto startegy retrieves userInfo
        let ditto_staked_lp_amount = 0;
        // 2. convert LP coin to aptos
        let (stapt_amount, apt_amount) = get_reserves_for_lp_coins<StakedAptos, AptosCoin, Stable>(ditto_staked_lp_amount);
        let stapt_to_apt = get_amount_out<StakedAptos, AptosCoin, Stable>(stapt_amount);
        stapt_to_apt + apt_amount
    }

    // get amount of LP to represented by am
    fun get_lp_for_given_aptos_amount(amount: u64) : u64 {
        let (st_apt_amount, apt_amount) = get_reserves_for_lp_coins<StakedAptos, AptosCoin, Stable>(100);
        let stapt_to_apt_amount = get_amount_out<StakedAptos, AptosCoin, Stable>(st_apt_amount);
        amount * 100 / (stapt_to_apt_amount + apt_amount)
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