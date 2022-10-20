module satay::base_strategy {

    use aptos_framework::coin::{Coin};
    use satay::staking_pool::{Self, claimRewards};
    use liquidswap::router;
    use liquidswap::curves::Uncorrelated;
    use std::signer;
    use satay::satay;
    use aptos_std::type_info;
    use satay::vault;
    // use satay::satay;

    struct BaseStrategy has drop {}

    // It should be removed for actual implementation
    struct PoolBaseCoin has store {}

    const ERR_NOT_ENOUGH_FUND: u64 = 301;
    const ERR_ENOUGH_BALANCE_ON_VAULT: u64 = 302;

    // initialize vault_cap to accept strategy
    public fun initialize(manager: &signer, vault_id: u64) {
        let manager_addr = signer::address_of(manager);
        let witness = BaseStrategy {};

        satay::approve_strategy<BaseStrategy>(manager, vault_id, type_info::type_of<PoolBaseCoin>());
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
    public fun withdraw_from_user<BaseCoin>(user: &signer, manager_addr: address, vault_id: u64, amount: u64) {
        let _witness = BaseStrategy {};
        let (vault_cap, stop_handle) = satay::lock_vault<BaseStrategy>(manager_addr, vault_id, _witness);

        // check if user is eligible to withdraw
        let user_deposited_amount = vault::get_user_amount(&vault_cap, signer::address_of(user));
        assert!(user_deposited_amount >= amount, ERR_NOT_ENOUGH_FUND);

        // check if vault has enough balance
        assert!(vault::balance<BaseCoin>(&vault_cap) < amount, ERR_ENOUGH_BALANCE_ON_VAULT);
        liquidate_position<BaseCoin>(manager_addr, vault_id, amount);
        satay::unlock_vault<BaseStrategy>(manager_addr, vault_cap, stop_handle);
    }


    /**
     *  @notice
     *  This function adds underyling to 3rd party service to get yield
    */
    fun apply_position<BaseCoin>(manager_addr : address, vault_id: u64, amount: u64) {
        let witness = BaseStrategy {};

        let (vault_cap, stop_handle) = satay::lock_vault<BaseStrategy>(manager_addr, vault_id, witness);
        let base_coins = vault::withdraw<BaseCoin>(&vault_cap, amount);
        staking_pool::deposit(@staking_pool_manager, base_coins);

        // deposit to the vault if there's any share token from 3rd party staking pool

        satay::unlock_vault<BaseStrategy>(manager_addr, vault_cap, stop_handle);
    }

    fun liquidate_position<BaseCoin>(manager_addr: address, vault_id: u64, amount: u64) {
        let witness = BaseStrategy {};

        let (vault_cap, stop_handle) = satay::lock_vault<BaseStrategy>(manager_addr, vault_id, witness);
        let coins = staking_pool::withdraw<BaseCoin>(@staking_pool_manager, amount);
        vault::deposit<BaseCoin>(&vault_cap, coins);
        satay::unlock_vault<BaseStrategy>(manager_addr, vault_cap, stop_handle);
    }

    /**
    *   @notice
    *   It is for harvest
    */
    public entry fun harvest<CoinType, BaseCoin>() {
        let coins = claimRewards<CoinType>(@staking_pool_manager);
        let want_coins = swap_to_want_token<CoinType, BaseCoin>(coins);

        // re-invest
        staking_pool::deposit(@staking_pool_manager, want_coins);
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
}
