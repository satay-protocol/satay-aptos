module satay::ditto_strategy {
    use aptos_framework::account::{Self, SignerCapability, create_signer_with_capability};
    use aptos_std::type_info;
    use satay::satay;
    use std::signer;
    use satay::vault;
    use aptos_framework::coin;
    use liquidswap_lp::lp_coin::LP;
    use aptos_framework::aptos_coin::AptosCoin;
    use liquidswap::curves::Stable;
    use aptos_framework::coin::Coin;
    use liquidswap::router;
    use satay::vault::VaultCapability;
    use ditto_staking::staked_coin::StakedAptos;
    use ditto_staking::ditto_staking;
    use liquidity_mining::liquidity_mining;
    use liquidswap::router::{get_reserves_for_lp_coins, get_amount_out, remove_liquidity, swap_exact_coin_for_coin};


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
    public fun withdraw_from_user<BaseCoin>(user: &signer, manager_addr: address, vault_id: u64, share_amount: u64) {
        let (vault_cap, stop_handle) = satay::lock_vault<DittoStrategy>(manager_addr, vault_id, DittoStrategy {});

        // check if user is eligible to withdraw
        let user_share_amount = coin::balance<vault::VaultCoin<BaseCoin>>(signer::address_of(user));
        assert!(user_share_amount >= share_amount, ERR_NOT_ENOUGH_FUND);

        // check if vault has enough balance
        let user_amount = vault::calculate_amount_from_share<BaseCoin>(&vault_cap, share_amount);
        assert!(vault::balance<BaseCoin>(&vault_cap) < user_amount, ERR_ENOUGH_BALANCE_ON_VAULT);

        // reclaim user_amount to vault
        let coins = liquidate_position(&vault_cap, user_amount);
        vault::update_total_debt<DittoStrategy>(&mut vault_cap, 0, coin::value(&coins));
        vault::deposit<AptosCoin>(&vault_cap, coins);

        satay::unlock_vault<DittoStrategy>(manager_addr, vault_cap, stop_handle);
    }

    // adds BaseCoin to 3rd party protocol to get yield
    // if 3rd party protocol returns a coin, it should be sent to the vault
    fun apply_position(vault_cap: &VaultCapability, coins: Coin<AptosCoin>) {
        let vault_storage_signer = vault::get_storage_signer(vault_cap);
        // 1. exchange half of APT to stAPT
        let coin_amount = coin::value<AptosCoin>(&coins);
        let half_aptos = coin::extract(&mut coins, coin_amount / 2);
        let stAPT = ditto_staking::exchange_aptos(half_aptos, signer::address_of(&vault_storage_signer));
        // 2. add liquidity with APT and stAPT
        // TODO: handle dust amount
        // convert stPAT using instant_exchange and send back to the vault
        let (rest_stk_apt, rest_apt, lp) =
            router::add_liquidity<StakedAptos, AptosCoin, Stable>(stAPT, 1, coins, 1);
        coin::merge(&mut rest_apt, swap_exact_coin_for_coin<StakedAptos, AptosCoin, Stable>(rest_stk_apt, 1));
        vault::deposit(vault_cap, rest_apt);
        let lp_amount = coin::value(&lp);
        // 3. stake stAPTOS-APTOS pool for Ditto pre-mine program
        vault::deposit<LP<StakedAptos, AptosCoin, Stable>>(vault_cap, lp);
        liquidity_mining::stake<LP<StakedAptos, AptosCoin, Stable>>(&vault_storage_signer, lp_amount);
    }

    // removes BaseCoin from 3rd party protocol to get yield
    // @param amount: aptos amount
    fun liquidate_position(vault_cap: &VaultCapability, amount: u64): Coin<AptosCoin> {
        let vault_storage_signer = vault::get_storage_signer(vault_cap);
        // calcuate required LP token amount to withdraw
        let (st_apt_amount, apt_amount) = get_reserves_for_lp_coins<StakedAptos, AptosCoin, Stable>(10000);
        let stapt_to_apt_amount = get_amount_out<StakedAptos, AptosCoin, Stable>(st_apt_amount);
        let lp_to_unstake = amount * 10000 / (stapt_to_apt_amount + apt_amount);
        // withdraw and get apt coin
        // liquidity_mining::redeem<LP<StakedAptos, AptosCoin, Stable>, DTOCoinType>()
        liquidity_mining::unstake<LP<StakedAptos, AptosCoin, Stable>>(&vault_storage_signer, lp_to_unstake);
        let lp_coins = coin::withdraw<LP<StakedAptos, AptosCoin, Stable>>(&vault_storage_signer, coin::balance<LP<StakedAptos, AptosCoin, Stable>>(signer::address_of(&vault_storage_signer)));
        let (staked_aptos, aptos_coin) = remove_liquidity<StakedAptos, AptosCoin, Stable>(lp_coins, 1, 1);
        let aptos_from_swap = swap_exact_coin_for_coin<StakedAptos, AptosCoin, Stable>(staked_aptos, 1);
        coin::merge(&mut aptos_coin, aptos_from_swap);
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
    public entry fun harvest<CoinType, BaseCoin>(manager_addr: address, vault_id: u64) {
        let (vault_cap, stop_handle) = satay::lock_vault<DittoStrategy>(manager_addr, vault_id, DittoStrategy {});
        // claim rewards and swap them into BaseCoin

        let coins = claim_rewards_from_ditto();
        apply_position(&vault_cap, coins);


        let (profit, loss, debt_payment) = prepare_return<BaseCoin>(&vault_cap);

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
            let coins =  vault::withdraw<AptosCoin>(&vault_cap, credit - total_available);
            apply_position(&vault_cap, coins);
        } else { // credit deficit, take from Strategy
            let coins = liquidate_position(&vault_cap, total_available - credit);
            vault::deposit<AptosCoin>(&vault_cap, coins);
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
    fun prepare_return<BaseCoin>(vault_cap: &VaultCapability) : (u64, u64, u64) {
        // get amount of strategy debt over limit
        let debt_out_standing = vault::debt_out_standing<DittoStrategy, BaseCoin>(vault_cap);
        // balance of staking pool
        // get user staked(LP) amount from liquidity_mining
        // convert LP to aptos
        let total_assets = 0;
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
        router::swap_exact_coin_for_coin<CoinType, BaseCoin, Stable>(
            coins,
            0
        )
    }

}
