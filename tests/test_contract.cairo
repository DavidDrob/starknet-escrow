use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;
use starknet_escrow::{
    IDestinationEscrowDispatcher, IDestinationEscrowDispatcherTrait,
    IDestinationEscrowSafeDispatcher, IDestinationEscrowSafeDispatcherTrait,
};

fn deploy_destination_escrow() -> ContractAddress {
    let contract = declare("DestinationEscrow").unwrap().contract_class();

    let taker: ContractAddress = 'taker'.try_into().unwrap();
    let secret_hash: felt252 = 111;
    let constructor_calldata = array![taker.into(), secret_hash.into()];

    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();

    contract_address
}

#[test]
#[feature("safe_dispatcher")]
fn test_withdraw() {
    let contract_address = deploy_destination_escrow();
    let taker: ContractAddress = 'taker'.try_into().unwrap();

    let safe_dispatcher = IDestinationEscrowSafeDispatcher { contract_address };

    let secret: felt252 = 1234;
    match safe_dispatcher.withdraw(secret) {
        Result::Ok(_) => core::panic_with_felt252('Should have panicked'),
        Result::Err(panic_data) => {
            assert(*panic_data.at(0) == 'Caller is not taker', *panic_data.at(0));
        },
    }

    start_cheat_caller_address(safe_dispatcher.contract_address, taker);
    safe_dispatcher.withdraw(secret).unwrap(); // unwrap works => didnt panic
}
