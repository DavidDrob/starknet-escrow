use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
use starknet::ContractAddress;

#[starknet::contract]
pub mod TestToken {
    use core::num::traits::zero::Zero;
    use openzeppelin_token::erc20::interface::IERC20;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use starknet::{ContractAddress, get_caller_address};

    #[storage]
    struct Storage {
        balances: Map<ContractAddress, u256>,
        allowances: Map<(ContractAddress, ContractAddress), u256>,
    }

    #[derive(starknet::Event, PartialEq, Debug, Drop)]
    pub(crate) struct Transfer {
        pub(crate) from: ContractAddress,
        pub(crate) to: ContractAddress,
        pub(crate) value: u256,
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        Transfer: Transfer,
    }

    #[constructor]
    fn constructor(ref self: ContractState, recipient: ContractAddress, amount: u256) {
        self.balances.write(recipient, amount);
        self.emit(Transfer { from: Zero::zero(), to: recipient, value: amount })
    }

    #[abi(embed_v0)]
    impl IERC20Impl of IERC20<ContractState> {
        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account).into()
        }

        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress,
        ) -> u256 {
            self.allowances.read((owner, spender)).into()
        }

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            let balance = self.balances.read(get_caller_address());
            assert(balance >= amount, 'INSUFFICIENT_TRANSFER_BALANCE');
            self.balances.write(recipient, self.balances.read(recipient) + amount);
            self.balances.write(get_caller_address(), balance - amount);
            self.emit(Transfer { from: get_caller_address(), to: recipient, value: amount });
            true
        }

        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) -> bool {
            let allowance = self.allowances.read((sender, get_caller_address()));
            assert(allowance >= amount, 'INSUFFICIENT_ALLOWANCE');
            let balance = self.balances.read(sender);
            assert(balance >= amount, 'INSUFFICIENT_TF_BALANCE');
            self.balances.write(recipient, self.balances.read(recipient) + amount);
            self.balances.write(sender, balance - amount);
            self.allowances.write((sender, get_caller_address()), allowance - amount);
            self.emit(Transfer { from: sender, to: recipient, value: amount });
            true
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            self.allowances.write((get_caller_address(), spender), amount.try_into().unwrap());
            true
        }

        fn total_supply(self: @ContractState) -> u256 {
            0
        }
    }
}

pub fn deploy(owner: ContractAddress, amount: u256) -> ContractAddress {
    let contract = declare("TestToken").unwrap().contract_class();

    let mut constructor_calldata: Array<felt252> = ArrayTrait::new();
    Serde::serialize(@(owner, amount), ref constructor_calldata);

    let (address, _) = contract.deploy(@constructor_calldata).unwrap();
    address
}
