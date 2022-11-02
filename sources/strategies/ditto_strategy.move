module satay::ditto_strategy {
    use aptos_framework::account::{Self, SignerCapability, create_signer_with_capability};
    use aptos_std::type_info;
    use satay::satay;
    use std::signer;
    use satay::vault;
    use ditto::staked_coin::{StakedAptos};
    use aptos_framework::coin;
    use liquidswap_lp::lp_coin::LP;
    use aptos_framework::aptos_coin::AptosCoin;
    use liquidswap::curves::Stable;
    use aptos_framework::coin::Coin;
    use ditto::ditto_staking;
    use liquidswap::scripts::add_liquidity;
    use liquidswap::router;
    use satay::vault::VaultCapability;


    // witness for the strategy
    // used for checking approval when locking and unlocking vault
    struct DittoStrategy has drop {}

    struct StrategyCapability has key {
        strategy_cap: SignerCapability,
    }

    const ERR_NOT_ENOUGH_FUND: u64 = 301;
    const ERR_ENOUGH_BALANCE_ON_VAULT: u64 = 302;
    const ERR_LOSS: u64 = 303;

    // initialize vault_id to accept strategy
    public entry fun initialize(manager: &signer, vault_id: u64, seed: vector<u8>, debt_ratio: u64) {
        // create strategy resource account and store its capability in the manager's account
        let (_, strategy_cap) = account::create_resource_account(manager, seed);
        move_to(manager, StrategyCapability {strategy_cap});

        // approve strategy on vault
        satay::approve_strategy<DittoStrategy>(manager, vault_id, type_info::type_of<StakedAptos>(), debt_ratio);

        // add a CoinStore for the PoolBaseCoin
        let manager_addr = signer::address_of(manager);
        let (vault_cap, stop_handle) = satay::lock_vault<DittoStrategy>(manager_addr, vault_id, DittoStrategy {});
        if (!vault::has_coin<LP<StakedAptos, AptosCoin, Stable>>(&vault_cap)) {
            vault::add_coin<LP<StakedAptos, AptosCoin, Stable>>(&vault_cap);
        };
        satay::unlock_vault<DittoStrategy>(manager_addr, vault_cap, stop_handle);
    }

    // update the strategy debt ratio
    public entry fun update_debt_ratio(manager: &signer, vault_id: u64, debt_ratio: u64) {
        satay::update_strategy_debt_ratio<DittoStrategy>(manager, vault_id, debt_ratio);
    }

    // called when vault does not have enough BaseCoin in reserves, and must reclaim funds from strategy
    public fun withdraw_from_user<BaseCoin>(user: &signer, manager_addr: address, vault_id: u64, share_amount: u64) acquires StrategyCapability {
        let (vault_cap, stop_handle) = satay::lock_vault<DittoStrategy>(manager_addr, vault_id, DittoStrategy {});

        // check if user is eligible to withdraw
        let user_share_amount = coin::balance<vault::VaultCoin<BaseCoin>>(signer::address_of(user));
        assert!(user_share_amount >= share_amount, ERR_NOT_ENOUGH_FUND);

        // check if vault has enough balance
        let user_amount = vault::calculate_amount_from_share<BaseCoin>(&vault_cap, share_amount);
        assert!(vault::balance<BaseCoin>(&vault_cap) < user_amount, ERR_ENOUGH_BALANCE_ON_VAULT);

        // reclaim user_amount to vault
        let coins = liquidate_position<BaseCoin>(manager_addr, user_amount);
        vault::update_total_debt<DittoStrategy>(&mut vault_cap, 0, coin::value(&coins));
        vault::deposit<BaseCoin>(&vault_cap, coins);

        satay::unlock_vault<DittoStrategy>(manager_addr, vault_cap, stop_handle);
    }

    // adds BaseCoin to 3rd party protocol to get yield
    // if 3rd party protocol returns a coin, it should be sent to the vault
    fun apply_position<BaseCoin>(vault_storage_signer : signer, aptos_amount: u64) acquires StrategyCapability {
        ditto_staking::stake_aptos(&vault_storage_signer, aptos_amount / 2);
        // stake stAPTOS-APTOS pool
        let aptos_coins = coin::withdraw<AptosCoin>(&vault_storage_signer, aptos_balance - aptos_balance / 2);
        let staked_aptos_coins = coin::withdraw<StakedAptos>(&strategy_signer, aptos_balance / 2);

        // TODO: handle dust amount
        // convert stPAT using instant_exchange and send back to the vault
        let (_, _, lp) =
            router::add_liquidity<StakedAptos, AptosCoin, Stable>(staked_aptos_coins, 1, aptos_coins, 1);

        // stake LP token to ditto pool

    }

    // removes BaseCoin from 3rd party protocol to get yield
    fun liquidate_position<BaseCoin>(manager_addr: address, amount: u64): Coin<BaseCoin> acquires StrategyCapability {
        let signer = get_signer_cap(manager_addr);
        staking_pool::withdraw<BaseCoin>(&signer, amount)
    }

    fun claim_rewards_from_ditto(): Coin<AptosCoin> {
        // TODO: claim DTO rewards from LP staking pool
        // convert DTO to APT
        // return APT
        coin::zero<AptosCoin>()
    }

    // harvests the Strategy, realizing any profits or losses and adjusting the Strategy's position.
    public entry fun harvest<CoinType, BaseCoin>(manager_addr: address, vault_id: u64) acquires StrategyCapability {
        let (vault_cap, stop_handle) = satay::lock_vault<DittoStrategy>(manager_addr, vault_id, DittoStrategy {});
        // claim rewards and swap them into BaseCoin
        let coins = claim_rewards_from_ditto();
        // swap APT to stAPT
        ditto_staking::exchange_aptos(coins);


        let (profit, loss, debt_payment) = prepare_return<BaseCoin>(&vault_cap, manager_addr);

        // profit to report
        if (profit > 0) {
            vault::report_gain<DittoStrategy>(&mut vault_cap, profit);
        };

        // loss to report, do it before the rest of the calculation
        if (loss > 0) {
            let total_debt = vault::total_debt<DittoStrategy>(&vault_cap);
            assert!(total_debt >= loss, ERR_LOSS);
            vault::report_loss<DittoStrategy>(&mut vault_cap, loss);
        };

        let credit = vault::credit_available<DittoStrategy, BaseCoin>(&vault_cap);
        let debt = vault::debt_out_standing<DittoStrategy, BaseCoin>(&vault_cap);
        if (debt_payment > debt) {
            debt_payment = debt;
        };

        if (credit > 0 || debt_payment > 0) {
            vault::update_total_debt<DittoStrategy>(&mut vault_cap, credit, debt_payment);
        };

        let total_available = profit + debt_payment;

        // assess fees for profits
        if (profit > 0) {
            assess_fees<BaseCoin>(profit, &vault_cap);
        };
        if (total_available < credit) { // credit surplus, give to Strategy
            let coins =  vault::withdraw<BaseCoin>(&vault_cap, credit - total_available);
            apply_position<BaseCoin>(manager_addr, coins);
        } else { // credit deficit, take from Strategy
            let coins = liquidate_position<BaseCoin>(manager_addr, total_available - credit);
            vault::deposit<BaseCoin>(&vault_cap, coins);
        };

        vault::report<DittoStrategy>(&mut vault_cap);

        satay::unlock_vault<DittoStrategy>(manager_addr, vault_cap, stop_handle);
    }

    // get strategy signer cap for manager_addr
    fun get_strategy_signer_cap(manager_addr : address) : signer acquires StrategyCapability {
        let strategy_cap = borrow_global_mut<StrategyCapability>(manager_addr);
        create_signer_with_capability(&strategy_cap.strategy_cap)
    }

    // returns any realized profits, realized losses incurred, and debt payments to be made
    // called by harvest
    fun prepare_return<BaseCoin>(vault_cap: &VaultCapability, manager_addr: address) : (u64, u64, u64) acquires StrategyCapability {
        let strategy_signer = get_strategy_signer_cap(manager_addr);

        // get amount of strategy debt over limit
        let debt_out_standing = vault::debt_out_standing<DittoStrategy, BaseCoin>(vault_cap);
        // balance of staking pool
        let total_assets = ditto_staking::get_staked_balance(signer::address_of(&strategy_signer));
        // strategy's total debt
        let total_debt = vault::total_debt<DittoStrategy>(vault_cap);

        let profit = 0;
        let loss = 0;
        let debt_payment: u64;
        // staking pool has more BaseCoin than outstanding debt
        if (total_assets > debt_out_standing) {
            // amount to return = outstanding debt
            debt_payment = debt_out_standing;
            // amount in staking pool decreases by debt payment
            total_assets = total_assets - debt_payment;
        } else {
            // amount to return = all assets
            debt_payment = total_assets;
            total_assets = 0;
        };
        total_debt = total_debt - debt_payment;

        if (total_assets > total_debt) {
            profit = total_assets - total_debt;
        } else {
            loss = total_debt - total_assets;
        };

        (profit, loss, debt_payment)
    }

    // calls a vault's assess_fees function for a specified gain amount
    fun assess_fees<BaseCoin>(gain: u64, vault_cap: &VaultCapability) {
        vault::assess_fees<DittoStrategy, BaseCoin>(gain, 0, vault_cap, DittoStrategy {});
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
        router::swap_exact_coin_for_coin<CoinType, BaseCoin, Uncorrelated>(
            coins,
            0
        )
    }

}
