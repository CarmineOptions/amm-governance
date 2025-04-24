use starknet::ClassHash;

use starknet::ContractAddress;

#[starknet::interface]
trait IArbitraryProposalRemusUpgrade<TContractState> {
    fn execute_arbitrary_proposal(ref self: TContractState);
}

pub const REMUS_ADDRESS: felt252 =
    0x067e7555f9ff00f5c4e9b353ad1f400e2274964ea0942483fae97363fd5d7958;

// ClassHash of this proposal: 0x05f3c6cd06f9390ed46e4ea2a350039297d8b809a120ddcf03098446081e8d26
#[starknet::contract]
pub mod ArbitraryProposalAdjustRemusFees {
    use amm_governance::traits::{IRemusDEXDispatcher, IRemusDEXDispatcherTrait};
    use amm_governance::types::{MarketConfig, Fees};

    use core::integer::BoundedInt;
    use core::traits::{Into, TryInto};

    use starknet::ClassHash;
    use starknet::ContractAddress;
    use starknet::SyscallResult;
    use starknet::SyscallResultTrait;
    use starknet::syscalls::deploy_syscall;

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
            let mut dex = IRemusDEXDispatcher {
                contract_address: super::REMUS_ADDRESS.try_into().unwrap()
            };

            // Fetch all configs
            let mut configs = dex.get_all_market_configs();

            while let Option::Some((market_id, market_config)) = configs.pop_front() {
                let new_fees = Fees {
                    taker_fee_bps: 0,
                    maker_fee_bps: 0,
                };
                let new_market_config = MarketConfig {
                    fees: new_fees,
                    ..market_config
                };

                dex.update_market_config(
                    market_id,
                    new_market_config
                );
            }
        }
    }
}

