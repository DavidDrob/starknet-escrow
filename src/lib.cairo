#[starknet::interface]
pub trait IDestinationEscrow<TContractState> {
    fn withdraw(ref self: TContractState, secret: felt252);
}

// SPDX-License-Identifier: MIT
#[starknet::contract]
mod DestinationEscrow {
    use core::hash::{HashStateExTrait, HashStateTrait};
    use core::poseidon::PoseidonTrait;
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address, get_contract_address};

    #[storage]
    struct Storage {
        hashlock: felt252,
        taker: ContractAddress,
        token: IERC20Dispatcher,
        // amount: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        taker: ContractAddress,
        secret_hash: felt252,
        token: ContractAddress,
        amount: u256,
    ) {
        let zero_address: Option<ContractAddress> = 0.try_into();
        assert(token != zero_address.unwrap(), 'Token is the zero address');
        let token_dispatcher = IERC20Dispatcher { contract_address: taker };
        self.taker.write(taker);
        self.hashlock.write(secret_hash);
        self.token.write(token_dispatcher);
        // self.amount.write(amount);

        //let caller = get_caller_address();
    //let this = get_contract_address();
    //token_dispatcher.transfer_from(caller, this, amount);
    }

    #[abi(embed_v0)]
    impl DestinationEscrowImpl of super::IDestinationEscrow<ContractState> {
        fn withdraw(ref self: ContractState, secret: felt252) {
            let caller = get_caller_address();
            assert(caller == self.taker.read(), 'Caller is not taker');

            let secret_hashed = PoseidonTrait::new().update_with(secret).finalize();
            assert(secret_hashed == self.hashlock.read(), 'Incorrect secret');
        }
    }
}


pub mod test_token;
