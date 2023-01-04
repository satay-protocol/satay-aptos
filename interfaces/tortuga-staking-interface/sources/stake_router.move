module tortuga::stake_router {
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use tortuga::staked_aptos_coin::StakedAptosCoin;

    public fun stake_coins(aptos: coin::Coin<AptosCoin>): coin::Coin<StakedAptosCoin> {
        coin::destroy_zero(aptos);
        coin::zero<StakedAptosCoin>()
    }
}