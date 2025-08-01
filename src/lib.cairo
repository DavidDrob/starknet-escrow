use starknet::ContractAddress;

#[starknet::interface]
pub trait IDestinationEscrow<TContractState> {
    fn withdraw(ref self: TContractState, secret: felt252);
    fn cancel(ref self: TContractState);
}

const STRK_ADDRESS: ContractAddress =
    0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d
    .try_into()
    .unwrap();
const SAFETY_DEPOSIT: u256 = 1000000000000000000; // 1e18

// SPDX-License-Identifier: MIT
#[starknet::contract]
mod DestinationEscrow {
    use core::hash::{HashStateExTrait, HashStateTrait};
    use core::poseidon::PoseidonTrait;
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_block_info, get_caller_address, get_contract_address};
    use super::{SAFETY_DEPOSIT, STRK_ADDRESS};

    #[derive(Drop, Serde, starknet::Store)]
    struct Timelocks {
        withdrawal: u64,
        publicWithdrawal: u64,
        cancellation: u64,
    }

    #[storage]
    struct Storage {
        hashlock: felt252,
        taker: ContractAddress,
        token: IERC20Dispatcher,
        timelocks: Timelocks,
        amount: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        taker: ContractAddress,
        secret_hash: felt252,
        token: ContractAddress,
        amount: u256,
        timelocks: Timelocks,
    ) {
        let zero_address: Option<ContractAddress> = 0.try_into();
        assert(token != zero_address.unwrap(), 'Token is the zero address');
        let token_dispatcher = IERC20Dispatcher { contract_address: token };
        self.taker.write(taker);
        self.hashlock.write(secret_hash);
        self.token.write(token_dispatcher);
        self.amount.write(amount);
        self.timelocks.write(timelocks);
        // TODO: safety deposit

        //let caller = get_caller_address();
    //let this = get_contract_address();
    //token_dispatcher.transfer_from(caller, this, amount);
    }

    #[abi(embed_v0)]
    impl DestinationEscrowImpl of super::IDestinationEscrow<ContractState> {
        fn withdraw(ref self: ContractState, secret: felt252) {
            assert(is_before(self.timelocks.read().cancellation), 'Invalid time');
            assert(is_after(self.timelocks.read().withdrawal), 'Invalid time');

            let caller = get_caller_address();
            assert(caller == self.taker.read(), 'Caller is not taker');

            let secret_hashed = PoseidonTrait::new().update_with(secret).finalize();
            assert(secret_hashed == self.hashlock.read(), 'Incorrect secret');

            let amount = self.amount.read();
            let token_dispatcher = self.token.read();
            token_dispatcher.transfer(caller, amount);

            let eth_token_dispatcher = IERC20Dispatcher { contract_address: STRK_ADDRESS };
            eth_token_dispatcher.transfer(caller, SAFETY_DEPOSIT);
        }

        fn cancel(ref self: ContractState) {
            assert(is_after(self.timelocks.read().cancellation), 'Invalid time');

            let caller = get_caller_address();
            assert(caller == self.taker.read(), 'Caller is not taker');

            let amount = self.amount.read();
            let token_dispatcher = self.token.read();
            let balance = token_dispatcher.balance_of(get_contract_address());
            assert(balance >= amount, 'Withdraw already happend');
            token_dispatcher.transfer(caller, amount);

            let eth_token_dispatcher = IERC20Dispatcher { contract_address: STRK_ADDRESS };
            eth_token_dispatcher.transfer(caller, SAFETY_DEPOSIT);
        }
    }

    fn is_before(time: u64) -> bool {
        let block_info = get_block_info();
        block_info.block_number < time
    }

    fn is_after(time: u64) -> bool {
        let block_info = get_block_info();
        block_info.block_number > time
    }
}


pub mod test_token;
