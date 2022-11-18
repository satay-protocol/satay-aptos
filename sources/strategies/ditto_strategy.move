module satay::ditto_strategy {

    use std::signer;

    use aptos_framework::account::{Self, SignerCapability, create_signer_with_capability};
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::AptosCoin;

    use satay::satay;

    use liquidswap_lp::lp_coin::LP;
    use liquidswap::curves::Stable;
    use liquidswap::router::{
        get_reserves_for_lp_coins,
        get_amount_out,
    };

    use ditto_staking::staked_coin::StakedAptos;
    use satay::base_strategy::{Self, initialize as base_initialize};
    use satay::vault::VaultCapability;
    use satay::ditto_rewards::{Self, DittoStrategyCoin};

    // witness for the strategy
    // used for checking approval when locking and unlocking vault
    struct DittoStrategy has drop {}

    // acts as signer in stake LP call
    struct StrategyCapability has key {
        strategy_cap: SignerCapability,
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
    ) {
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
        let strategy_coins =
        ditto_rewards::withdraw_strategy_coin_from_vault<DittoStrategy>(
            &vault_cap,
            lp_to_burn,
            DittoStrategy {}
        );
        let coins = ditto_rewards::liquidate_position(manager_addr, strategy_coins);

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
        ditto_rewards_manager: address,
        vault_id: u64
    ) acquires StrategyCapability  {
        let manager_addr = signer::address_of(manager);

        let ditto_strategy_cap = borrow_global<StrategyCapability>(manager_addr);
        let ditto_strategy_signer = account::create_signer_with_capability(&ditto_strategy_cap.strategy_cap);
        let ditto_strategy_address = signer::address_of(&ditto_strategy_signer);

        let (vault_cap, stop_handle) = base_strategy::open_vault_for_harvest<DittoStrategy, AptosCoin>(
            manager,
            vault_id,
            DittoStrategy {}
        );

        // claim rewards and swap them into BaseCoin
        let coins = claim_rewards_from_ditto();
        let ditto_strategy_coins = ditto_rewards::deposit_coin(&ditto_strategy_signer, ditto_rewards_manager, coins);
        base_strategy::deposit_strategy_coin(&vault_cap, ditto_strategy_coins);

        let strategy_aptos_balance = get_strategy_aptos_balance(&vault_cap);
        let (
            to_apply,
            amount_needed,
        ) = base_strategy::process_harvest<DittoStrategy, AptosCoin>(
            &mut vault_cap,
            strategy_aptos_balance,
            DittoStrategy {}
        );

        let aptos_coins = coin::zero<AptosCoin>();
        if(amount_needed > 0) {
            let lp_to_liquidate = get_lp_for_given_aptos_amount(amount_needed);
            let strategy_coins_to_liquidate = ditto_rewards::withdraw_strategy_coin_from_vault(&vault_cap, lp_to_liquidate, DittoStrategy {});
            let liquidated_aptos_coins = ditto_rewards::liquidate_position(manager_addr, strategy_coins_to_liquidate);
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
        let (ditto_strategy_coins, rest_apt) = ditto_rewards::apply_position(to_apply, ditto_strategy_address, manager_addr,);
        coin::deposit(ditto_strategy_address, rest_apt);
        base_strategy::close_vault_for_harvest<DittoStrategy, AptosCoin, DittoStrategyCoin>(
            signer::address_of(manager),
            vault_cap,
            stop_handle,
            aptos_coins,
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
        let (stapt_amount, apt_amount) = get_reserves_for_lp_coins<StakedAptos, AptosCoin, Stable>(ditto_staked_lp_amount);
        let stapt_to_apt = get_amount_out<StakedAptos, AptosCoin, Stable>(stapt_amount);
        stapt_to_apt + apt_amount
    }

    // get amount of LP to represented by am
    fun get_lp_for_given_aptos_amount(amount: u64) : u64 {
        let (st_apt_amount, apt_amount) = get_reserves_for_lp_coins<StakedAptos, AptosCoin, Stable>(100);
        let stapt_to_apt_amount = get_amount_out<StakedAptos, AptosCoin, Stable>(st_apt_amount);
        (amount * 100 + stapt_to_apt_amount + apt_amount - 1) / (stapt_to_apt_amount + apt_amount)
    }

    public fun name() : vector<u8> {
        b"Ditto LP Farming"
    }

    public fun version() : vector<u8> {
        b"0.0.1"
    }
}
