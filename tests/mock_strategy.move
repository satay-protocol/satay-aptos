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
            stop_handle
        ) = base_strategy::open_vault_for_harvest<MockStrategy, AptosCoin>(
            keeper,
            vault_id,
            MockStrategy {}
        );

        let wrapped_aptos = aptos_wrapper_product::reinvest_returns();
        base_strategy::deposit_strategy_coin<MockStrategy, WrappedAptos>(
            &vault_cap,
            wrapped_aptos,
            &stop_handle
        );

        let strategy_aptos_balance = get_strategy_aptos_balance(&vault_cap);
        let (
            to_apply,
            amount_needed
        ) = base_strategy::process_harvest<MockStrategy, AptosCoin, WrappedAptos>(
            &mut vault_cap,
            strategy_aptos_balance,
            &stop_handle,
        );

        let wrapped_aptos = aptos_wrapper_product::apply_position(to_apply);

        let to_return = coin::zero<AptosCoin>();
        if(amount_needed > 0) {
            let wrapped_aptos_to_withdraw = get_wrapped_amount_for_aptos_amount(amount_needed);
            let wrapped_aptos = base_strategy::withdraw_strategy_coin<MockStrategy, WrappedAptos>(
                &vault_cap,
                wrapped_aptos_to_withdraw,
                &stop_handle,
            );
            let aptos_to_return = aptos_wrapper_product::liquidate_position(wrapped_aptos);
            coin::merge(&mut to_return, aptos_to_return);
        };

        base_strategy::close_vault_for_harvest<MockStrategy, AptosCoin, WrappedAptos>(
            vault_cap,
            stop_handle,
            to_return,
            wrapped_aptos,
        );

    }

    fun harvest_trigger(
        keeper: &signer,
        vault_id: u64,
    ): bool {
        let (
            vault_cap,
            stop_handle
        ) = base_strategy::open_vault_for_harvest<MockStrategy, AptosCoin>(
            keeper,
            vault_id,
            MockStrategy {}
        );

        let harvest_trigger = base_strategy::process_harvest_trigger<MockStrategy, AptosCoin>(
            &vault_cap,
        );

        base_strategy::close_vault_for_harvest_trigger<MockStrategy>(
            vault_cap,
            stop_handle,
        );

        harvest_trigger
    }

    public entry fun tend(
        keeper: &signer,
        vault_id: u64,
    ) {
        let (
            vault_cap,
            stop_handle
        ) = base_strategy::open_vault_for_tend<MockStrategy, AptosCoin>(
            keeper,
            vault_id,
            MockStrategy {}
        );

        let wrapped_aptos = aptos_wrapper_product::reinvest_returns();

        base_strategy::close_vault_for_tend<MockStrategy, WrappedAptos>(
            vault_cap,
            stop_handle,
            wrapped_aptos,
        );
    }

    public entry fun withdraw_for_user(
        user: &signer,
        vault_id: u64,
        share_amount: u64,
    ) {
        let (
            amount_aptos_needed,
            vault_cap,
            stop_handle
        ) = base_strategy::open_vault_for_user_withdraw<MockStrategy, AptosCoin, WrappedAptos>(
            user,
            vault_id,
            share_amount,
            MockStrategy {}
        );

        let to_return = coin::zero<AptosCoin>();
        if(amount_aptos_needed > 0){
            let wrapped_aptos_to_withdraw = get_wrapped_amount_for_aptos_amount(amount_aptos_needed);
            let wrapped_aptos = base_strategy::withdraw_strategy_coin<MockStrategy, WrappedAptos>(
                &vault_cap,
                wrapped_aptos_to_withdraw,
                &stop_handle,
            );
            let aptos_to_return = aptos_wrapper_product::liquidate_position(wrapped_aptos);
            coin::merge(&mut to_return, aptos_to_return);
        };

        base_strategy::close_vault_for_user_withdraw<MockStrategy, AptosCoin>(
            vault_cap,
            stop_handle,
            to_return,
            amount_aptos_needed
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

    // update the strategy credit threshold
    public entry fun update_credit_threshold(
        vault_manager: &signer,
        vault_id: u64,
        credit_threshold: u64
    ) {
        base_strategy::update_credit_threshold<MockStrategy, AptosCoin>(
            vault_manager,
            vault_id,
            credit_threshold,
            MockStrategy {}
        );
    }

    // set the strategy force harvest trigger once
    public entry fun set_force_harvest_trigger_once(
        vault_manager: &signer,
        vault_id: u64,
    ) {
        base_strategy::set_force_harvest_trigger_once<MockStrategy, AptosCoin>(
            vault_manager,
            vault_id,
            MockStrategy {}
        );
    }

    // update the strategy max report delay
    public entry fun update_max_report_delay(
        strategist: &signer,
        vault_id: u64,
        max_report_delay: u64
    ) {
        base_strategy::update_max_report_delay<MockStrategy, AptosCoin>(
            strategist,
            vault_id,
            max_report_delay,
            MockStrategy {}
        );
    }

    fun get_strategy_aptos_balance(vault_cap: &VaultCapability): u64 {
        let wrapped_balance = base_strategy::balance<WrappedAptos>(vault_cap);
        aptos_wrapper_product::get_aptos_amount_for_wrapped_amount(wrapped_balance)
    }

    fun get_wrapped_amount_for_aptos_amount(aptos_amount: u64): u64 {
        aptos_wrapper_product::get_wrapped_amount_for_aptos_amount(aptos_amount)
    }
}