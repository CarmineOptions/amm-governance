use starknet::contract_address::{ContractAddress};

#[starknet::interface]
trait IArbitraryProposalAddOptions<TContractState> {
    fn execute_arbitrary_proposal(ref self: TContractState);
}

#[starknet::contract]
pub mod ArbitraryProposalAddOptions {
    use amm_governance::proposals::proposals as proposals_component;
    use amm_governance::proposals::proposals::InternalTrait;
    use konoha::contract::IGovernanceDispatcher;
    use konoha::contract::IGovernanceDispatcherTrait;
    use konoha::types::{CustomProposalConfig};
    use starknet::{ContractAddress, ClassHash, get_contract_address};

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
            let option_deployer_class_hash: felt252 =
                0x004e19b87b7777e6e7032ca325794cd793a4d6e9591a8c4e60e0d1b27e4da3d7;

            let add_options = CustomProposalConfig {
                target: option_deployer_class_hash,
                selector: selector!("add_options"),
                library_call: true
            };

            self.proposals.add_custom_proposal_config(add_options);
        }
    }
}
