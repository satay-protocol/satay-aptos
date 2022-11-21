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
    struct StrategyCapability has key {
        strategy_cap: SignerCapability,
    }

    // coin issued upon apply strategy
    struct DittoFarmingCoin {}

    struct DittoFarmingCoinCaps has key {
        mint_cap: MintCapability<DittoFarmingCoin>,
        burn_cap: BurnCapability<DittoFarmingCoin>,
        freeze_cap: FreezeCapability<DittoFarmingCoin>
    }

    const MAX_BPS: u64 = 10000; // 100%

    const ERR_NOT_ADMIN: u64 = 1;
    const ERR_NO_FEE: u64 = 2;

    // initialize strategy account and coin,
    // register LP<APT/stAPT> and AptosCoin on account
    public entry fun initialize(manager: &signer) {
        // only module publisher can initialize
        assert!(signer::address_of(manager) == @satay_ditto_farming, ERR_NOT_ADMIN);

        // create strategy resource account and store its capability in the manager's account
        let (strategy_acc, strategy_cap) = account::create_resource_account(manager, b"ditto-strategy");
        move_to(manager, StrategyCapability {
            strategy_cap
        });

        // initailze DittoFarmingCoin, to be used as StrategyCoin in harvest
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
            &strategy_acc,
            DittoFarmingCoinCaps {
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
        amount: u64
    ) acquires StrategyCapability, DittoFarmingCoinCaps {
        let user_addr = signer::address_of(user);

        if(!coin::is_account_registered<DittoFarmingCoin>(user_addr)){
            coin::register<DittoFarmingCoin>(user);
        };

        let aptos_coin = coin::withdraw<AptosCoin>(user, amount);
        let (ditto_strategy_coins, residual_aptos_coins) = apply_position(aptos_coin, user_addr);

        coin::deposit(signer::address_of(user), ditto_strategy_coins);
        coin::deposit(signer::address_of(user), residual_aptos_coins);
    }

    public entry fun withdraw(
        user: &signer,
        amount: u64
    ) acquires StrategyCapability, DittoFarmingCoinCaps {
        let ditto_strategy_coin = coin::withdraw<DittoFarmingCoin>(user, amount);
        let aptos_coin = liquidate_position(ditto_strategy_coin);
        coin::deposit<AptosCoin>(signer::address_of(user), aptos_coin);
    }

    // stakes AptosCoin on Ditto for StakedAptos
    // adds AptosCoin and StakedAptos to Liquidswap LP
    // stakes LP<StakedAptos, AptosCoin> to Ditto liquidity_mining
    public fun apply_position(
        aptos_coins: Coin<AptosCoin>,
        user_addr: address,
    ): (Coin<DittoFarmingCoin>, Coin<AptosCoin>) acquires StrategyCapability, DittoFarmingCoinCaps {
        let deposit_amount = coin::value(&aptos_coins);
        if(deposit_amount > 0){
            let ditto_strategy_cap = borrow_global<StrategyCapability>(@satay_ditto_farming);
            let ditto_strategy_signer = account::create_signer_with_capability(&ditto_strategy_cap.strategy_cap);
            let ditto_strategy_addr = signer::address_of(&ditto_strategy_signer);

            // exchange optimal amount of apt for stAPT
            let st_apt = swap_apt_for_stapt(&mut aptos_coins, user_addr);
            // add apt and stAPT to LP
            let (lp, residual_aptos) = add_apt_st_apt_lp(
                aptos_coins,
                st_apt,
                ditto_strategy_addr
            );
            // stake LP token and mint DittoFarmingCoin
            let ditto_farming_coins = stake_lp_and_mint(lp, &ditto_strategy_signer);
            (ditto_farming_coins, residual_aptos)
        } else {
            (coin::zero(), aptos_coins)
        }
    }

    fun swap_apt_for_stapt(aptos_coins: &mut Coin<AptosCoin>, user_addr: address) : Coin<StakedAptos> {
        let (apt_reserve, st_apt_reserve) = get_reserves_size<AptosCoin, StakedAptos, Stable>();
        let apt_to_swap = mul_div(coin::value(aptos_coins), st_apt_reserve, (apt_reserve + st_apt_reserve));
        let apt_to_stapt = coin::extract(aptos_coins, apt_to_swap);
        ditto_staking::exchange_aptos(apt_to_stapt, user_addr)
    }

    fun add_apt_st_apt_lp(
        apt: Coin<AptosCoin>,
        st_apt: Coin<StakedAptos>,
        product_address: address
    ) : (Coin<LP<AptosCoin, StakedAptos, Stable>>, Coin<AptosCoin>) {
        let (
            rest_apt,
            rest_st_apt,
            lp
        ) = add_liquidity<AptosCoin, StakedAptos, Stable>(apt, 0, st_apt, 0);

        if(coin::value(&rest_st_apt) == 0){
            coin::destroy_zero(rest_st_apt);
        } else {
            coin::merge(&mut rest_apt, ditto_staking::exchange_staptos(rest_st_apt, product_address));
        };

        (lp, rest_apt)
    }

    fun stake_lp_and_mint(
        lp: Coin<LP<AptosCoin, StakedAptos, Stable>>,
        product_signer: &signer,
    ) : Coin<DittoFarmingCoin> acquires DittoFarmingCoinCaps {
        let product_address = signer::address_of(product_signer);
        let strategy_coin_caps = borrow_global<DittoFarmingCoinCaps>(product_address);
        let lp_amount = coin::value(&lp);
        coin::deposit(product_address, lp);
        liquidity_mining::stake<LP<AptosCoin, StakedAptos, Stable>>(
            product_signer,
            lp_amount
        );
        coin::mint<DittoFarmingCoin>(
            lp_amount,
            &strategy_coin_caps.mint_cap
        )
    }

    // removes Apto from 3rd party protocol to get yield
    // @param amount: aptos amount
    // @dev BaseCoin should be AptosCoin
    public fun liquidate_position(
        strategy_coin: Coin<DittoFarmingCoin>,
    ): Coin<AptosCoin> acquires StrategyCapability, DittoFarmingCoinCaps {
        let ditto_strategy_cap = borrow_global<StrategyCapability>(@satay_ditto_farming);
        let ditto_strategy_signer = account::create_signer_with_capability(&ditto_strategy_cap.strategy_cap);
        let ditto_strategy_coin_caps = borrow_global<DittoFarmingCoinCaps>(
            signer::address_of(&ditto_strategy_signer)
        );

        let strategy_coin_amount = coin::value<DittoFarmingCoin>(&strategy_coin);
        coin::burn(strategy_coin, &ditto_strategy_coin_caps.burn_cap);

        // withdraw and get apt coin
        liquidity_mining::unstake<LP<AptosCoin, StakedAptos, Stable>>(&ditto_strategy_signer, strategy_coin_amount);

        let lp_coins = coin::withdraw<LP<AptosCoin, StakedAptos, Stable>>(
            &ditto_strategy_signer,
            strategy_coin_amount
        );
        let (aptos_coin, staked_aptos) = remove_liquidity<AptosCoin, StakedAptos, Stable>(
            lp_coins,
            1,
            1
        );
        coin::merge(&mut aptos_coin, swap_stapt_for_apt(staked_aptos));

        aptos_coin
    }

    public entry fun tend(
        user: &signer,
    ) acquires StrategyCapability, DittoFarmingCoinCaps {
        let (dito_farming_coins, residual_aptos_coins) = reinvest_returns(user);
        coin::deposit(signer::address_of(user), dito_farming_coins);
        coin::deposit(signer::address_of(user), residual_aptos_coins);
    }


    public fun reinvest_returns(
        user: &signer,
    ): (Coin<DittoFarmingCoin>, Coin<AptosCoin>) acquires StrategyCapability, DittoFarmingCoinCaps {
        let aptos_coins = claim_rewards_from_ditto();
        apply_position(aptos_coins, signer::address_of(user))
    }

    fun claim_rewards_from_ditto(): Coin<AptosCoin> {
        // claim DTO rewards from LP staking pool
        // FIXME: add DTO coin type
        // liquidity_mining::redeem<LP<StakedAptos, AptosCoin, Stable>, DTOCoinType>()
        // convert DTO to APT (DTO is not live on mainnet)
        // proceed apply_position

        coin::zero<AptosCoin>()
    }

    public fun get_apt_amount_for_strategy_coin_amount(amount_strategy_coin: u64) : u64 {
        if(amount_strategy_coin > 0) {
            let (
                apt_amount,
                st_apt_amount
            ) = get_reserves_for_lp_coins<AptosCoin, StakedAptos, Stable>(amount_strategy_coin);
            let stapt_to_apt = get_amount_out<StakedAptos, AptosCoin, Stable>(st_apt_amount);
            stapt_to_apt + apt_amount
        } else {
            0
        }
    }

    public fun get_strategy_coin_amount_for_apt_amount(amount_aptos: u64) : u64 {
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

    // simple swap from CoinType to BaseCoin on Liquidswap
    fun swap_stapt_for_apt(stAPT: Coin<StakedAptos>) : Coin<AptosCoin> {
        // swap on liquidswap AMM
        swap_exact_coin_for_coin<StakedAptos, AptosCoin, Stable>(
            stAPT,
            0
        )
    }
}