#[test_only]
module satay::mock_strategy {

    use aptos_framework::aptos_coin::AptosCoin;

    use satay::base_strategy;
    use satay::vault::VaultCapability;
    use satay::aptos_wrapper_product::{Self, WrappedAptos};
    use aptos_framework::coin;

    struct MockStrategy has drop {}

    public entry fun initialize(
        governance: &signer,
        vault_id: u64,
        debt_ratio: u64,
    ) {
        base_strategy::initialize<MockStrategy, WrappedAptos>(
            governance,
            vault_id,
            debt_ratio,
            MockStrategy {}
        );
    }

    public entry fun harvest(
        keeper: &signer,
        vault_id: u64,
    ) {
        let (
            vault_cap,
            vault_cap_lock
        ) = base_strategy::open_vault_for_harvest<MockStrategy, AptosCoin>(
            keeper,
            vault_id,
            MockStrategy {}
        );

        let wrapped_aptos = aptos_wrapper_product::reinvest_returns();
        base_strategy::deposit_strategy_coin<MockStrategy, WrappedAptos>(
            &vault_cap,
            wrapped_aptos,
            &vault_cap_lock
        );

        let strategy_aptos_balance = get_strategy_aptos_balance(&vault_cap);
        let (
            to_apply,
            harvest_lock
        ) = base_strategy::process_harvest<MockStrategy, AptosCoin, WrappedAptos>(
            &mut vault_cap,
            strategy_aptos_balance,
            vault_cap_lock,
        );

        let profit_coins = coin::zero<AptosCoin>();
        let debt_payment_coins = coin::zero<AptosCoin>();

        let profit = base_strategy::get_harvest_profit(&harvest_lock);
        let debt_payment = base_strategy::get_harvest_debt_payment(&harvest_lock);

        if(profit > 0 || debt_payment > 0){
            let wrapped_aptos_to_liquidate = get_wrapped_amount_for_aptos_amount(profit + debt_payment);
            let wrapped_aptos = base_strategy::withdraw_strategy_coin<MockStrategy, WrappedAptos>(
                &vault_cap,
                wrapped_aptos_to_liquidate,
                base_strategy::get_harvest_vault_cap_lock(&harvest_lock)
            );
            let aptos_to_return = aptos_wrapper_product::liquidate_position(wrapped_aptos);
            coin::merge(&mut profit_coins, coin::extract(&mut aptos_to_return, profit));
            coin::merge(&mut debt_payment_coins, coin::extract(&mut aptos_to_return, debt_payment));
            coin::destroy_zero(aptos_to_return);
        };

        let wrapped_aptos = aptos_wrapper_product::apply_position(to_apply);

        base_strategy::close_vault_for_harvest<MockStrategy, AptosCoin, WrappedAptos>(
            vault_cap,
            harvest_lock,
            debt_payment_coins,
            profit_coins,
            wrapped_aptos,
        );
    }

    public entry fun tend(
        keeper: &signer,
        vault_id: u64,
    ) {
        let (
            vault_cap,
            tend_lock
        ) = base_strategy::open_vault_for_tend<MockStrategy, AptosCoin>(
            keeper,
            vault_id,
            MockStrategy {}
        );

        let wrapped_aptos = aptos_wrapper_product::reinvest_returns();

        base_strategy::close_vault_for_tend<MockStrategy, WrappedAptos>(
            vault_cap,
            tend_lock,
            wrapped_aptos,
        );
    }

    public entry fun withdraw_for_user(
        user: &signer,
        vault_id: u64,
        share_amount: u64,
    ) {
        let (
            vault_cap,
            user_withdraw_lock
        ) = base_strategy::open_vault_for_user_withdraw<MockStrategy, AptosCoin, WrappedAptos>(
            user,
            vault_id,
            share_amount,
            MockStrategy {}
        );

        let vault_cap_lock = base_strategy::get_user_withdraw_vault_cap_lock(&user_withdraw_lock);
        let amount_needed = base_strategy::get_user_withdraw_amount_needed(&user_withdraw_lock);

        let to_return = coin::zero<AptosCoin>();
        if(amount_needed > 0){
            let wrapped_aptos_to_withdraw = get_wrapped_amount_for_aptos_amount(amount_needed);
            let wrapped_aptos = base_strategy::withdraw_strategy_coin<MockStrategy, WrappedAptos>(
                &vault_cap,
                wrapped_aptos_to_withdraw,
                vault_cap_lock,
            );
            let aptos_to_return = aptos_wrapper_product::liquidate_position(wrapped_aptos);
            coin::merge(&mut to_return, aptos_to_return);
        };

        base_strategy::close_vault_for_user_withdraw<MockStrategy, AptosCoin>(
            vault_cap,
            user_withdraw_lock,
            to_return,
        );
    }

    // update the strategy debt ratio
    public entry fun update_debt_ratio(
        vault_manager: &signer,
        vault_id: u64,
        debt_ratio: u64
    ) {
        base_strategy::update_debt_ratio<MockStrategy, AptosCoin>(
            vault_manager,
            vault_id,
            debt_ratio,
            MockStrategy {}
        );
    }

    public entry fun revoke(
        vault_manager: &signer,
        vault_id: u64
    ) {
        base_strategy::revoke_strategy<MockStrategy, AptosCoin>(
            vault_manager,
            vault_id,
            MockStrategy {}
        );
        harvest(vault_manager, vault_id);
    }

    fun get_strategy_aptos_balance(vault_cap: &VaultCapability): u64 {
        let wrapped_balance = base_strategy::balance<WrappedAptos>(vault_cap);
        aptos_wrapper_product::get_aptos_amount_for_wrapped_amount(wrapped_balance)
    }

    fun get_wrapped_amount_for_aptos_amount(aptos_amount: u64): u64 {
        aptos_wrapper_product::get_wrapped_amount_for_aptos_amount(aptos_amount)
    }
}