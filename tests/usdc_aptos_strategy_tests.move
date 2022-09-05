#[test_only]
module satay::usdc_aptos_strategy_tests {
    use std::signer;
    use std::string;

    use aptos_framework::account;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin;
    use aptos_framework::stake;
    use liquidswap::liquidity_pool;
    use liquidswap_lp::coins;
    use liquidswap_lp::coins_extended::{Self, USDC};
    use liquidswap_lp::lp::LP;

    use satay::satay;
    use satay::usdc_aptos_strategy::{Self, UsdcAptosStrategy};

    #[test(
        aptos_framework = @aptos_framework,
        manager_acc = @satay,
    )]
    fun test_vault_end_to_end(aptos_framework: signer, manager_acc: signer) {
        stake::initialize_for_test(&aptos_framework);

        let pool_owner = account::create_account_for_test(@liquidswap_lp);
        coins::register_coins(&pool_owner);
        coins_extended::register_coins(&pool_owner);

        liquidity_pool::register<USDC, AptosCoin, LP<USDC, AptosCoin>>(
            &pool_owner,
            string::utf8(b"LP"),
            string::utf8(b"LP"),
            1
        );

        let user = account::create_account_for_test(@0x45);
        let user_address = signer::address_of(&user);
        coin::register<USDC>(&user);
        coin::register<AptosCoin>(&user);

        coins_extended::mint_coin<USDC>(&pool_owner, user_address, 100000);
        aptos_coin::mint(&aptos_framework, user_address, 100000);

        let usdc = coin::withdraw<USDC>(&user, 100000);
        let aptos = coin::withdraw<AptosCoin>(&user, 100000);
        let lp = liquidity_pool::mint<USDC, AptosCoin, LP<USDC, AptosCoin>>(
            signer::address_of(&pool_owner),
            usdc,
            aptos
        );
        coin::register<LP<USDC, AptosCoin>>(&user);
        coin::deposit(user_address, lp);

        coins_extended::mint_coin<USDC>(&pool_owner, signer::address_of(&user), 1000);

        satay::initialize(&manager_acc);
        satay::new_vault<USDC>(&manager_acc, b"usdc_aptos_vault_50_50");
        satay::approve_strategy<UsdcAptosStrategy>(&manager_acc, 0);

        usdc_aptos_strategy::initialize(&manager_acc, @satay, 0);

        satay::deposit<USDC>(&user, @satay, 0, 1000);

        usdc_aptos_strategy::run_strategy(&manager_acc, @satay, 0);

        satay::withdraw<USDC>(&user, @satay, 0, 300);
    }
}




















