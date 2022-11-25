module aries_interface::controller {

    public entry fun register_user(_user: &signer, _seed: vector<u8>) {}

    // to my unerstanding, the _collateral flag is true when borrowing/repaying and false when depositing/withdrawing
    public entry fun deposit<CoinType>(_user: &signer, _account: vector<u8>, _collateral: bool) {}

    public entry fun withdraw<CoinType>(_user: &signer, _account: vector<u8>, _collateral: bool) {}
}
