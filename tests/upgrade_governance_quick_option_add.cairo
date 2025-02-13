// tests/test_arbitrary_proposal_upgrade_and_add_treasury.cairo

use amm_governance::proposals::{IProposalsDispatcherTrait, IProposalsDispatcher};
use amm_governance::types::Option_;
use konoha::types::{CustomProposalConfig, FullPropDetails};

use konoha::upgrades::IUpgradesDispatcher;
use konoha::upgrades::IUpgradesDispatcherTrait;

use snforge_std::{
    CheatSpan, CheatTarget, ContractClassTrait, ContractClass, prank, start_warp, declare
};
use starknet::{ContractAddress, get_block_timestamp, ClassHash};

// Helper function to get addresses of voters (you'll need to update this with real addresses)
fn get_voter_addresses() -> @Span<felt252> {
    let arr = array![
        0x0011d341c6e841426448ff39aa443a6dbb428914e05ba2259463c18308b86233,
        0x0583a9d956d65628f806386ab5b12dccd74236a3c6b930ded9cf3c54efc722a1,
        0x03d1525605db970fa1724693404f5f64cba8af82ec4aab514e6ebd3dec4838ad,
        0x00d79a15d84f5820310db21f953a0fae92c95e25d93cb983cc0c27fc4c52273c,
        0x06717eaf502baac2b6b2c6ee3ac39b34a52e726a73905ed586e757158270a0af,
    ];
    @arr.span()
}

#[test]
#[fork("MAINNET_PROP168")] // Use your defined MAINNET fork
fn test_arbitrary_proposal_upgrade_and_add_treasury() {
    // 1. Define Governance Contract Address (on Mainnet)
    let gov_addr = 0x001405ab78ab6ec90fba09e6116f373cda53b0ba557789a4578d8c1ec374ba0f
        .try_into()
        .unwrap();
    let props = IProposalsDispatcher { contract_address: gov_addr };

    // 2. Declare the ArbitraryProposalAddOptions contract
    let _new_gov_class = declare("Governance").expect('unable to declare govUGQOA');
    let arbitrary_proposal_class = declare("ArbitraryProposalAddOptions")
        .expect('unable to declare arbpropAO');

    // 3. Submit the Arbitrary Proposal.
    let user1: ContractAddress = 0x0011d341c6e841426448ff39aa443a6dbb428914e05ba2259463c18308b86233
        .try_into()
        .unwrap(); // Team Member 1 - Example Voter

    prank(CheatTarget::One(gov_addr), user1, CheatSpan::TargetCalls(1));

    // Proposal type "6" represents an arbitrary proposal.
    let prop_id = props.submit_proposal(arbitrary_proposal_class.class_hash.into(), 6);

    // 4. Vote on the Proposal
    let mut voter_addresses = *get_voter_addresses();

    // vote yay with all users
    loop {
        match voter_addresses.pop_front() {
            Option::Some(address) => {
                let current_voter: ContractAddress = (*address).try_into().unwrap();
                prank(CheatTarget::One(gov_addr), current_voter, CheatSpan::TargetCalls(1));
                props.vote(prop_id, 1);
            },
            Option::None(()) => { break (); }
        }
    };

    // 5. Warp Time (Simulate Time Passing)
    let curr_timestamp = get_block_timestamp();
    let proposal_wait_time = consteval_int!(60 * 60 * 24 * 7) + 420; // 7 days + buffer
    let warped_timestamp = curr_timestamp + proposal_wait_time;
    start_warp(CheatTarget::One(gov_addr), warped_timestamp);

    // Check the proposal status to make sure it is passed
    assert(props.get_proposal_status(prop_id) == 1, 'arbitrary proposal not passed');

    println!("prop passed!");
    // 6. Execute the Proposal (Apply Passed Proposal)
    let upgrades = IUpgradesDispatcher { contract_address: gov_addr };
    upgrades.apply_passed_proposal(prop_id);

    // Some checks
    let _prop_zero: FullPropDetails = props.get_proposal_details(0);

    let added_config: CustomProposalConfig = props.get_custom_proposal_type(3);
    let expected_target: felt252 =
        0x004e19b87b7777e6e7032ca325794cd793a4d6e9591a8c4e60e0d1b27e4da3d7;
    assert(added_config.target == expected_target, 'wrong custom prop target');
    assert(added_config.selector == selector!("add_options"), 'wrong custom prop selector');
    assert(added_config.library_call == true, 'wrong custom prop libcall');
    assert(added_config.proposal_voting_time == 259200, 'wrong custom prop voting time');

    // 7.c Check if governance works correctly, if it's healthy

    assert(check_if_healthy(gov_addr), 'Governance is not healthy');
}


fn check_if_healthy(gov_contract_addr: ContractAddress) -> bool {
    let dispatcher = IProposalsDispatcher { contract_address: gov_contract_addr };

    // 1. Submit a new airdrop proposal (type 3).  Use a dummy merkle root.
    let dummy_merkle_root: felt252 = 0x12345;
    let user1: ContractAddress = 0x0011d341c6e841426448ff39aa443a6dbb428914e05ba2259463c18308b86233
        .try_into()
        .unwrap(); // Team Member 1 - Example Voter

    prank(CheatTarget::One(gov_contract_addr), user1, CheatSpan::TargetCalls(1));

    let new_prop_id = dispatcher.submit_proposal(dummy_merkle_root, 3);

    // 2. Vote on the new proposal.
    let mut voter_addresses = *get_voter_addresses();
    loop {
        match voter_addresses.pop_front() {
            Option::Some(address) => {
                let current_voter: ContractAddress = (*address).try_into().unwrap();
                prank(
                    CheatTarget::One(gov_contract_addr), current_voter, CheatSpan::TargetCalls(1)
                );
                dispatcher.vote(new_prop_id, 1); // Vote "yes" (1).
            },
            Option::None(()) => { break (); }
        }
    };

    // 3. Warp time to after the voting period.
    let curr_timestamp = get_block_timestamp();
    let proposal_wait_time = consteval_int!(3 * 60 * 60 * 24 * 7)
        + 420; // Or use a shorter time if needed.
    let warped_timestamp = curr_timestamp + proposal_wait_time;
    start_warp(CheatTarget::One(gov_contract_addr), warped_timestamp);

    // 4. Check the new proposal's status.
    dispatcher.get_proposal_status(new_prop_id) == 1 // Assert that it passed (status 1).
}
