#[test_only]
module satay::aptos_wrapper_product {

    use std::signer;

    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability, FreezeCapability};
    use aptos_framework::aptos_coin::AptosCoin;
    use std::string;

    const ERR_NOT_SATAY: u64 = 1;

    struct WrappedAptos {}

    struct WrappedAptosCaps has key {
        mint_cap: MintCapability<WrappedAptos>,
        burn_cap: BurnCapability<WrappedAptos>,
        freeze_cap: FreezeCapability<WrappedAptos>,
    }

    struct AptosWrapperAccount has key {
        signer_cap: SignerCapability
    }

    public fun initialize(satay: &signer) {
        assert!(signer::address_of(satay) == @satay, ERR_NOT_SATAY);

        let (account, signer_cap) = account::create_resource_account(
            satay,
            b"aptos_wrapper"
        );

        move_to(satay, AptosWrapperAccount { signer_cap });

        let (
            burn_cap,
            freeze_cap,
            mint_cap
        ) = coin::initialize<WrappedAptos>(
            satay,
            string::utf8(b"Wrapped Aptos"),
            string::utf8(b"wAPT"),
            8,
            false
        );

        move_to(&account, WrappedAptosCaps {
            mint_cap,
            burn_cap,
            freeze_cap
        });

        coin::register<AptosCoin>(&account);
    }

    public fun apply_position(
        aptos_coins: Coin<AptosCoin>
    ): Coin<WrappedAptos> acquires AptosWrapperAccount, WrappedAptosCaps {
        let aptos_wrapper_account = borrow_global<AptosWrapperAccount>(@satay);
        let aptos_wrapper_account_address = account::get_signer_capability_address(
            &aptos_wrapper_account.signer_cap
        );
        let aptos_wrapper_caps = borrow_global<WrappedAptosCaps>(aptos_wrapper_account_address);

        let aptos_value = coin::value(&aptos_coins);
        coin::deposit(
            aptos_wrapper_account_address,
            aptos_coins
        );
        coin::mint(aptos_value, &aptos_wrapper_caps.mint_cap)
    }

    public fun liquidate_position(
        wrapped_aptos_coins: Coin<WrappedAptos>
    ): Coin<AptosCoin> acquires AptosWrapperAccount, WrappedAptosCaps {
        let aptos_wrapper_account = borrow_global<AptosWrapperAccount>(@satay);
        let aptos_wrapper_account_signer = account::create_signer_with_capability(
            &aptos_wrapper_account.signer_cap
        );
        let aptos_wrapper_account_address = signer::address_of(&aptos_wrapper_account_signer);
        let aptos_wrapper_caps = borrow_global<WrappedAptosCaps>(aptos_wrapper_account_address);

        let wrapped_aptos_value = coin::value(&wrapped_aptos_coins);
        coin::burn(
            wrapped_aptos_coins,
            &aptos_wrapper_caps.burn_cap
        );
        coin::withdraw(
            &aptos_wrapper_account_signer,
            wrapped_aptos_value
        )
    }

    public fun reinvest_returns(): Coin<WrappedAptos> {
        coin::zero<WrappedAptos>()
    }

    public fun get_aptos_amount_for_wrapped_amount(wrapped_amount: u64): u64 {
        wrapped_amount
    }

    public fun get_wrapped_amount_for_aptos_amount(aptos_amount: u64): u64 {
        aptos_amount
    }
}
