module satay::usdt_btc_strategy {

    use aptos_framework::coin::{Self, Coin};
    // use aptos_framework::signer;

    use liquidswap::router;
    
    use liquidswap_lp::coins::{USDT, BTC};
    use liquidswap_lp::lp::LP;

    use satay::vault;
    use satay::satay;

    const ERR_NO_PERMISSIONS: u64 = 201;
    const ERR_INITIALIZE: u64 = 202;
    const ERR_NO_POSITION: u64 = 203;
    const ERR_NOT_ENOUGH_POSITION: u64 = 204;

    // used for witnessing
    struct UsdtBtcStrategy has drop {}

    
    public fun initialize(_acc: &signer, manager_addr: address, vault_id: u64) {
        let witness = UsdtBtcStrategy {};
        let (vault_cap, stop_handle) = satay::lock_vault<UsdtBtcStrategy>(manager_addr, vault_id, witness);
        if (!vault::has_coin<LP<BTC, USDT>>(&vault_cap)) {
            vault::add_coin<LP<BTC, USDT>>(&vault_cap);
        };
        satay::unlock_vault<UsdtBtcStrategy>(manager_addr, vault_cap, stop_handle);
    }

    public fun run_strategy(_acc: &signer, manager_addr: address, vault_id: u64) {
        let (vault_cap, lock) = satay::lock_vault<UsdtBtcStrategy>(
            manager_addr,
            vault_id,
            UsdtBtcStrategy {}
        );

        let usdt_coins = vault::fetch_pending_coins(&vault_cap);
        let coins_amount = coin::value(&usdt_coins);

        let to_btc = coins_amount / 2;
        let btc_coins = swap<USDT, BTC>(coin::extract(&mut usdt_coins, to_btc));

        let (residual_usdt, residual_btc, lp_coins) = add_liquidity(usdt_coins, btc_coins);
        
        vault::deposit<LP<BTC, USDT>>(&vault_cap, lp_coins);

        coin::merge(&mut residual_usdt, swap<BTC, USDT>(residual_btc));
        vault::deposit<USDT>(&vault_cap, residual_usdt);

        satay::unlock_vault<UsdtBtcStrategy>(manager_addr, vault_cap, lock);
    }

    public fun liquidate_position(_acc: &signer, manager_addr : address, vault_id : u64, amount : u64) : Coin<USDT> {
        let (vault_cap, lock) = satay::lock_vault<UsdtBtcStrategy>(
            manager_addr,
            vault_id,
            UsdtBtcStrategy {}
        );

        let lp_coins = vault::withdraw<LP<BTC, USDT>>(&vault_cap, amount);
        let (btc_coins, usdt_coins) = remove_liquidity(lp_coins);

        coin::merge(&mut usdt_coins, swap<BTC, USDT>(btc_coins));

        satay::unlock_vault<UsdtBtcStrategy>(manager_addr, vault_cap, lock);

        usdt_coins
    }

    fun swap<From, To>(coins: Coin<From>): Coin<To> {
        // swap on AMM
        router::swap_exact_coin_for_coin<From, To, LP<BTC, USDT>>(
            @liquidswap_lp,
            coins,
            1
        )
    }

    fun add_liquidity(usdt_coins : Coin<USDT>, btc_coins : Coin<BTC>) : (Coin<USDT>, Coin<BTC>, Coin<LP<BTC, USDT>>) {
        router::add_liquidity(@liquidswap_lp, usdt_coins, 1, btc_coins, 1)
    }

    fun remove_liquidity(lp_coins : Coin<LP<BTC, USDT>>) : (Coin<BTC>, Coin<USDT>) {
        router::remove_liquidity<BTC, USDT, LP<BTC, USDT>>(@liquidswap_lp, lp_coins, 1, 1)
    }
}
