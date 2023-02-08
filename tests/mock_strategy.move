#[test_only]
module satay::mock_strategy {

    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin::{Self, Coin};

    use satay_coins::vault_coin::VaultCoin;
    use satay_coins::strategy_coin::StrategyCoin;

    use satay::base_strategy;
    use satay::satay;

    const ERR_NOT_SATAY: u64 = 1;

    struct MockStrategy has drop {}

    public fun initialize(satay: &signer) {
        satay::new_strategy<MockStrategy, AptosCoin>(satay, MockStrategy {});
    }

    public fun apply_position(aptos_coins: Coin<AptosCoin>): Coin<StrategyCoin<MockStrategy, AptosCoin>> {
        let aptos_value = coin::value(&aptos_coins);
        satay::strategy_deposit<MockStrategy, AptosCoin, AptosCoin>(aptos_coins, MockStrategy {});
        satay::strategy_mint<MockStrategy, AptosCoin>(aptos_value, MockStrategy {})
    }

    public fun liquidate_position(wrapped_aptos_coins: Coin<StrategyCoin<MockStrategy, AptosCoin>>): Coin<AptosCoin> {
        let wrapped_aptos_value = coin::value(&wrapped_aptos_coins);
        satay::strategy_burn(wrapped_aptos_coins, MockStrategy {});
        satay::strategy_withdraw<MockStrategy, AptosCoin, AptosCoin>(wrapped_aptos_value, MockStrategy {})
    }

    public entry fun approve(governance: &signer, vault_id: u64, debt_ratio: u64, ) {
        base_strategy::initialize<MockStrategy, AptosCoin>(
            governance,
            vault_id,
            debt_ratio,
            MockStrategy {}
        );
    }

    public entry fun harvest(keeper: &signer, vault_id: u64, ) {
        let strategy_aptos_balance = get_strategy_aptos_balance(vault_id);

        let (
            to_apply,
            harvest_lock
        ) = base_strategy::open_vault_for_harvest<MockStrategy, AptosCoin>(
            keeper,
            vault_id,
            strategy_aptos_balance,
            MockStrategy {}
        );

        let profit_coins = coin::zero<AptosCoin>();
        let debt_payment_coins = coin::zero<AptosCoin>();

        let profit = base_strategy::get_harvest_profit(&harvest_lock);
        let debt_payment = base_strategy::get_harvest_debt_payment(&harvest_lock);

        if(profit > 0 || debt_payment > 0){
            let wrapped_aptos_to_liquidate = get_wrapped_amount_for_aptos_amount(profit + debt_payment);
            let wrapped_aptos = base_strategy::withdraw_strategy_coin<MockStrategy, AptosCoin>(
                &harvest_lock,
                wrapped_aptos_to_liquidate,
            );
            let aptos_to_return = liquidate_position(wrapped_aptos);
            coin::merge(&mut profit_coins, coin::extract(&mut aptos_to_return, profit));
            coin::merge(&mut debt_payment_coins, coin::extract(&mut aptos_to_return, debt_payment));
            coin::destroy_zero(aptos_to_return);
        };

        let wrapped_aptos = apply_position(to_apply);

        base_strategy::close_vault_for_harvest<MockStrategy, AptosCoin>(
            harvest_lock,
            debt_payment_coins,
            profit_coins,
            wrapped_aptos,
        );
    }

    public entry fun withdraw_for_user(user: &signer, vault_id: u64, share_amount: u64) {
        let vault_coins = coin::withdraw<VaultCoin<AptosCoin>>(user, share_amount);
        let user_withdraw_lock = base_strategy::open_vault_for_user_withdraw<MockStrategy, AptosCoin>(
            user,
            vault_id,
            vault_coins,
            MockStrategy {}
        );

        let amount_needed = base_strategy::get_user_withdraw_amount_needed(&user_withdraw_lock);

        let to_return = coin::zero<AptosCoin>();
        if(amount_needed > 0){
            let wrapped_aptos_to_withdraw = get_wrapped_amount_for_aptos_amount(amount_needed);
            let wrapped_aptos = base_strategy::withdraw_strategy_coin_for_liquidation<MockStrategy, AptosCoin>(
                &user_withdraw_lock,
                wrapped_aptos_to_withdraw,
            );
            let aptos_to_return = liquidate_position(wrapped_aptos);
            coin::merge(&mut to_return, aptos_to_return);
        };

        base_strategy::close_vault_for_user_withdraw<MockStrategy, AptosCoin>(
            user_withdraw_lock,
            to_return,
        );
    }

    // update the strategy debt ratio
    public entry fun update_debt_ratio(vault_manager: &signer, vault_id: u64, debt_ratio: u64) {
        base_strategy::update_debt_ratio<MockStrategy, AptosCoin>(
            vault_manager,
            vault_id,
            debt_ratio,
            MockStrategy {}
        );
    }

    public entry fun revoke(vault_manager: &signer, vault_id: u64) {
        base_strategy::revoke_strategy<MockStrategy, AptosCoin>(
            vault_manager,
            vault_id,
            MockStrategy {}
        );
        harvest(vault_manager, vault_id);
    }

    fun get_strategy_aptos_balance(vault_id: u64): u64 {
        let wrapped_balance = satay::get_vault_balance<StrategyCoin<MockStrategy, AptosCoin>>(vault_id);
        get_aptos_amount_for_wrapped_amount(wrapped_balance)
    }

    public fun get_aptos_amount_for_wrapped_amount(wrapped_amount: u64): u64 {
        wrapped_amount
    }

    public fun get_wrapped_amount_for_aptos_amount(aptos_amount: u64): u64 {
        aptos_amount
    }
}