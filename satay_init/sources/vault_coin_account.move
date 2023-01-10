/// The module used to create a resource account for Satay to deploy Vault Coins under
module satay::vault_coin_account {
    use std::signer;

    use aptos_framework::account::{Self, SignerCapability};

    /// When called from wrong account.
    const ERR_NOT_ENOUGH_PERMISSIONS: u64 = 1;

    /// Temporary storage for user resource account signer capability.
    struct CapabilityStorage has key { signer_cap: SignerCapability }

    /// Creates new resource account for Liquidswap, puts signer capability into storage
    /// and deploys LP coin type.
    /// Can be executed only from Liquidswap account.
    public entry fun initialize_satay_account(
        satay: &signer,
        vault_coin_metadata_serialized: vector<u8>,
        vault_coin_code: vector<u8>
    ) {
        assert!(signer::address_of(satay) == @satay, ERR_NOT_ENOUGH_PERMISSIONS);

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

    /// Destroys temporary storage for resource account signer capability and returns signer capability.
    /// It needs for initialization of liquidswap.
    public fun retrieve_signer_cap(satay: &signer): SignerCapability acquires CapabilityStorage {
        assert!(signer::address_of(satay) == @satay, ERR_NOT_ENOUGH_PERMISSIONS);
        let CapabilityStorage {
            signer_cap
        } = move_from<CapabilityStorage>(signer::address_of(satay));
        signer_cap
    }
}