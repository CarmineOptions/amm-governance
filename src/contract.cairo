use starknet::ContractAddress;

#[starknet::interface]
pub trait IMigrate<TContractState> {
    fn add_custom_proposals(ref self: TContractState);
}

#[starknet::interface]
pub trait ICarmineGovernance<TContractState> {
    fn get_amm_address(self: @TContractState) -> ContractAddress;
}

#[starknet::contract]
pub mod Governance {
    use amm_governance::proposals::proposals as proposals_component;
    use amm_governance::proposals::proposals::InternalTrait;
    use amm_governance::staking::staking as staking_component;
    use amm_governance::staking::{IStakingDispatcher, IStakingDispatcherTrait};
    use amm_governance::upgrades::upgrades as upgrades_component;
    use konoha::airdrop::airdrop as airdrop_component;
    use konoha::types::{BlockNumber, VoteStatus, ContractType, PropDetails, CustomProposalConfig};

    use starknet::{ContractAddress, get_contract_address};


    component!(path: airdrop_component, storage: airdrop, event: AirdropEvent);
    component!(path: proposals_component, storage: proposals, event: ProposalsEvent);
    component!(path: upgrades_component, storage: upgrades, event: UpgradesEvent);
    component!(path: staking_component, storage: staking, event: StakingEvent);

    #[abi(embed_v0)]
    impl Airdrop = airdrop_component::AirdropImpl<ContractState>;

    #[abi(embed_v0)]
    impl Proposals = proposals_component::ProposalsImpl<ContractState>;

    #[abi(embed_v0)]
    impl Upgrades = upgrades_component::UpgradesImpl<ContractState>;

    #[abi(embed_v0)]
    impl Staking = staking_component::StakingImpl<ContractState>;

    #[storage]
    struct Storage {
        proposal_initializer_run: LegacyMap::<u64, bool>,
        governance_token_address: ContractAddress,
        amm_address: ContractAddress,
        #[substorage(v0)]
        proposals: proposals_component::Storage,
        #[substorage(v0)]
        airdrop: airdrop_component::Storage,
        #[substorage(v0)]
        upgrades: upgrades_component::Storage,
        #[substorage(v0)]
        staking: staking_component::Storage,
        migration_performed: bool
    }


    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        AirdropEvent: airdrop_component::Event,
        ProposalsEvent: proposals_component::Event,
        UpgradesEvent: upgrades_component::Event,
        StakingEvent: staking_component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, govtoken_address: ContractAddress) {
        // This is not used in production on mainnet, because the governance token is already deployed (and distributed).
        self.governance_token_address.write(govtoken_address);
    }

    #[abi(embed_v0)]
    impl Governance of konoha::contract::IGovernance<ContractState> {
        fn get_governance_token_address(self: @ContractState) -> ContractAddress {
            self.governance_token_address.read()
        }
    }

    #[abi(embed_v0)]
    impl CarmineGovernance of super::ICarmineGovernance<ContractState> {
        fn get_amm_address(self: @ContractState) -> ContractAddress {
            self.amm_address.read()
        }
    }

    const ONE_MONTH: u64 = 2629743; // 30.44 days
    const ONE_YEAR: u64 = 31536000; // 365 days

    #[abi(embed_v0)]
    impl Migrate of super::IMigrate<ContractState> {
        fn add_custom_proposals(ref self: ContractState) {
            assert(!self.migration_performed.read(), 'migration already done');
            let upgrade_amm = CustomProposalConfig {
                target: self.amm_address.read().into(),
                selector: selector!("upgrade"),
                library_call: false
            }; // TODO test
            let upgrade_govtoken = CustomProposalConfig {
                target: self.governance_token_address.read().into(),
                selector: selector!("upgrade"),
                library_call: false
            };
            self.proposals.add_custom_proposal_config(upgrade_amm);
            self.proposals.add_custom_proposal_config(upgrade_govtoken);

            self.migration_performed.write(true);

            let staking = IStakingDispatcher { contract_address: get_contract_address() };
            let THREE_MONTHS = ONE_MONTH * 3;
            let SIX_MONTHS = ONE_MONTH * 6;
            staking.set_curve_point(ONE_MONTH, 100); // 1 KONOHA = 1 veKONOHA if staked for 1 month
            staking.set_curve_point(THREE_MONTHS, 120);
            staking.set_curve_point(SIX_MONTHS, 160);
            staking.set_curve_point(ONE_YEAR, 250);
        }
    }
}
