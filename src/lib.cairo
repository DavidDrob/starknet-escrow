#[starknet::interface]
pub trait IDestinationEscrow<TContractState> {
    fn withdraw(ref self: TContractState, secret: felt252);
}

// SPDX-License-Identifier: MIT
#[starknet::contract]
mod DestinationEscrow {
    use core::hash::{HashStateExTrait, HashStateTrait};
    use core::poseidon::PoseidonTrait;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address};

    #[storage]
    struct Storage {
        hashlock: felt252,
        taker: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState, taker: ContractAddress, secret_hash: felt252) {
        self.taker.write(taker);
        self.hashlock.write(secret_hash);
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
