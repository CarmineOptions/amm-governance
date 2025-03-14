
use starknet::ClassHash;

use starknet::ContractAddress;

#[starknet::interface]
trait IArbitraryProposalRemusUpgrade<TContractState> {
    fn execute_arbitrary_proposal(ref self: TContractState);
}

pub const REMUS_ADDRESS: felt252 = 0x067e7555f9ff00f5c4e9b353ad1f400e2274964ea0942483fae97363fd5d7958;
pub const NEW_REMUS_HASH: felt252 = 0x01f8e52a4e6489c9daae16cf8f9764e13476e6ff17064f075248412ba64259fd;

// ClassHash of this proposal: 0x026098805ed363333c12189031a9955fe9bdc9e4ad68218b4ee5e8927ce14650
#[starknet::contract]
pub mod ArbitraryProposalRemusUpgrade {

    use core::integer::BoundedInt;
    use core::traits::{Into, TryInto};

    use starknet::ClassHash;
    use starknet::ContractAddress;
    use starknet::SyscallResult;
    use starknet::SyscallResultTrait;
    use starknet::syscalls::deploy_syscall;

    use amm_governance::traits::{IRemusDEXDispatcher, IRemusDEXDispatcherTrait};

    #[storage]
    struct Storage {}

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {}

    #[constructor]
    fn constructor(ref self: ContractState) {}


    #[abi(embed_v0)]
    impl ArbitraryProposalRemusUpgrade of super::IArbitraryProposalRemusUpgrade<ContractState> {
        fn execute_arbitrary_proposal(ref self: ContractState) {

            // Create dex dispatcher
            let mut dex = IRemusDEXDispatcher { contract_address: super::REMUS_ADDRESS.try_into().unwrap() };

            // Upgrade Remus to new class hash that allows for permissionles market addition
            dex.upgrade(super::NEW_REMUS_HASH.try_into().unwrap()); 
        }
    }
}


