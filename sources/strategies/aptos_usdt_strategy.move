module satay::aptos_usdt_strategy {

    use std::signer;

    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::AptosCoin;

    use liquidswap::router;

    use liquidswap_lp::lp::{LP};
    use liquidswap_lp::coins::{USDT};

    use satay::vault;
    use satay::satay;
    use aptos_std::type_info::{
        Self,
        TypeInfo
    };

    const ERR_NO_PERMISSIONS: u64 = 201;
    const ERR_INITIALIZE: u64 = 202;
    const ERR_NO_POSITION: u64 = 203;
    const ERR_NOT_ENOUGH_POSITION: u64 = 204;

    struct StrategyCoin has key {
        coin: TypeInfo
    }

    // used for witnessing
    struct AptosUsdcLpStrategy has drop {}

    public entry fun initialize(manager: &signer, vault_id: u64) {
        let manager_addr = signer::address_of(manager);

        let strategy_coin = StrategyCoin { coin: type_info::type_of<LP<AptosCoin, USDT>>() };
        move_to(manager, strategy_coin);

        let witness = AptosUsdcLpStrategy {};

        let (vault_cap, stop_handle) = satay::lock_vault<AptosUsdcLpStrategy>(manager_addr, vault_id, witness);
        if (!vault::has_coin<LP<AptosCoin, USDT>>(&vault_cap)) {
            vault::add_coin<LP<AptosCoin, USDT>>(&vault_cap);
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

        let to_usdt = coin::value((&aptos_coins)) / 2;

        let usdt_coins = swap<AptosCoin, USDT>(coin::extract(&mut aptos_coins, to_usdt));

        let (residual_usdt, residual_aptos, aptos_usdt_lp_coins) = add_liquidity(aptos_coins, usdt_coins);

        vault::deposit<LP<AptosCoin, USDT>>(&vault_cap, aptos_usdt_lp_coins);

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

        satay::unlock_vault<AptosUsdcLpStrategy>(manager_addr, vault_cap, lock);
    }

    public entry fun liquidate_strategy(manager: &signer, vault_id : u64, amount : u64) {
        let manager_addr = signer::address_of(manager);
        let (vault_cap, lock) = satay::lock_vault<AptosUsdcLpStrategy>(
            manager_addr,
            vault_id,
            AptosUsdcLpStrategy {}
        );

        let lp_coins = vault::withdraw<LP<AptosCoin, USDT>>(&vault_cap, amount);
        let (aptos_coins, usdt_coins) = remove_liquidity(lp_coins);

        coin::merge(&mut aptos_coins, swap<USDT, AptosCoin>(usdt_coins));

        vault::deposit<AptosCoin>(&vault_cap, aptos_coins);

        satay::unlock_vault<AptosUsdcLpStrategy>(
            manager_addr,
            vault_cap,
            lock
        );
    }

    fun swap<From, To>(coins: Coin<From>): Coin<To> {
        // swap on AMM
        router::swap_exact_coin_for_coin<From, To, LP<AptosCoin, USDT>>(
            @liquidswap,
            coins,
            0
        )
    }

    fun add_liquidity(aptos_coins : Coin<AptosCoin>, usdt_coins : Coin<USDT>) : (Coin<USDT>, Coin<AptosCoin>, Coin<LP<AptosCoin, USDT>>) {
        router::add_liquidity(@liquidswap, usdt_coins, 1, aptos_coins, 1)
    }

    fun remove_liquidity(lp_coins : Coin<LP<AptosCoin, USDT>>) : (Coin<AptosCoin>, Coin<USDT>) {
        router::remove_liquidity<AptosCoin, USDT, LP<AptosCoin, USDT>>(@liquidswap, lp_coins, 1, 1)
    }
}
