module satay_ditto_rewards::ditto_rewards_product {

    use std::signer;

    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::AptosCoin;

    use liquidswap_lp::lp_coin::LP;
    use liquidswap::curves::Stable;
    use liquidswap::router::{
        add_liquidity,
        remove_liquidity,
        swap_exact_coin_for_coin,
        get_reserves_size,
        register_pool
    };

    use ditto_staking::staked_coin::StakedAptos;
    use ditto_staking::ditto_staking;
    use liquidswap::math::sqrt;
    use aptos_std::math128::pow;

    public entry fun init(
        user: &signer,
        amount: u64
    ) {
        let user_addr = signer::address_of(user);
        // get Aptos from user
        let apt = coin::withdraw<AptosCoin>(user, amount);
        let amount_to_exchange = coin::value(&apt) / 2;
        let apt_to_stapt = coin::extract(&mut apt, amount_to_exchange);
        let st_apt = ditto_staking::exchange_aptos(apt_to_stapt, signer::address_of(user));

        // create LP<AptosCoin, StakedAptos, Stable> pool on Liquidswap
        register_pool<AptosCoin, StakedAptos, Stable>(user);
        // add liquidity to pool
        let (
            residual_apt,
            residual_st_apt,
            lp
        ) = add_liquidity<AptosCoin, StakedAptos, Stable>(apt, 0, st_apt, 0);
        // swap residual st_apt into apt
        if(coin::value(&residual_st_apt) == 0){
            coin::destroy_zero(residual_st_apt);
        } else {
            coin::merge(&mut residual_apt, ditto_staking::exchange_staptos(residual_st_apt, user_addr));
        };
        //deposit residual apt
        if(coin::value(&residual_apt) == 0){
            coin::destroy_zero(residual_apt);
        } else {
            coin::deposit(user_addr, residual_apt);
        };

        coin::register<LP<AptosCoin, StakedAptos, Stable>>(user);
        coin::deposit(user_addr, lp);
    }

    public entry fun initialize(
        _user: &signer,
    ) {

    }

    public entry fun deposit(
        user: &signer,
        amount: u64
    ) {
        let user_addr = signer::address_of(user);

        if(!coin::is_account_registered<LP<AptosCoin, StakedAptos, Stable>>(user_addr)){
            coin::register<LP<AptosCoin, StakedAptos, Stable>>(user);
        };

        let aptos_coin = coin::withdraw<AptosCoin>(user, amount);
        let (lp_coins, residual_aptos_coins) = apply_position(aptos_coin, user_addr);

        coin::deposit(signer::address_of(user), lp_coins);
        coin::deposit(signer::address_of(user), residual_aptos_coins);
    }

    public entry fun withdraw(
        user: &signer,
        amount: u64
    ) {
        let lp_coins = coin::withdraw<LP<AptosCoin, StakedAptos, Stable>>(user, amount);
        let aptos_coin = liquidate_position(lp_coins);
        coin::deposit<AptosCoin>(signer::address_of(user), aptos_coin);
    }

    // stakes AptosCoin on Ditto for StakedAptos
    // adds AptosCoin and StakedAptos to Liquidswap LP
    // stakes LP<StakedAptos, AptosCoin> to Ditto liquidity_mining
    fun apply_position(
        coins: Coin<AptosCoin>,
        user_addr: address
    ): (Coin<LP<AptosCoin, StakedAptos, Stable>>, Coin<AptosCoin>) {
        // 1. exchange half of APT to stAPT
        let coin_amount = coin::value<AptosCoin>(&coins);
        // STAPT and APT decimals are all 8
        let (apt_reserve, _st_apt_reserve) = get_reserves_size<AptosCoin, StakedAptos, Stable>();
        let apt_to_swap = coin_amount / 2;
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
        (lp, rest_apt)
    }

    // removes Apto from 3rd party protocol to get yield
    // @param amount: aptos amount
    // @dev BaseCoin should be AptosCoin
    fun liquidate_position(
        lp_coins: Coin<LP<AptosCoin, StakedAptos, Stable>>

    ): Coin<AptosCoin> {
        let (aptos_coin, staked_aptos) = remove_liquidity<AptosCoin, StakedAptos, Stable>(lp_coins, 1, 1);
        coin::merge(&mut aptos_coin, swap_stapt_for_apt(staked_aptos));
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