module satay::ditto_strategy {
    use aptos_framework::account::{Self, SignerCapability, create_signer_with_capability};
    use satay::satay;
    use std::signer;
    use aptos_framework::coin;
    use liquidswap_lp::lp_coin::LP;
    use aptos_framework::aptos_coin::AptosCoin;
    use liquidswap::curves::Stable;
    use aptos_framework::coin::Coin;
    use liquidswap::router;
    use ditto_staking::staked_coin::StakedAptos;
    use ditto_staking::ditto_staking;
    use liquidity_mining::liquidity_mining;
    use liquidswap::router::{get_reserves_for_lp_coins, get_amount_out, remove_liquidity, swap_exact_coin_for_coin};
    use satay::base_strategy::{Self, initialize as base_initialize};

    // witness for the strategy
    // used for checking approval when locking and unlocking vault
    struct DittoStrategy has drop {}

    struct StrategyCapability has key {
        strategy_cap: SignerCapability,
    }

    struct CoinStore<phantom AptosCoin, phantom StakedAptosCoin, phantom LPCoin> has key {
        aptos_coin: Coin<AptosCoin>,
        staked_aptos_coin: Coin<StakedAptos>,
        lp_coin: Coin<LPCoin>
    }

    struct DittoTempCoinType {}

    const ERR_NOT_ENOUGH_FUND: u64 = 301;
    const ERR_ENOUGH_BALANCE_ON_VAULT: u64 = 302;
    const ERR_LOSS: u64 = 303;

    // initialize vault_id to accept strategy
    public entry fun initialize(manager: &signer, vault_id: u64, debt_ratio: u64) {
        // create strategy resource account and store its capability in the manager's account
        base_initialize<DittoStrategy, LP<StakedAptos, AptosCoin, Stable>>(manager, vault_id, debt_ratio, DittoStrategy {});
        let (strategy_acc, strategy_cap) = account::create_resource_account(manager, b"ditto-strategy");
        move_to(manager, StrategyCapability {
            strategy_cap
        });

        // register coins
        move_to(&strategy_acc,
            CoinStore<AptosCoin, StakedAptos, LP<StakedAptos, AptosCoin, Stable>> {
                aptos_coin: coin::zero(),
                staked_aptos_coin: coin::zero(),
                lp_coin: coin::zero()
            });
    }

    // update the strategy debt ratio
    public entry fun update_debt_ratio(manager: &signer, vault_id: u64, debt_ratio: u64) {
        satay::update_strategy_debt_ratio<DittoStrategy>(manager, vault_id, debt_ratio);
    }

    // revoke the strategy
    public entry fun revoke<StrategyType: drop>(manager: &signer, vault_id: u64) {
        satay::update_strategy_debt_ratio<StrategyType>(manager, vault_id, 0);
    }

    // migrate to new strategy
    public entry fun migrate_from<OldStrategy: drop, NewStrategy: drop, NewStrategyCoin>(manager: &signer, vault_id: u64, witness: NewStrategy) {
        let debt_ratio = satay::update_strategy_debt_ratio<OldStrategy>(manager, vault_id, 0);
        base_initialize<NewStrategy, NewStrategyCoin>(manager, vault_id, debt_ratio, witness);
    }

    // called when vault does not have enough BaseCoin in reserves, and must reclaim funds from strategy
    public entry fun withdraw_for_user<BaseCoin>(
        user: &signer,
        manager_addr: address,
        vault_id: u64,
        share_amount: u64
    ) acquires StrategyCapability {
        let (
            amount_needed,
            vault_cap,
            stop_handle
        ) = base_strategy::assert_user_eligible_to_withdraw<DittoStrategy, BaseCoin, LP<StakedAptos, AptosCoin, Stable>>(
            user,
            manager_addr,
            vault_id,
            share_amount,
            DittoStrategy {}
        );

        let coins = liquidate_position<BaseCoin>(manager_addr, amount_needed);

        base_strategy::close_vault_for_user_withdraw<DittoStrategy, BaseCoin>(
            manager_addr,
            vault_cap,
            stop_handle,
            coins,
            amount_needed
        );
    }

    // adds BaseCoin to 3rd party protocol to get yield
    // if 3rd party protocol returns a coin, it should be sent to the vault
    fun apply_position(manager_addr: address, coins: Coin<AptosCoin>) acquires StrategyCapability, CoinStore {
        let ditto_strategy_cap = borrow_global<StrategyCapability>(manager_addr);
        let ditto_strategy_signer = account::create_signer_with_capability(&ditto_strategy_cap.strategy_cap);
        let coin_store = borrow_global_mut<CoinStore<AptosCoin, StakedAptos, LP<StakedAptos, AptosCoin, Stable>>>(signer::address_of(&ditto_strategy_signer));

        // 1. exchange half of APT to stAPT
        let coin_amount = coin::value<AptosCoin>(&coins);
        let half_aptos = coin::extract(&mut coins, coin_amount / 2);
        let stAPT = ditto_staking::exchange_aptos(half_aptos, signer::address_of(&ditto_strategy_signer));

        // 2. add liquidity with APT and stAPT
        // convert stPAT using instant_exchange and send back to the vault
        let (rest_st_apt, rest_apt, lp) =
            router::add_liquidity<StakedAptos, AptosCoin, Stable>(stAPT, 1, coins, 1);
        coin::merge(&mut coin_store.aptos_coin, rest_apt);
        coin::merge(&mut coin_store.staked_aptos_coin, rest_st_apt);
        // TODO: handle dust amount of stAPT

        // deposit lp coins to strategy account to call ditto function
        coin::merge(&mut coin_store.lp_coin, lp);
        // 3. stake stAPTOS-APTOS pool for Ditto pre-mine program
        liquidity_mining::stake<LP<StakedAptos, AptosCoin, Stable>>(
            &ditto_strategy_signer,
            coin::balance<LP<StakedAptos, AptosCoin, Stable>>(signer::address_of(&ditto_strategy_signer))
        );
     }

    // removes BaseCoin from 3rd party protocol to get yield
    // @param amount: aptos amount
    // @dev BaseCoin should be AptosCoin
    fun liquidate_position<BaseCoin>(manager_addr: address, amount: u64): Coin<BaseCoin> acquires StrategyCapability {
        let ditto_strategy_cap = borrow_global<StrategyCapability>(manager_addr);
        let ditto_strategy_signer = account::create_signer_with_capability(&ditto_strategy_cap.strategy_cap);

        // withdraw and get apt coin
        // 1. redeem DTO token and convert to APT
        // liquidity_mining::redeem<LP<StakedAptos, AptosCoin, Stable>, DTOCoinType>()

        // calcuate required LP token amount to withdraw
        let (st_apt_amount, apt_amount) = get_reserves_for_lp_coins<StakedAptos, BaseCoin, Stable>(10000);
        let stapt_to_apt_amount = get_amount_out<StakedAptos, BaseCoin, Stable>(st_apt_amount);
        let lp_to_unstake = amount * 10000 / (stapt_to_apt_amount + apt_amount);

        liquidity_mining::unstake<LP<StakedAptos, BaseCoin, Stable>>(&ditto_strategy_signer, lp_to_unstake);
        let total_lp_balance = coin::balance<LP<StakedAptos, AptosCoin, Stable>>(signer::address_of(&ditto_strategy_signer));
        let lp_coins = coin::withdraw<LP<StakedAptos, BaseCoin, Stable>>(&ditto_strategy_signer, total_lp_balance);
        let (staked_aptos, aptos_coin) = remove_liquidity<StakedAptos, BaseCoin, Stable>(lp_coins, 1, 1);
        let aptos_from_swap = swap_exact_coin_for_coin<StakedAptos, BaseCoin, Stable>(staked_aptos, 1);
        coin::merge(&mut aptos_coin, aptos_from_swap);

        // debug if there's such case
        assert!(coin::value(&aptos_coin) >= amount, 1);
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

    // harvests the Strategy, realizing any profits or losses and adjusting the Strategy's position.
    public entry fun harvest<CoinType, BaseCoin>(manager: &signer, vault_id: u64) acquires StrategyCapability, CoinStore {
        let (vault_cap, stop_handle) = base_strategy::open_vault_for_harvest<DittoStrategy, BaseCoin>(
            manager,
            vault_id,
            DittoStrategy {}
        );

        // claim rewards and swap them into BaseCoin
        let coins = claim_rewards_from_ditto();
        apply_position(signer::address_of(manager), coins);

        let strategy_base_coin_balance = get_strategy_base_coin_balance();
        let (to_apply, to_liquidaite, _, to_liquidate_amount) =
            base_strategy::process_harvest<DittoStrategy, AptosCoin, DittoTempCoinType>(
                &mut vault_cap,
                strategy_base_coin_balance,
                DittoStrategy {}
            );
        coin::destroy_zero(to_liquidaite);
        let base_coins = liquidate_position<BaseCoin>(signer::address_of(manager), to_liquidate_amount);
        apply_position(signer::address_of(manager), to_apply);

        base_strategy::close_vault_for_harvest<DittoStrategy, BaseCoin, BaseCoin>(
            signer::address_of(manager),
            vault_cap,
            stop_handle,
            base_coins,
            coin::zero<BaseCoin>()
        )
    }

    // get strategy signer cap for manager_addr
    fun get_strategy_signer_cap(manager_addr : address) : signer acquires StrategyCapability {
        let strategy_cap = borrow_global_mut<StrategyCapability>(manager_addr);
        create_signer_with_capability(&strategy_cap.strategy_cap)
    }

    fun get_strategy_base_coin_balance() : u64 {
        // NOTE: get claimable DTO and convert to APT
        // TODO: 1. get user staked LP amount to ditto LP layer (interface missing from Ditto)
        let ditto_staked_lp_amount = 1000;
        // 2. convert LP coin to aptos
        let (stapt_amount, apt_amount) = router::get_reserves_for_lp_coins<StakedAptos, AptosCoin, Stable>(ditto_staked_lp_amount);
        let stapt_to_apt = router::get_amount_out<StakedAptos, AptosCoin, Stable>(stapt_amount);
        stapt_to_apt + apt_amount
    }

    public fun name() : vector<u8> {
        b"strategy-name"
    }

    public fun version() : vector<u8> {
        b"0.0.1"
    }

    // simple swap from CoinType to BaseCoin on Liquidswap
    fun swap_to_want_token<CoinType, BaseCoin>(coins: Coin<CoinType>) : Coin<BaseCoin> {
        // swap on liquidswap AMM
        router::swap_exact_coin_for_coin<CoinType, BaseCoin, Stable>(
            coins,
            0
        )
    }

}
