#[test_only]
module liquidity_mining::mock_liquidity_mining {

    use std::signer;
    use std::string;

    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::coin::{Self, MintCapability, BurnCapability};

    use liquidswap_lp::lp_coin::LP;
    use liquidswap::curves::Stable;
    use aptos_framework::aptos_coin::AptosCoin;
    use ditto_staking::mock_ditto_staking::StakedAptos;

    const ERR_NOT_ADMIN: u64 = 1;

    struct DTO {}

    struct LiquidityMiningAccount has key {
        signer_cap: SignerCapability
    }

    struct DittoCoinCaps has key {
        mint_cap: MintCapability<DTO>,
        burn_cap: BurnCapability<DTO>
    }

    public fun initialize(
        account: &signer,
    ) {
        assert!(signer::address_of(account) == @liquidity_mining, ERR_NOT_ADMIN);
        account::create_account_for_test(@liquidity_mining);

        let (signer, signer_cap) = account::create_resource_account(
            account,
            b"ditto liquidity mining",
        );
        move_to(account, LiquidityMiningAccount { signer_cap });

        coin::register<LP<AptosCoin, StakedAptos, Stable>>(&signer);

        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<DTO>(
            account,
            string::utf8(b"Ditto Governance"),
            string::utf8(b"DTO"),
            8,
            false
        );
        coin::destroy_freeze_cap(freeze_cap);
        move_to(&signer, DittoCoinCaps { mint_cap, burn_cap });
    }

    public entry fun stake<CoinType>(
        user: &signer,
        amount: u64,
    ) acquires LiquidityMiningAccount {
        let lm_account = borrow_global<LiquidityMiningAccount>(@liquidity_mining);
        let lm_account_address = account::get_signer_capability_address(&lm_account.signer_cap);
        let lp_coins = coin::withdraw<LP<AptosCoin, StakedAptos, Stable>>(
            user,
            amount,
        );
        coin::deposit(lm_account_address, lp_coins);
    }

    public entry fun unstake<CoinType>(
        user: &signer,
        amount: u64,
    ) acquires LiquidityMiningAccount {
        let lm_account = borrow_global<LiquidityMiningAccount>(@liquidity_mining);
        let lm_account_signer = account::create_signer_with_capability(&lm_account.signer_cap);
        let lp_coins = coin::withdraw<LP<AptosCoin, StakedAptos, Stable>>(
            &lm_account_signer,
            amount,
        );
        coin::deposit(signer::address_of(user), lp_coins);
    }

    public entry fun redeem<StakedCoin, RewardCoin>(user: &signer) acquires LiquidityMiningAccount, DittoCoinCaps {
        let lm_account = borrow_global<LiquidityMiningAccount>(@liquidity_mining);
        let lm_account_address = account::get_signer_capability_address(&lm_account.signer_cap);
        let dto_caps = borrow_global<DittoCoinCaps>(lm_account_address);
        let dto_mint_cap = &dto_caps.mint_cap;
        let dto_coins = coin::mint<DTO>(100, dto_mint_cap);
        coin::deposit(signer::address_of(user), dto_coins);
    }

    public fun get_lp_amount(): u64 acquires LiquidityMiningAccount {
        let lm_account = borrow_global<LiquidityMiningAccount>(@liquidity_mining);
        let lm_account_address = account::get_signer_capability_address(&lm_account.signer_cap);
        coin::balance<LP<AptosCoin, StakedAptos, Stable>>(lm_account_address)
    }
}
