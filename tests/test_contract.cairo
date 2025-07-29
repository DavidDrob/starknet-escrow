use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, Token, TokenImpl, declare, set_balance,
    start_cheat_block_number, start_cheat_caller_address, stop_cheat_block_number,
    stop_cheat_caller_address,
};
use starknet::{ContractAddress, get_block_info, get_contract_address};
use starknet_escrow::test_token::{TestToken, deploy as deploy_token};
use starknet_escrow::{
    IDestinationEscrowDispatcher, IDestinationEscrowDispatcherTrait,
    IDestinationEscrowSafeDispatcher, IDestinationEscrowSafeDispatcherTrait,
};

const STRK_ADDRESS: ContractAddress =
    0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d
    .try_into()
    .unwrap();
const SAFETY_DEPOSIT: u256 = 1000000000000000000; // 1e18

#[derive(Drop, Serde, starknet::Store)]
struct Timelocks {
    withdrawal: u64,
    publicWithdrawal: u64,
    cancellation: u64,
}

fn deploy_destination_escrow() -> (ContractAddress, ContractAddress) {
    let contract = declare("DestinationEscrow").unwrap().contract_class();
    let amount: u256 = 100000000000000000000; // 100e18

    let test_token = deploy_token(get_contract_address(), amount.into());
    let test_token_dispatcher = IERC20Dispatcher { contract_address: test_token };
    let taker: ContractAddress = 'taker'.try_into().unwrap();
    let secret: felt252 = 'secret';
    let secret_hash = PoseidonTrait::new()
        .update_with(secret)
        .finalize(); // 26439584174109800712083033069066874202485490695772359629503443471327618552

    let now = get_block_info().block_number;
    let timelocks = Timelocks {
        withdrawal: now + 86_400,
        publicWithdrawal: now + 86_400 * 2,
        cancellation: now + 86_400 * 3,
    };

    //let test_token_dispatcher = IERC20Dispatcher { contract_address: test_token };
    //test_token_dispatcher.approve();

    let mut constructor_calldata: Array<felt252> = ArrayTrait::new();
    Serde::serialize(
        @(taker, secret_hash, test_token, amount, timelocks), ref constructor_calldata,
    );

    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();

    // TODO: do the transfer in constructor
    test_token_dispatcher.transfer(contract_address, amount);

    set_balance(get_contract_address(), SAFETY_DEPOSIT, Token::STRK);
    // transfer safety deposit
    // TODO: do the transfer in constructor
    let eth_token_dispatcher = IERC20Dispatcher { contract_address: STRK_ADDRESS };
    eth_token_dispatcher.transfer(contract_address, SAFETY_DEPOSIT);

    (contract_address, test_token)
}

#[test]
#[feature("safe_dispatcher")]
fn test_withdraw() {
    let (contract_address, test_token_address) = deploy_destination_escrow();
    let taker: ContractAddress = 'taker'.try_into().unwrap();

    let safe_dispatcher = IDestinationEscrowSafeDispatcher { contract_address };
    let secret: felt252 = 'secret';

    match safe_dispatcher.withdraw(secret) {
        Result::Ok(_) => core::panic_with_felt252('Should have panicked'),
        Result::Err(panic_data) => {
            assert(*panic_data.at(0) == 'Invalid time', *panic_data.at(0));
        },
    }

    let now = get_block_info().block_number;
    start_cheat_block_number(contract_address, now + 86_400 + 1);
    // correct secret, wrong caller
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

    let test_token_dispatcher = IERC20Dispatcher { contract_address: test_token_address };
    let balance_before = test_token_dispatcher.balance_of(taker);

    // correct secret, correct caller
    safe_dispatcher.withdraw(secret).unwrap(); // unwrap works => didnt panic
    stop_cheat_caller_address(safe_dispatcher.contract_address);
    stop_cheat_block_number(contract_address);

    let balance_after = test_token_dispatcher.balance_of(taker);
    assert(balance_after - balance_before == 100000000000000000000, 'Withdrawal went wrong');
}

#[test]
#[feature("safe_dispatcher")]
fn test_cancel() {
    let (contract_address, test_token_address) = deploy_destination_escrow();
    let taker: ContractAddress = 'taker'.try_into().unwrap();

    let safe_dispatcher = IDestinationEscrowSafeDispatcher { contract_address };

    let now = get_block_info().block_number;
    start_cheat_block_number(contract_address, now + 86_400 + 1);
    match safe_dispatcher.cancel() {
        Result::Ok(_) => core::panic_with_felt252('Should have panicked'),
        Result::Err(panic_data) => {
            assert(*panic_data.at(0) == 'Invalid time', *panic_data.at(0));
        },
    }

    let test_token_dispatcher = IERC20Dispatcher { contract_address: test_token_address };
    let balance_before = test_token_dispatcher.balance_of(taker);

    stop_cheat_block_number(contract_address);

    start_cheat_caller_address(safe_dispatcher.contract_address, taker);
    start_cheat_block_number(contract_address, now + (86_400 * 3) + 1);

    safe_dispatcher.cancel().unwrap(); // unwrap works => didnt panic
    stop_cheat_caller_address(safe_dispatcher.contract_address);
    stop_cheat_block_number(contract_address);

    let balance_after = test_token_dispatcher.balance_of(taker);
    assert(balance_after - balance_before == 100000000000000000000, 'Cancellation went wrong');
}

#[test]
#[feature("safe_dispatcher")]
fn test_cant_cancel_after_withdrawal() {
    let (contract_address, test_token_address) = deploy_destination_escrow();
    let taker: ContractAddress = 'taker'.try_into().unwrap();
    let secret: felt252 = 'secret';

    let safe_dispatcher = IDestinationEscrowSafeDispatcher { contract_address };

    let now = get_block_info().block_number;
    start_cheat_caller_address(safe_dispatcher.contract_address, taker);
    start_cheat_block_number(contract_address, now + 86_400 + 1);
    safe_dispatcher.withdraw(secret).unwrap(); // unwrap works => didnt panic

    stop_cheat_block_number(contract_address);
    start_cheat_block_number(contract_address, now + (86_400 * 3) + 1);

    match safe_dispatcher.cancel() {
        Result::Ok(_) => core::panic_with_felt252('Should have panicked'),
        Result::Err(panic_data) => {
            assert(*panic_data.at(0) == 'Withdraw already happend', *panic_data.at(0));
        },
    }

    stop_cheat_block_number(contract_address);
    stop_cheat_caller_address(contract_address);
}
