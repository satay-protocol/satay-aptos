#[test_only]
module satay::vault_tests {
    use std::signer;
    use std::string;

    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin;
    use aptos_framework::genesis;
    use liquidswap::liquidity_pool;
    use liquidswap_lp::coins;
    use liquidswap_lp::coins_extended::{Self, USDC};
    use liquidswap_lp::lp::LP;

    use satay::vault;

    #[test(
        aptos_framework = @aptos_framework,
        token_admin = @liquidswap_lp,
        pool_owner = @liquidswap_lp,
        vault_owner = @usdc_vault,
        user = @0x44
    )]
    fun test_vault_end_to_end(
        aptos_framework: signer,
        token_admin: signer,
        pool_owner: signer,
        vault_owner: signer,
        user: signer
    ) {
        genesis::setup();
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);

        coins::register_coins(&token_admin);
        coins_extended::register_coins(&token_admin);

        vault::register(&vault_owner);

        liquidity_pool::register<USDC, AptosCoin, LP<USDC, AptosCoin>>(
            &pool_owner,
            string::utf8(b"LP"),
            string::utf8(b"LP"),
            1
        );
        let user_address = signer::address_of(&user);
        coin::register_for_test<USDC>(&user);
        coin::register_for_test<AptosCoin>(&user);

        coins_extended::mint_coin<USDC>(&token_admin, user_address, 100000);
        aptos_coin::mint(&aptos_framework, user_address, 100000);

        let usdc = coin::withdraw<USDC>(&user, 100000);
        let aptos = coin::withdraw<AptosCoin>(&user, 100000);
        let lp = liquidity_pool::mint<USDC, AptosCoin, LP<USDC, AptosCoin>>(
            signer::address_of(&pool_owner),
            usdc,
            aptos
        );
        coin::register_for_test<LP<USDC, AptosCoin>>(&user);
        coin::deposit(user_address, lp);

        coins_extended::mint_coin<USDC>(&token_admin, signer::address_of(&user), 1000);

        let usdc_coins = coin::withdraw<USDC>(&user, 500);
        vault::deposit(
            &user,
            signer::address_of(&vault_owner),
            usdc_coins
        );
    }
}




















