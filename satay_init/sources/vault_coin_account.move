/// Initializes resource account to deploy the SatayVaultCoin package
/// Temporarily stores the SignerCapability for the resource account in the satay account
/// Signer cap is later extracted by the Satay package
module satay::vault_coin_account {
    use std::signer;

    use aptos_framework::account::{Self, SignerCapability};

    /// when the protected functions are called by an invalid signer
    const ERR_NOT_ENOUGH_PERMISSIONS: u64 = 1;

    /// temporary storage for deployer resource account SignerCapability
    /// @field signer_cap - SignerCapability for VaultCoin resource account
    struct CapabilityStorage has key { signer_cap: SignerCapability }

    /// creates a resource account for Satay, deploys the SatayVaultCoin package, and stores the SignerCapability
    /// @param satay - the transaction signer; must be the deployer account
    /// @param vault_coin_metadata_serialized - serialized metadata for the VaultCoin package
    /// @param vault_coin_code - compiled code for the VaultCoin package
    public entry fun initialize_satay_account(
        satay: &signer,
        vault_coin_metadata_serialized: vector<u8>,
        vault_coin_code: vector<u8>
    ) {
        assert!(signer::address_of(satay) == @satay, ERR_NOT_ENOUGH_PERMISSIONS);

        // this function will abort if initialize_satay_account is called twice
        let (
            satay_acc,
            signer_cap
        ) = account::create_resource_account(satay, b"satay_account_seed");

        aptos_framework::code::publish_package_txn(
            &satay_acc,
            vault_coin_metadata_serialized,
            vector[vault_coin_code]
        );

        move_to(satay, CapabilityStorage { signer_cap });
    }

    /// destroys temporary storage for resource account SignerCapability and returns SignerCapability; called by satay::initialize
    /// @param satay - the transaction signer; must be the deployer account
    public fun retrieve_signer_cap(satay: &signer): SignerCapability
    acquires CapabilityStorage {
        assert!(signer::address_of(satay) == @satay, ERR_NOT_ENOUGH_PERMISSIONS);
        let CapabilityStorage {
            signer_cap
        } = move_from<CapabilityStorage>(signer::address_of(satay));
        signer_cap
    }
}