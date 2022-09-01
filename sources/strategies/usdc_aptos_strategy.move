module satay::usdc_aptos_strategy {
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin::{Self, Coin};
    use liquidswap::router;
    use liquidswap_lp::coins_extended::USDC;
    use liquidswap_lp::lp::LP;

    use satay::vault;
    use satay::satay;

    const ERR_NO_PERMISSIONS: u64 = 201;
    const ERR_INITIALIZE: u64 = 202;
    const ERR_NO_POSITION: u64 = 203;
    const ERR_NOT_ENOUGH_POSITION: u64 = 204;

    // used for witnessing
    struct UsdcAptosStrategy has drop {}

    public fun initialize(_acc: &signer, manager_addr: address, vault_id: u64) {
        let witness = UsdcAptosStrategy {};
        let (vault_cap, stop_handle) = satay::lock_vault_cap<UsdcAptosStrategy>(manager_addr, vault_id, witness);
        if (!vault::has_coin<USDC>(&vault_cap)) {
            vault::add_coin<USDC>(&vault_cap);
        };
        if (!vault::has_coin<AptosCoin>(&vault_cap)) {
            vault::add_coin<AptosCoin>(&vault_cap);
        };
        satay::unlock_vault_cap<UsdcAptosStrategy>(manager_addr, vault_cap, stop_handle);
    }

    public fun run_strategy(_acc: &signer, manager_addr: address, vault_id: u64) {
        let witness = UsdcAptosStrategy {};
        let (vault_cap, lock) = satay::lock_vault_cap<UsdcAptosStrategy>(
            manager_addr,
            vault_id,
            witness
        );

        let usdc_coins = vault::fetch_pending_coins(&vault_cap);
        let coins_amount = coin::value(&usdc_coins);

        let to_usdc = coins_amount / 2;
        vault::deposit(
            &vault_cap,
            coin::extract(&mut usdc_coins, to_usdc)
        );

        let aptos_coins = swap<USDC, AptosCoin>(usdc_coins);
        vault::deposit(&vault_cap, aptos_coins);

        satay::unlock_vault_cap<UsdcAptosStrategy>(manager_addr, vault_cap, lock);
    }

    fun swap<From, To>(coins: Coin<From>): Coin<To> {
        // swap on AMM
        router::swap_exact_coin_for_coin<From, To, LP<USDC, AptosCoin>>(
            @liquidswap_lp,
            coins,
            1
        )
    }
}
