use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin_token::erc20::interface::IERC20Dispatcher;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::{ContractAddress, get_contract_address};
use starknet_escrow::test_token::{TestToken, deploy as deploy_token};
use starknet_escrow::{
    IDestinationEscrowDispatcher, IDestinationEscrowDispatcherTrait,
    IDestinationEscrowSafeDispatcher, IDestinationEscrowSafeDispatcherTrait,
};

fn deploy_destination_escrow() -> ContractAddress {
    let contract = declare("DestinationEscrow").unwrap().contract_class();
    let amount: u256 = 100000000000000000000; // 100e18

    let test_token = deploy_token(get_contract_address(), amount.into());
    //let test_token_dispatcher = IERC20Dispatcher { contract_address: test_token };
    let taker: ContractAddress = 'taker'.try_into().unwrap();
    let secret: felt252 = 'secret';
    let secret_hash = PoseidonTrait::new()
        .update_with(secret)
        .finalize(); // 26439584174109800712083033069066874202485490695772359629503443471327618552

    //let test_token_dispatcher = IERC20Dispatcher { contract_address: test_token };
    //test_token_dispatcher.approve();

    let mut constructor_calldata: Array<felt252> = ArrayTrait::new();
    Serde::serialize(@(taker, secret_hash, test_token, amount), ref constructor_calldata);

    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();

    contract_address
}

#[test]
#[feature("safe_dispatcher")]
fn test_withdraw() {
    let contract_address = deploy_destination_escrow();
    let taker: ContractAddress = 'taker'.try_into().unwrap();

    let safe_dispatcher = IDestinationEscrowSafeDispatcher { contract_address };

    // correct secret, wrong caller
    let secret: felt252 = 'secret';
    match safe_dispatcher.withdraw(secret) {
        Result::Ok(_) => core::panic_with_felt252('Should have panicked'),
        Result::Err(panic_data) => {
            assert(*panic_data.at(0) == 'Caller is not taker', *panic_data.at(0));
        },
    }

    // wrong secret, correct caller
    let wrong_secret: felt252 = 'wrong secret';
    start_cheat_caller_address(safe_dispatcher.contract_address, taker);
    match safe_dispatcher.withdraw(wrong_secret) {
        Result::Ok(_) => core::panic_with_felt252('Should have panicked'),
        Result::Err(panic_data) => {
            assert(*panic_data.at(0) == 'Incorrect secret', *panic_data.at(0));
        },
    }

    // correct secret, correct caller
    safe_dispatcher.withdraw(secret).unwrap(); // unwrap works => didnt panic
    stop_cheat_caller_address(safe_dispatcher.contract_address);
}
