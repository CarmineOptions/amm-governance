#[starknet::interface]
trait IUpgrades<TContractState> {
    fn apply_passed_proposal(ref self: TContractState, prop_id: felt252);
}

#[starknet::component]
pub(crate) mod upgrades {
    use amm_governance::proposals::proposals as proposals_component;
    use amm_governance::proposals::proposals::ProposalsImpl;
    use core::array::ArrayTrait;
    use core::option::OptionTrait;
    use core::panic_with_felt252;
    use core::result::ResultTrait;
    use konoha::airdrop::airdrop as airdrop_component;
    use konoha::contract::Governance::ContractState;
    use konoha::contract::Governance;
    use konoha::traits::get_governance_token_address_self;

    use konoha::types::{CustomProposalConfig, PropDetails};
    use starknet::ClassHash;
    use starknet::ContractAddress;
    use starknet::SyscallResult;

    use starknet::SyscallResultTrait;
    use starknet::class_hash;
    use starknet::syscalls;

    #[storage]
    struct Storage {
        proposal_applied: LegacyMap::<felt252, bool>,
        amm_address: ContractAddress
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    pub(crate) enum Event {
        Upgraded: Upgraded
    }

    #[derive(starknet::Event, Drop)]
    struct Upgraded {
        prop_id: u64,
        upgrade_type: u64
    }

    #[embeddable_as(UpgradesImpl)]
    impl Upgrades<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Proposals: proposals_component::HasComponent<TContractState>,
        impl Airdrop: airdrop_component::HasComponent<TContractState>
    > of super::IUpgrades<ComponentState<TContractState>> {
        fn apply_passed_proposal(ref self: ComponentState<TContractState>, prop_id: felt252) {
            let proposals_comp = get_dep_component!(@self, Proposals);
            let status = proposals_comp
                .get_proposal_status(
                    prop_id
                ); // needs use konoha::proposals::proposals::ProposalsImpl;
            assert(status == 1, 'prop not passed');
            let applied = self.proposal_applied.read(prop_id);
            assert(!applied, 'Proposal already applied');

            let prop_details: PropDetails = proposals_comp.proposal_details.read(prop_id);
            let contract_type = prop_details.to_upgrade.try_into().unwrap();

            proposals_component::assert_correct_contract_type(contract_type);

            let impl_hash = prop_details.payload;

            // Apply the upgrade
            match contract_type {
                0 => {
                    panic!("Carmine Options AMM upgrade not supported, use generic proposals");
                },
                1 => {
                    let impl_hash_classhash: ClassHash = impl_hash.try_into().unwrap();
                    let res = syscalls::replace_class_syscall(impl_hash_classhash);
                    res.expect('upgrade failed');
                },
                2 => { panic!("CRM upgrade not supported, use generic proposals"); },
                3 => {
                    let mut airdrop_comp = get_dep_component_mut!(ref self, Airdrop);
                    airdrop_comp.merkle_root.write(impl_hash);
                },
                4 => (),
                5 => {
                    // custom proposal
                    let custom_proposal_type: u32 = impl_hash
                        .try_into()
                        .expect('custom prop type fit in u32');
                    let config: CustomProposalConfig = proposals_comp
                        .custom_proposal_type
                        .read(custom_proposal_type);

                    let prop_id_: u32 = prop_id.try_into().unwrap();
                    let mut calldata_len = proposals_comp
                        .custom_proposal_payload
                        .read((prop_id_, 0));
                    let mut calldata: Array<felt252> = ArrayTrait::new();
                    let mut i: u32 = 1;
                    while (calldata_len != 0) {
                        calldata.append(proposals_comp.custom_proposal_payload.read((prop_id_, i)));
                        i += 1;
                        calldata_len -= 1;
                    };

                    if (config.library_call) {
                        let res = syscalls::library_call_syscall(
                            config.target.try_into().expect('unable to convert>classhash'),
                            config.selector,
                            calldata.span()
                        );
                        res.expect('libcall failed');
                    } else {
                        let res = syscalls::call_contract_syscall(
                            config.target.try_into().expect('unable to convert>addr'),
                            config.selector,
                            calldata.span()
                        );
                        res.expect('contract call failed');
                    }
                },
                6 => {
                    // arbitrary proposal
                    let res = syscalls::library_call_syscall(
                        impl_hash.try_into().expect('unable to convert>classhash'),
                        selector!("execute_arbitrary_proposal"),
                        ArrayTrait::new().span()
                    );
                    res.expect('libcall failed');
                },
                _ => { panic_with_felt252('invalid to_upgrade') }
            };
            self.proposal_applied.write(prop_id, true); // Mark the proposal as applied
            self
                .emit(
                    Upgraded {
                        prop_id: prop_id.try_into().unwrap(),
                        upgrade_type: contract_type.try_into().unwrap()
                    }
                );
        }
    }
}
