module satay::base_strategy {

    use aptos_framework::coin::{Coin};
    use satay::staking_pool::{Self};
    use liquidswap::router;
    use liquidswap::curves::Uncorrelated;
    use std::signer;
    use satay::satay;
    use aptos_std::type_info;
    use satay::vault;
    use satay::vault::{VaultCapability};
    use aptos_framework::account::{SignerCapability, create_signer_with_capability};
    use aptos_framework::account;
    // use satay::satay;

    struct BaseStrategy has drop {}

    // It should be removed for actual implementation
    struct PoolBaseCoin has store {}

    struct StrategyCapability has key {
        strategy_cap: SignerCapability,

    }

    const ERR_NOT_ENOUGH_FUND: u64 = 301;
    const ERR_ENOUGH_BALANCE_ON_VAULT: u64 = 302;
    const ERR_LOSS: u64 = 303;

    // initialize vault_cap to accept strategy
    public fun initialize(manager: &signer, vault_id: u64, seed: vector<u8>, debt_ratio: u64) {
        let (_, strategy_cap) = account::create_resource_account(manager, seed);
        move_to(manager, StrategyCapability {strategy_cap});
        let manager_addr = signer::address_of(manager);
        let witness = BaseStrategy {};

        satay::approve_strategy<BaseStrategy>(manager, vault_id, type_info::type_of<PoolBaseCoin>(), debt_ratio);
        let (vault_cap, stop_handle) = satay::lock_vault<BaseStrategy>(manager_addr, vault_id, witness);
        if (!vault::has_coin<PoolBaseCoin>(&vault_cap)) {
            vault::add_coin<PoolBaseCoin>(&vault_cap);
        };
        satay::unlock_vault<BaseStrategy>(manager_addr, vault_cap, stop_handle);
    }

    /**
      * @notice
      * This function suppsoed to be called when the vault doesn't have enough balance than user requested
    */
    public fun withdraw_from_user<BaseCoin>(user: &signer, manager_addr: address, vault_id: u64, amount: u64) acquires StrategyCapability {
        let _witness = BaseStrategy {};
        let (vault_cap, stop_handle) = satay::lock_vault<BaseStrategy>(manager_addr, vault_id, _witness);

        // check if user is eligible to withdraw
        let user_deposited_amount = vault::get_user_amount<BaseCoin>(&vault_cap, signer::address_of(user));
        assert!(user_deposited_amount >= amount, ERR_NOT_ENOUGH_FUND);

        // check if vault has enough balance
        assert!(vault::balance<BaseCoin>(&vault_cap) < amount, ERR_ENOUGH_BALANCE_ON_VAULT);
        let coins = liquidate_position<BaseCoin>(manager_addr, amount);
        vault::deposit<BaseCoin>(&vault_cap, coins);
        satay::unlock_vault<BaseStrategy>(manager_addr, vault_cap, stop_handle);
    }


    /**
     *  @notice
     *  This function adds underyling to 3rd party service to get yield
     *  TODO: if there's protocol based coin from 3rd party, we should send it to the vault
    */
    fun apply_position<BaseCoin>(manager_addr : address, coins: Coin<BaseCoin>) acquires StrategyCapability {
        let signer = get_signer_cap(manager_addr);
        staking_pool::deposit(&signer, coins);
    }

    fun liquidate_position<BaseCoin>(manager_addr: address, amount: u64): Coin<BaseCoin> acquires StrategyCapability {
        let signer = get_signer_cap(manager_addr);
        staking_pool::withdraw<BaseCoin>(&signer, amount)
    }

    /**
    *   @notice
    *   It is for harvest
    */
    public entry fun harvest<CoinType, BaseCoin>(manager_addr: address, vault_id: u64) acquires StrategyCapability {
        let _witness = BaseStrategy {};
        let (vault_cap, stop_handle) = satay::lock_vault<BaseStrategy>(manager_addr, vault_id, _witness);

        let coins = staking_pool::claimRewards<CoinType>(@staking_pool_manager);
        let want_coins = swap_to_want_token<CoinType, BaseCoin>(coins);
        apply_position<BaseCoin>(manager_addr, want_coins);

        let (profit, loss, debt_payment) = prepare_return<BaseCoin>(&vault_cap, manager_addr);

        // loss to report, do it before the rest of the calculation
        if (loss > 0) {
            let total_debt = vault::total_debt<BaseStrategy>(&vault_cap);
            assert!(total_debt >= loss, ERR_LOSS);
            vault::report_loss<BaseStrategy>(&mut vault_cap, loss);
        };

        let credit = vault::credit_available<BaseStrategy, BaseCoin>(&vault_cap);
        let debt = vault::debt_out_standing<BaseStrategy, BaseCoin>(&vault_cap);
        if (debt_payment > debt) {
            debt_payment = debt;
        };

        if (credit > 0 || debt_payment > 0) {
            vault::update_total_debt<BaseStrategy>(&mut vault_cap, credit, debt_payment);
            // debt = debt - debt_payment;
        };

        let total_available = profit + debt_payment;

        if (total_available < credit) { // credit surplus, give to Strategy
            // assess fees
            assess_fees<BaseCoin>(profit, &vault_cap);
            let coins =  vault::withdraw<BaseCoin>(&vault_cap, credit - total_available);
            apply_position<BaseCoin>(manager_addr, coins);
        } else { // credit deficit, take from Strategy
            let coins = liquidate_position<BaseCoin>(manager_addr, total_available - credit);
            vault::deposit<BaseCoin>(&vault_cap, coins);
        };

        satay::unlock_vault<BaseStrategy>(manager_addr, vault_cap, stop_handle);
    }

    fun get_signer_cap(manager_addr : address) : signer acquires StrategyCapability {
        let strategy_cap = borrow_global_mut<StrategyCapability>(manager_addr);
        create_signer_with_capability(&strategy_cap.strategy_cap)
    }

    fun prepare_return<BaseCoin>(vault_cap: &VaultCapability, manager_addr: address) : (u64, u64, u64) acquires StrategyCapability {
        let strategy_cap = borrow_global_mut<StrategyCapability>(manager_addr);
        let signer = create_signer_with_capability(&strategy_cap.strategy_cap);

        let debt_out_standing = vault::debt_out_standing<BaseStrategy, BaseCoin>(vault_cap);
        // needs to be calculate
        let total_assets = staking_pool::balanceOf(signer::address_of(&signer));
        let total_debt = vault::total_debt<BaseStrategy>(vault_cap);

        let profit = 0;
        let loss = 0;
        let debt_payment: u64;
        // 19 > 14
        if (total_assets > debt_out_standing) {
            debt_payment = debt_out_standing;
            total_assets = total_assets - debt_out_standing;
        } else {
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

    fun assess_fees<BaseCoin>(gain: u64, vault_cap: &VaultCapability) {
        vault::assess_fees<BaseStrategy, BaseCoin>(gain, 0, vault_cap, BaseStrategy {});
    }

    public entry fun name() : vector<u8> {
        b"strategy-name"
    }

    public entry fun version() : vector<u8> {
        b"0.0.1"
    }

    fun swap_to_want_token<CoinType, BaseCoin>(coins: Coin<CoinType>) : Coin<BaseCoin> {
        // swap on liquidswap AMM
        router::swap_exact_coin_for_coin<CoinType, BaseCoin, Uncorrelated>(
            coins,
            0
        )
    }

    #[test_only]
    public fun test_prepare_return<CoinType, BaseCoin>(manager_addr: address, vault_id: u64): (u64, u64, u64) acquires StrategyCapability {
        let _witness = BaseStrategy {};
        let (vault_cap, stop_handle) = satay::lock_vault<BaseStrategy>(manager_addr, vault_id, _witness);

        let coins = staking_pool::claimRewards<CoinType>(@staking_pool_manager);
        let want_coins = swap_to_want_token<CoinType, BaseCoin>(coins);
        apply_position<BaseCoin>(manager_addr, want_coins);

        let (profit, loss, debt_payment) = prepare_return<BaseCoin>(&vault_cap, manager_addr);

        satay::unlock_vault<BaseStrategy>(manager_addr, vault_cap, stop_handle);

        (profit, loss, debt_payment)
    }


    #[test_only]
    public entry fun test_harvest<CoinType, BaseCoin>(manager_addr: address, vault_id: u64): (u64, u64) acquires StrategyCapability {
        let _witness = BaseStrategy {};
        let (vault_cap, stop_handle) = satay::lock_vault<BaseStrategy>(manager_addr, vault_id, _witness);

        let coins = staking_pool::claimRewards<CoinType>(@staking_pool_manager);
        let want_coins = swap_to_want_token<CoinType, BaseCoin>(coins);
        apply_position<BaseCoin>(manager_addr, want_coins);

        let (profit, loss, debt_payment) = prepare_return<BaseCoin>(&vault_cap, manager_addr);

        // loss to report, do it before the rest of the calculation
        if (loss > 0) {
            let total_debt = vault::total_debt<BaseStrategy>(&vault_cap);
            assert!(total_debt >= loss, ERR_LOSS);
            vault::report_loss<BaseStrategy>(&mut vault_cap, loss);
        };

        let credit = vault::credit_available<BaseStrategy, BaseCoin>(&vault_cap);
        let debt = vault::debt_out_standing<BaseStrategy, BaseCoin>(&vault_cap);
        if (debt_payment > debt) {
            debt_payment = debt;
        };

        if (credit > 0 || debt_payment > 0) {
            vault::update_total_debt<BaseStrategy>(&mut vault_cap, credit, debt_payment);
            // debt = debt - debt_payment;
        };

        let total_available = profit + debt_payment;

        if (total_available < credit) { // credit surplus, give to Strategy
            let coins =  vault::withdraw<BaseCoin>(&vault_cap, credit - total_available);
            apply_position<BaseCoin>(manager_addr, coins);
        } else { // credit deficit, take from Strategy
            let coins = liquidate_position<BaseCoin>(manager_addr, total_available - credit);
            vault::deposit<BaseCoin>(&vault_cap, coins);
        };

        satay::unlock_vault<BaseStrategy>(manager_addr, vault_cap, stop_handle);

        (total_available, credit)
    }
}
