// This proposal, designed to be library called:

// 1. upgrades the contract to new class hash
// 2. add custom proposals for treasury ops
// 3. add custom proposal to add options but in 3 days

use starknet::contract_address::{ContractAddress};

#[starknet::interface]
trait IArbitraryProposalAddOptions<TContractState> {
    fn execute_arbitrary_proposal(ref self: TContractState);
}

#[starknet::contract]
pub mod ArbitraryProposalAddOptions {
    use amm_governance::proposals::proposals as proposals_component;
    use amm_governance::proposals::proposals::InternalTrait;
    use amm_governance::proposals::{IProposalsDispatcher, IProposalsDispatcherTrait};
    use konoha::contract::IGovernanceDispatcher;
    use konoha::contract::IGovernanceDispatcherTrait;
    use konoha::types::{CustomProposalConfig};
    use starknet::{ContractAddress, ClassHash, get_contract_address, syscalls};

    component!(path: proposals_component, storage: proposals, event: ProposalsEvent);

    #[storage]
    struct Storage {
        #[substorage(v0)]
        proposals: proposals_component::Storage,
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        ProposalsEvent: proposals_component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {}

    #[abi(embed_v0)]
    impl ArbitraryProposalAddOptions of super::IArbitraryProposalAddOptions<ContractState> {
        fn execute_arbitrary_proposal(ref self: ContractState) {
            let gov_addr: ContractAddress =
                0x001405ab78ab6ec90fba09e6116f373cda53b0ba557789a4578d8c1ec374ba0f
                .try_into()
                .unwrap();
            // upgrade governance
            let new_impl_hash = 0x0464940feceb3ed195d1642c6596c726022b9bf521b0d7ae08b8cebf844b494b;
            let impl_hash_classhash: ClassHash = new_impl_hash.try_into().unwrap();
            let res = syscalls::replace_class_syscall(impl_hash_classhash);
            res.expect('upgrade failed');

            let option_deployer_class_hash: felt252 =
                0x004e19b87b7777e6e7032ca325794cd793a4d6e9591a8c4e60e0d1b27e4da3d7;

            let props = IProposalsDispatcher { contract_address: gov_addr };

            let add_options = CustomProposalConfig {
                target: option_deployer_class_hash,
                selector: selector!("add_options"),
                library_call: true,
                proposal_voting_time: 259200 // 3 days
            };

            props.add_custom_proposal_config(add_options);
        }
    }
}
