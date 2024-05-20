use core::num::traits::Zero;
use konoha::contract::IGovernanceDispatcher;
use konoha::contract::IGovernanceDispatcherTrait;
use konoha::proposals::IProposalsDispatcher;
use konoha::proposals::IProposalsDispatcherTrait;
use konoha::upgrades::IUpgradesDispatcher;
use konoha::upgrades::IUpgradesDispatcherTrait;
use amm_governance::contract::{
    IMigrateDispatcher, IMigrateDispatcherTrait, ICarmineGovernanceDispatcher,
    ICarmineGovernanceDispatcherTrait
};
use snforge_std::{start_prank, CheatTarget, start_warp};
use starknet::{ClassHash, ContractAddress, get_block_timestamp};

pub(crate) fn vote_on_proposal(gov_contract_addr: ContractAddress, prop_id: u32) {
    let dispatcher = IProposalsDispatcher { contract_address: gov_contract_addr };
    let mut top_carm_holders = ArrayTrait::new();
    let marek_address: ContractAddress =
        0x0011d341c6e841426448ff39aa443a6dbb428914e05ba2259463c18308b86233
        .try_into()
        .unwrap();
    top_carm_holders.append(marek_address);
    let scaling_address: ContractAddress =
        0x052df7acdfd3174241fa6bd5e1b7192cd133f8fc30a2a6ed99b0ddbfb5b22dcd
        .try_into()
        .unwrap();
    top_carm_holders.append(scaling_address);
    let ondrej_address: ContractAddress =
        0x0583a9d956d65628f806386ab5b12dccd74236a3c6b930ded9cf3c54efc722a1
        .try_into()
        .unwrap();
    top_carm_holders.append(ondrej_address);
    let carlote_address: ContractAddress =
        0x021b2b25dd73bc60b0549683653081f8963562cbe5cba2d123ec0cbcbf0913e4
        .try_into()
        .unwrap();
    top_carm_holders.append(carlote_address);
    let fifth_address: ContractAddress =
        0x02af7135154dc27d9311b79c57ccc7b3a6ed74efd0c2b81116e8eb49dbf6aaf8
        .try_into()
        .unwrap();
    top_carm_holders.append(fifth_address);
    let sixth_address: ContractAddress =
        0x07824efd915baa421d93909bd7f24e36c022b5cfbc5af6687328848a6490ada7
        .try_into()
        .unwrap();
    top_carm_holders.append(sixth_address);
    let madman_address: ContractAddress =
        0x06717eaf502baac2b6b2c6ee3ac39b34a52e726a73905ed586e757158270a0af
        .try_into()
        .unwrap();
    top_carm_holders.append(madman_address);
    let eighth_address: ContractAddress =
        0x03d1525605db970fa1724693404f5f64cba8af82ec4aab514e6ebd3dec4838ad
        .try_into()
        .unwrap();
    top_carm_holders.append(eighth_address);

    loop {
        match top_carm_holders.pop_front() {
            Option::Some(holder) => {
                start_prank(CheatTarget::One(gov_contract_addr), holder);
                dispatcher.vote(prop_id.into(), 1);
            },
            Option::None(()) => { break (); },
        }
    };
    let curr_timestamp = get_block_timestamp();
    let warped_timestamp = curr_timestamp + consteval_int!(60 * 60 * 24 * 7) + 420;
    start_warp(CheatTarget::One(gov_contract_addr), warped_timestamp);
    assert(dispatcher.get_proposal_status(prop_id.into()) == 1, 'proposal not passed!');
}

#[starknet::interface]
pub(crate) trait IERC20<TContractState> {
    fn name(self: @TContractState) -> felt252;
    fn symbol(self: @TContractState) -> felt252;
    fn decimals(self: @TContractState) -> u8;
    fn totalSupply(self: @TContractState) -> u256;
    fn balanceOf(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transferFrom(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
}
