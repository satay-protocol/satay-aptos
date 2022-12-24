module satay_ditto_farming::ditto_farming {

    use std::signer;
    use std::string;

    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability, FreezeCapability};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::account::{Self, SignerCapability};

    use liquidswap_lp::lp_coin::LP;
    use liquidswap::curves::Stable;
    use liquidswap::router_v2::{
        add_liquidity,
        remove_liquidity,
        swap_exact_coin_for_coin,
        get_reserves_size,
        get_reserves_for_lp_coins,
        get_amount_out
    };
    use liquidswap::math::mul_div;

    use ditto_staking::staked_coin::StakedAptos;
    use ditto_staking::ditto_staking;
    use liquidity_mining::liquidity_mining;

    // acts as signer in stake LP call
    struct FarmingAccountCapability has key {
        signer_cap: SignerCapability,
    }

    // coin issued upon apply_position
    struct DittoFarmingCoin {}

    struct DittoFarmingCoinCaps has key {
        mint_cap: MintCapability<DittoFarmingCoin>,
        burn_cap: BurnCapability<DittoFarmingCoin>,
        freeze_cap: FreezeCapability<DittoFarmingCoin>
    }

    const ERR_NOT_ADMIN: u64 = 1;

    // initialize resource account and DittoFarmingCoin
    // register LP<APT, stAPT> and AptosCoin for resource account
    public entry fun initialize(manager: &signer) {
        // only module publisher can initialize
        assert!(signer::address_of(manager) == @satay_ditto_farming, ERR_NOT_ADMIN);

        // create resource account and store its SignerCapability in the manager's account
        let (farming_acc, signer_cap) = account::create_resource_account(
            manager,
            b"ditto_farming_product"
        );
        move_to(manager, FarmingAccountCapability {
            signer_cap
        });

        // initailze DittoFarmingCoin
        // store mint, burn and freeze capabilities in the resource account
        let (
            burn_cap,
            freeze_cap,
            mint_cap
        ) = coin::initialize<DittoFarmingCoin>(
            manager,
            string::utf8(b"Ditto Farming Coin"),
            string::utf8(b"DFC"),
            6,
            true
        );
        move_to(
            &farming_acc,
            DittoFarmingCoinCaps {
                mint_cap,
                burn_cap,
                freeze_cap
            }
        );

        // register strategy account to hold AptosCoin and LP<APT, stAPT> coin
        coin::register<AptosCoin>(&farming_acc);
        coin::register<LP<AptosCoin, StakedAptos, Stable>>(&farming_acc);
    }

    // deposit amount of AptosCoin into the product
    // mints DittoFarmingCoin and deposits to caller account
    // called by users
    public entry fun deposit(
        user: &signer,
        amount: u64
    ) acquires FarmingAccountCapability, DittoFarmingCoinCaps {
        let user_addr = signer::address_of(user);

        if(!coin::is_account_registered<DittoFarmingCoin>(user_addr)){
            coin::register<DittoFarmingCoin>(user);
        };

        let aptos_coin = coin::withdraw<AptosCoin>(user, amount);
        let (ditto_strategy_coins, residual_aptos_coins) = apply_position(aptos_coin, user_addr);

        coin::deposit(signer::address_of(user), ditto_strategy_coins);
        coin::deposit(signer::address_of(user), residual_aptos_coins);
    }

    // withdraw amount of DittoFarmCoin from the user
    // burn DittoFarmingCoin and deposit returned AptosCoin to caller account
    // called by users
    public entry fun withdraw(
        user: &signer,
        amount: u64
    ) acquires FarmingAccountCapability, DittoFarmingCoinCaps {
        let ditto_farming_coin = coin::withdraw<DittoFarmingCoin>(user, amount);
        let aptos_coin = liquidate_position(ditto_farming_coin);
        coin::deposit<AptosCoin>(signer::address_of(user), aptos_coin);
    }

    // mint DittoFarmingCoin for AptosCoin
    public fun apply_position(
        aptos_coins: Coin<AptosCoin>,
        user_addr: address,
    ): (Coin<DittoFarmingCoin>, Coin<AptosCoin>) acquires FarmingAccountCapability, DittoFarmingCoinCaps {
        let deposit_amount = coin::value(&aptos_coins);
        if(deposit_amount > 0){
            let ditto_farming_cap = borrow_global<FarmingAccountCapability>(@satay_ditto_farming);
            let ditto_farming_signer = account::create_signer_with_capability(&ditto_farming_cap.signer_cap);
            let ditto_farming_address = signer::address_of(&ditto_farming_signer);

            // exchange optimal amount of apt for stAPT
            let st_apt = swap_apt_for_stapt(&mut aptos_coins, user_addr);
            // add apt and stAPT to LP
            let (lp, residual_aptos) = add_apt_st_apt_lp(
                aptos_coins,
                st_apt,
                ditto_farming_address
            );
            // stake LP token and mint DittoFarmingCoin
            let ditto_farming_coins = stake_lp_and_mint(lp, &ditto_farming_signer);
            (ditto_farming_coins, residual_aptos)
        } else {
            (coin::zero(), aptos_coins)
        }
    }

    // stakes optimal amount of AptosCoin for StakedAptos given current reserves ratio
    fun swap_apt_for_stapt(aptos_coins: &mut Coin<AptosCoin>, user_addr: address) : Coin<StakedAptos> {
        let (apt_reserve, st_apt_reserve) = get_reserves_size<AptosCoin, StakedAptos, Stable>();
        let apt_to_swap = mul_div(coin::value(aptos_coins), st_apt_reserve, (apt_reserve + st_apt_reserve));
        let apt_to_stapt = coin::extract(aptos_coins, apt_to_swap);
        ditto_staking::exchange_aptos(apt_to_stapt, user_addr)
    }

    // adds AptosCoin and StakedAptos to LP
    // returns LP<AptosCoin, StakedAptos> and residual AptosCoin
    fun add_apt_st_apt_lp(
        aptos_coins: Coin<AptosCoin>,
        staptos_coins: Coin<StakedAptos>,
        product_address: address
    ) : (Coin<LP<AptosCoin, StakedAptos, Stable>>, Coin<AptosCoin>) {
        let (
            residual_aptos_coins,
            residual_staptos_coins,
            lp
        ) = add_liquidity<AptosCoin, StakedAptos, Stable>(aptos_coins, 0, staptos_coins, 0);

        if(coin::value(&residual_staptos_coins) == 0){
            coin::destroy_zero(residual_staptos_coins);
        } else {
            coin::merge(
                &mut residual_aptos_coins,
                ditto_staking::exchange_staptos(residual_staptos_coins, product_address)
            );
        };

        (lp, residual_aptos_coins)
    }

    // stake LP<AptosCoin, StakedAptos> to Ditto liquidity_mining module
    // mint and return DittoFarmingCoin
    fun stake_lp_and_mint(
        lp_coins: Coin<LP<AptosCoin, StakedAptos, Stable>>,
        ditto_farming_signer: &signer,
    ) : Coin<DittoFarmingCoin> acquires DittoFarmingCoinCaps {
        let ditto_farming_addr = signer::address_of(ditto_farming_signer);
        let farming_coin_caps = borrow_global<DittoFarmingCoinCaps>(ditto_farming_addr);
        let lp_coin_amount = coin::value(&lp_coins);

        coin::deposit(ditto_farming_addr, lp_coins);
        liquidity_mining::stake<LP<AptosCoin, StakedAptos, Stable>>(
            ditto_farming_signer,
            lp_coin_amount,
        );
        coin::mint<DittoFarmingCoin>(
            lp_coin_amount,
            &farming_coin_caps.mint_cap
        )
    }

    // liquidates DittoFarmingCoin for AptosCoin
    public fun liquidate_position(
        ditto_farming_coins: Coin<DittoFarmingCoin>,
    ): Coin<AptosCoin> acquires FarmingAccountCapability, DittoFarmingCoinCaps {
        let ditto_farming_cap = borrow_global<FarmingAccountCapability>(@satay_ditto_farming);
        let ditto_farming_signer = account::create_signer_with_capability(&ditto_farming_cap.signer_cap);

        let lp_coins = unstake_lp_and_burn(ditto_farming_coins, &ditto_farming_signer);

        liquidate_lp_coins(lp_coins)
    }

    // unstake LP<AptosCoin, StakedAptos> from Ditto liquidity_mining module
    // burn DittoFarmingCoin and return LP<AptosCoin, StakedAptos>
    fun unstake_lp_and_burn(
        ditto_farming_coins: Coin<DittoFarmingCoin>,
        ditto_farming_signer: &signer,
    ) : Coin<LP<AptosCoin, StakedAptos, Stable>> acquires DittoFarmingCoinCaps {
        // unstake amount of LP for given amount of DittoFarmingCoin
        let farming_coin_amount = coin::value<DittoFarmingCoin>(&ditto_farming_coins);
        liquidity_mining::unstake<LP<AptosCoin, StakedAptos, Stable>>(
            ditto_farming_signer,
            farming_coin_amount,
        );
        // burn farming coin
        let farming_account_addr = signer::address_of(ditto_farming_signer);
        let farming_coin_caps = borrow_global<DittoFarmingCoinCaps>(farming_account_addr);
        coin::burn(ditto_farming_coins, &farming_coin_caps.burn_cap);
        // return proportionate amount of LP coin
        coin::withdraw<LP<AptosCoin, StakedAptos, Stable>>(ditto_farming_signer, farming_coin_amount)
    }

    // removes LP<AptosCoin, StakedAptos> from Liquidswap for AptosCoin
    fun liquidate_lp_coins(
        lp_coins: Coin<LP<AptosCoin, StakedAptos, Stable>>
    ) : Coin<AptosCoin> {
        // remove liquidity for lp_coins
        let (aptos_coin, staked_aptos) = remove_liquidity<AptosCoin, StakedAptos, Stable>(
            lp_coins,
            1,
            1
        );
        // swap returned stAPT for APT
        coin::merge(&mut aptos_coin, swap_stapt_for_apt(staked_aptos));
        // return APT
        aptos_coin
    }

    // calls reinvest_returns for user
    // deposit returned DittoFarmingCoin and AptosCoin to user account
    public entry fun tend(
        user: &signer,
    ) acquires FarmingAccountCapability, DittoFarmingCoinCaps {
        let (dito_farming_coins, residual_aptos_coins) = reinvest_returns(user);
        coin::deposit(signer::address_of(user), dito_farming_coins);
        coin::deposit(signer::address_of(user), residual_aptos_coins);
    }

    // claim AptosCoin rewards and call apply_position for DittoFarmingCoin
    public fun reinvest_returns(
        user: &signer,
    ): (Coin<DittoFarmingCoin>, Coin<AptosCoin>) acquires FarmingAccountCapability, DittoFarmingCoinCaps {
        let aptos_coins = claim_rewards_from_ditto();
        apply_position(aptos_coins, signer::address_of(user))
    }

    // claim staking rewards from Ditto
    // FIXME: currently, Ditto does not have a way to claim rewards as their DTO coin has not launched
    fun claim_rewards_from_ditto(): Coin<AptosCoin> {
        // FIXME: add DTO coin type
        // liquidity_mining::redeem<LP<StakedAptos, AptosCoin, Stable>, DTOCoinType>()
        // convert DTO to APT (DTO is not live on mainnet)
        // until DTO is live, return zero APT
        coin::zero<AptosCoin>()
    }

    // get amount of AptosCoin returned from burning farming_coin_amount of DittoFarmingCoin
    public fun get_apt_amount_for_farming_coin_amount(farming_coin_amount: u64) : u64 {
        if(farming_coin_amount > 0) {
            let (
                apt_amount,
                st_apt_amount
            ) = get_reserves_for_lp_coins<AptosCoin, StakedAptos, Stable>(farming_coin_amount);
            let stapt_to_apt = get_amount_out<StakedAptos, AptosCoin, Stable>(st_apt_amount);
            stapt_to_apt + apt_amount
        } else {
            0
        }
    }

    // get amount of DittoFarmingCoin to burn to return aptos_amount of AptosCoin
    public fun get_farming_coin_amount_for_apt_amount(amount_aptos: u64) : u64 {
        let (apt_amount, st_apt_amount) = get_reserves_for_lp_coins<AptosCoin, StakedAptos, Stable>(100);
        let stapt_to_apt_amount = get_amount_out<StakedAptos, AptosCoin, Stable>(st_apt_amount);
        (amount_aptos * 100 + stapt_to_apt_amount + apt_amount - 1) / (stapt_to_apt_amount + apt_amount)
    }

    public fun name() : vector<u8> {
        b"Ditto LP Farming"
    }

    public fun version() : vector<u8> {
        b"0.0.1"
    }

    // swap StakedAptos for AptosCoin on Liquidswap
    fun swap_stapt_for_apt(staptos_coins: Coin<StakedAptos>) : Coin<AptosCoin> {
        // swap on liquidswap AMM
        swap_exact_coin_for_coin<StakedAptos, AptosCoin, Stable>(
            staptos_coins,
            0
        )
    }
}