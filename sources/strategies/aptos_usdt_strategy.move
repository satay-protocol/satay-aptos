module satay::aptos_usdt_strategy {

    use std::signer;

    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::AptosCoin;

    use liquidswap::router;
    use liquidswap::curves::{Uncorrelated};

    use test_coins::coins::{USDT};
    use liquidswap_lp::lp_coin::{LP};

    use satay::vault::{Self, VaultCapability, lp_balance};
    use satay::satay;
    use aptos_std::type_info;
    friend satay::vault;

    const ERR_NO_PERMISSIONS: u64 = 201;
    const ERR_INITIALIZE: u64 = 202;
    const ERR_NO_POSITION: u64 = 203;
    const ERR_NOT_ENOUGH_POSITION: u64 = 204;
    const ERR_INVALID_COINTYPE: u64 = 205;

    // used for witnessing
    struct AptosUsdcLpStrategy has drop {}

    public entry fun initialize(manager: &signer, vault_id: u64) {
        let manager_addr = signer::address_of(manager);

        let witness = AptosUsdcLpStrategy {};

        satay::approve_strategy<AptosUsdcLpStrategy>(manager, vault_id, type_info::type_of<LP<USDT, AptosCoin, Uncorrelated>>());

        let (vault_cap, stop_handle) = satay::lock_vault<AptosUsdcLpStrategy>(manager_addr, vault_id, witness);
        if (!vault::has_coin<LP<USDT, AptosCoin, Uncorrelated>>(&vault_cap)) {
            vault::add_coin<LP<USDT, AptosCoin, Uncorrelated>>(&vault_cap);
        };
        satay::unlock_vault<AptosUsdcLpStrategy>(manager_addr, vault_cap, stop_handle);
    }

    public entry fun apply_strategy(manager: &signer, vault_id: u64, amount : u64) {
        let manager_addr = signer::address_of(manager);
        let (vault_cap, lock) = satay::lock_vault<AptosUsdcLpStrategy>(
            manager_addr,
            vault_id,
            AptosUsdcLpStrategy {}
        );

        let aptos_coins = vault::withdraw(&vault_cap, amount);

        // increase total_debt
        vault::increase_total_debt(&mut vault_cap, amount);

        let to_usdt = coin::value((&aptos_coins)) / 2;

        let usdt_coins = swap<AptosCoin, USDT>(coin::extract(&mut aptos_coins, to_usdt));

        let (residual_usdt, residual_aptos, aptos_usdt_lp_coins) = add_liquidity(aptos_coins, usdt_coins);

        vault::deposit<LP<USDT, AptosCoin, Uncorrelated>>(&vault_cap, aptos_usdt_lp_coins);

        if(coin::value(&residual_usdt) > 0){
            coin::merge(&mut residual_aptos, swap<USDT, AptosCoin>(residual_usdt));
        } else {
            // TODO: need a better disposal mechanism
            if (!vault::has_coin<USDT>(&vault_cap)) {
                vault::add_coin<USDT>(&vault_cap);
            };
            vault::deposit<USDT>(&vault_cap, residual_usdt);
        };

        vault::deposit<AptosCoin>(&vault_cap, residual_aptos);

        // increase total_debt
        vault::increase_total_debt(&mut vault_cap, amount);

        satay::unlock_vault<AptosUsdcLpStrategy>(manager_addr, vault_cap, lock);
    }

    public(friend) entry fun liquidate_strategy(vault_id : u64, amount : u64) {
        let (vault_cap, lock) = satay::lock_vault<AptosUsdcLpStrategy>(
            @manager,
            vault_id,
            AptosUsdcLpStrategy {}
        );

        let lp_coins = vault::withdraw<LP<USDT, AptosCoin, Uncorrelated>>(&vault_cap, amount);
        // decrease total_debt
        vault::decrease_total_debt(&mut vault_cap, amount);

        let (usdt_coins, aptos_coins) = remove_liquidity(lp_coins);
        coin::merge(&mut aptos_coins, swap<USDT, AptosCoin>(usdt_coins));

        vault::deposit<AptosCoin>(&vault_cap, aptos_coins);

        satay::unlock_vault<AptosUsdcLpStrategy>(
            @manager,
            vault_cap,
            lock
        );
    }

    /// NOTE: harvest function is not used in this strategy but added for strategy standard
    public entry fun harvest<CoinType>(manager: &signer, vault_id: u64) {
        // consider explicitly use AptosCoin for CoinType
        let manager_addr = signer::address_of(manager);
        // check if its profitable
        let (vault_cap, lock) = satay::lock_vault<AptosUsdcLpStrategy>(
            manager_addr,
            vault_id,
            AptosUsdcLpStrategy {}
        );
        assert!(vault::has_coin<CoinType>(&vault_cap), ERR_INVALID_COINTYPE);
        let currentAptos = get_aptos_reserves_for_lp_coins(&vault_cap);
        let total_debt = vault::total_debt(&vault_cap);
        if (currentAptos < total_debt) {
            // not profitable
        } else {

        };

        satay::unlock_vault<AptosUsdcLpStrategy>(manager_addr, vault_cap, lock);
    }

    fun swap<From, To>(coins: Coin<From>): Coin<To> {
        // swap on AMM
        router::swap_exact_coin_for_coin<From, To, Uncorrelated>(
            coins,
            0
        )
    }

    fun add_liquidity(
        aptos_coins : Coin<AptosCoin>,
        usdt_coins : Coin<USDT>
    ) : (
        Coin<USDT>,
        Coin<AptosCoin>,
        Coin<LP<USDT, AptosCoin, Uncorrelated>>
    ) {
        router::add_liquidity<USDT, AptosCoin, Uncorrelated>(usdt_coins, 1, aptos_coins, 1)
    }

    fun remove_liquidity(
        lp_coins : Coin<LP<USDT, AptosCoin, Uncorrelated>>
    ) : (
        Coin<USDT>, Coin<AptosCoin>
    ) {
        router::remove_liquidity<USDT, AptosCoin, Uncorrelated>(lp_coins, 1, 1)
    }

    fun get_aptos_reserves_for_lp_coins(vault_cap: &VaultCapability): u64 {
        let lp_balance = lp_balance<LP<USDT, AptosCoin, Uncorrelated>>(vault_cap);
        let (reserve0, reserve1) = router::get_reserves_for_lp_coins<USDT, AptosCoin, Uncorrelated>(lp_balance);
        let reserve0ToAptos = router::get_amount_out<USDT, AptosCoin, Uncorrelated>(reserve0);
        reserve0ToAptos + reserve1
    }
}
