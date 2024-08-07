use amm_governance::constants::UNLOCK_DATE;

use amm_governance::contract::{
    IMigrateDispatcher, IMigrateDispatcherTrait, ICarmineGovernanceDispatcher,
    ICarmineGovernanceDispatcherTrait
};
use amm_governance::staking::{IStakingDispatcher, IStakingDispatcherTrait};
use amm_governance::vecarm::{IVeCRMDispatcher, IVeCRMDispatcherTrait};
use core::num::traits::Zero;
use konoha::airdrop::{IAirdropDispatcher, IAirdropDispatcherTrait};
use konoha::contract::IGovernanceDispatcher;
use konoha::contract::IGovernanceDispatcherTrait;
use konoha::proposals::IProposalsDispatcher;
use konoha::proposals::IProposalsDispatcherTrait;
use konoha::traits::{IERC20Dispatcher, IERC20DispatcherTrait};
use konoha::treasury::{ITreasuryDispatcher, ITreasuryDispatcherTrait};
use konoha::upgrades::IUpgradesDispatcher;
use konoha::upgrades::IUpgradesDispatcherTrait;
use openzeppelin::upgrades::interface::{IUpgradeableDispatcher, IUpgradeableDispatcherTrait};
use snforge_std::{
    BlockId, declare, ContractClassTrait, ContractClass, start_prank, CheatTarget, prank, CheatSpan,
    roll, start_warp
};
use starknet::{ClassHash, ContractAddress, get_block_timestamp, get_block_number};
use super::utils::vote_on_proposal;

fn check_if_healthy(gov_contract_addr: ContractAddress) -> bool {
    let dispatcher = IProposalsDispatcher { contract_address: gov_contract_addr };
    dispatcher.get_proposal_status(0);
    let prop_details = dispatcher.get_proposal_details(0);
    (prop_details.payload + prop_details.to_upgrade) != 0
}

#[test]
#[fork("MAINNET")]
fn test_unstake_airdrop() {
    let gov_addr: ContractAddress =
        0x001405ab78ab6ec90fba09e6116f373cda53b0ba557789a4578d8c1ec374ba0f
        .try_into()
        .unwrap();
    let vecarm_addr: ContractAddress =
        0x03c0286e9e428a130ae7fbbe911b794e8a829c367dd788e7cfe3efb0367548fa
        .try_into()
        .unwrap();

    //let gov_class: ContractClass = declare("Governance").expect('unable to declare gov');
    //let floating_class: ContractClass = declare("CRMToken").expect('unable to declare CRM');
    //let voting_class: ContractClass = declare("VeCRM").expect('unable to declare voting');

    let mut floating_calldata = ArrayTrait::new();
    floating_calldata.append(10000000000000000000000000); // fixed supply low
    floating_calldata.append(0); // fixed supply high
    floating_calldata.append(gov_addr.into());
    floating_calldata.append(gov_addr.into());
    let floating_addr: ContractAddress =
        0x051c4b1fe3bf6774b87ad0b15ef5d1472759076e42944fff9b9f641ff13e5bbe
        .try_into()
        .unwrap();

    let time_zero = get_block_timestamp();

    let team_member_1: ContractAddress =
        0x0011d341c6e841426448ff39aa443a6dbb428914e05ba2259463c18308b86233
        .try_into()
        .unwrap();
    let team_member_2: ContractAddress =
        0x0583a9d956d65628f806386ab5b12dccd74236a3c6b930ded9cf3c54efc722a1
        .try_into()
        .unwrap();
    let random_user_1: ContractAddress =
        0x052df7acdfd3174241fa6bd5e1b7192cd133f8fc30a2a6ed99b0ddbfb5b22dcd
        .try_into()
        .unwrap();
    let random_user_2: ContractAddress =
        0x21b2b25dd73bc60b0549683653081f8963562cbe5cba2d123ec0cbcbf0913e4
        .try_into()
        .unwrap();
    let random_user_3: ContractAddress =
        0x539577df56aab4269c13ece28baff916ef08c26ba480142a3ce1739d2e848d9
        .try_into()
        .unwrap();

    let props = IProposalsDispatcher { contract_address: gov_addr };
    prank(CheatTarget::One(gov_addr), team_member_1, CheatSpan::TargetCalls(6));

    // Upgrade governance
    let prop_id_gov_upgrade = props
        .submit_proposal(0x04bc8bc7c476c4fca95624809dab1f1aa718edb566184a9d6dfe54f65b32b507, 1);
    props.vote(prop_id_gov_upgrade, 1);

    // Upgrade veCarm token
    let prop_id_vecarm_upgrade = props
        .submit_proposal(0x008e98fd1f76f0d6fca8b03292e1dd6c8a6c5362f5aa0fd1186592168e9ad692, 2);
    props.vote(prop_id_vecarm_upgrade, 1);

    // Propose Airdrop
    // Data for merkle root and proofs at the bottom of this file
    // Call data for users also at the bottom along with claim amounts
    let airdrop_merkle_root: felt252 =
        3265573744245319827729935647380033250513704347371868070479372031121930765592;
    let prop_id_airdrop = props
        .submit_proposal(
            airdrop_merkle_root, 3
        ); // simulate airdrop proposal, no merkle tree root yet
    props.vote(prop_id_airdrop, 1);

    // Vote for airdrop with another user
    prank(CheatTarget::One(gov_addr), random_user_1, CheatSpan::TargetCalls(3));
    props.vote(prop_id_gov_upgrade, 1);
    props.vote(prop_id_airdrop, 1);
    props.vote(prop_id_vecarm_upgrade, 1);

    // Warp to future and apply proposals
    let warped_timestamp = time_zero + consteval_int!(60 * 60 * 24 * 7) + 420;
    start_warp(CheatTarget::One(gov_addr), warped_timestamp + UNLOCK_DATE);
    let upgrades = IUpgradesDispatcher { contract_address: gov_addr };

    upgrades.apply_passed_proposal(prop_id_airdrop);
    upgrades.apply_passed_proposal(prop_id_vecarm_upgrade);
    // // order is important! first others, then governance. would not work otherwise.
    // // can't apply passed proposal to upgrade vecarm because that would have to be a custom proposal under new governance
    upgrades.apply_passed_proposal(prop_id_gov_upgrade);

    // Initialize veCarm token with governance as the owner
    let vecarm = IVeCRMDispatcher { contract_address: vecarm_addr };
    vecarm.initializer();

    check_if_healthy(gov_addr);

    let staking = IStakingDispatcher { contract_address: gov_addr };
    println!("initializing floating token address");
    staking.initialize_floating_token_address();

    prank(CheatTarget::One(gov_addr), random_user_1, CheatSpan::TargetCalls(1));
    println!("Unstaking Airdrop random_user_1");
    staking.unstake_airdrop();
    let floating = IERC20Dispatcher { contract_address: floating_addr };
    let voting = IERC20Dispatcher { contract_address: vecarm_addr };
    println!("floating balance random_user_1: {:?}", floating.balance_of(random_user_1));
    assert(
        floating.balance_of(random_user_1) == 529593807488384830000000, 'wrong bal floating rndusr1'
    );

    // Claim airdrop and unstake again
    let airdrops = IAirdropDispatcher { contract_address: gov_addr };
    airdrops.claim(random_user_1, RANDOM_USER_1_AIRDROP_AMOUNT, RANDOM_USER_1_AIRDROP_CALLDATA());

    assert(
        voting.balance_of(random_user_1) == 100000000000000000000000, 'wrong bal floating rndusr1'
    );
    println!("Unstaking Airdrop random_user_1 Again");
    prank(CheatTarget::One(gov_addr), random_user_1, CheatSpan::TargetCalls(1));
    staking.unstake_airdrop();
    assert(
        floating.balance_of(random_user_1) == RANDOM_USER_1_AIRDROP_AMOUNT.into(),
        'wrong bal floating rndusr1'
    );

    // Claim all airdrops
    airdrops.claim(team_member_1, TEAM_MEMBER_1_AIRDROP_AMOUNT, TEAM_MEMBER_1_AIRDROP_CALLDATA());
    airdrops.claim(team_member_2, TEAM_MEMBER_2_AIRDROP_AMOUNT, TEAM_MEMBER_2_AIRDROP_CALLDATA());
    airdrops.claim(random_user_2, RANDOM_USER_2_AIRDROP_AMOUNT, RANDOM_USER_2_AIRDROP_CALLDATA());
    airdrops.claim(random_user_3, RANDOM_USER_3_AIRDROP_AMOUNT, RANDOM_USER_3_AIRDROP_CALLDATA());

    // Unstake all airdrops
    prank(CheatTarget::One(gov_addr), team_member_1, CheatSpan::TargetCalls(1));
    staking.unstake_airdrop();

    prank(CheatTarget::One(gov_addr), team_member_2, CheatSpan::TargetCalls(1));
    staking.unstake_airdrop();

    prank(CheatTarget::One(gov_addr), random_user_2, CheatSpan::TargetCalls(1));
    staking.unstake_airdrop();
    assert(
        floating.balance_of(random_user_2) == RANDOM_USER_2_AIRDROP_AMOUNT.into(),
        'wrong bal floating rndusr2'
    );

    prank(CheatTarget::One(gov_addr), random_user_3, CheatSpan::TargetCalls(1));
    staking.unstake_airdrop();
    assert(
        floating.balance_of(random_user_3) == RANDOM_USER_3_AIRDROP_AMOUNT.into(),
        'wrong bal floating rndusr3'
    );
}

#[test]
#[should_panic(expected: ('no extra tokens to unstake',))]
#[fork("MAINNET")]
fn test_unstake_airdrop_unstake_again_failing() {
    let gov_addr: ContractAddress =
        0x001405ab78ab6ec90fba09e6116f373cda53b0ba557789a4578d8c1ec374ba0f
        .try_into()
        .unwrap();
    let vecarm_addr: ContractAddress =
        0x03c0286e9e428a130ae7fbbe911b794e8a829c367dd788e7cfe3efb0367548fa
        .try_into()
        .unwrap();

    //let gov_class: ContractClass = declare("Governance").expect('unable to declare gov');
    //let floating_class: ContractClass = declare("CRMToken").expect('unable to declare CRM');
    //let voting_class: ContractClass = declare("VeCRM").expect('unable to declare voting');

    let mut floating_calldata = ArrayTrait::new();
    floating_calldata.append(10000000000000000000000000); // fixed supply low
    floating_calldata.append(0); // fixed supply high
    floating_calldata.append(gov_addr.into());
    floating_calldata.append(gov_addr.into());
    let floating_addr: ContractAddress =
        0x051c4b1fe3bf6774b87ad0b15ef5d1472759076e42944fff9b9f641ff13e5bbe
        .try_into()
        .unwrap();

    let time_zero = get_block_timestamp();

    let team_member_1: ContractAddress =
        0x0011d341c6e841426448ff39aa443a6dbb428914e05ba2259463c18308b86233
        .try_into()
        .unwrap(); // Team
    let random_user_1: ContractAddress =
        0x052df7acdfd3174241fa6bd5e1b7192cd133f8fc30a2a6ed99b0ddbfb5b22dcd
        .try_into()
        .unwrap(); // Not team

    let props = IProposalsDispatcher { contract_address: gov_addr };
    prank(CheatTarget::One(gov_addr), team_member_1, CheatSpan::TargetCalls(6));

    // Upgrade governance
    let prop_id_gov_upgrade = props
        .submit_proposal(0x04bc8bc7c476c4fca95624809dab1f1aa718edb566184a9d6dfe54f65b32b507, 1);
    props.vote(prop_id_gov_upgrade, 1);

    // Upgrade veCarm token
    let prop_id_vecarm_upgrade = props
        .submit_proposal(0x008e98fd1f76f0d6fca8b03292e1dd6c8a6c5362f5aa0fd1186592168e9ad692, 2);
    props.vote(prop_id_vecarm_upgrade, 1);

    // Propose Airdrop
    // Data for merkle root and proofs at the bottom of this file
    // Call data for users also at the bottom along with claim amounts
    let airdrop_merkle_root: felt252 =
        3265573744245319827729935647380033250513704347371868070479372031121930765592;
    let prop_id_airdrop = props
        .submit_proposal(
            airdrop_merkle_root, 3
        ); // simulate airdrop proposal, no merkle tree root yet
    props.vote(prop_id_airdrop, 1);

    // Vote for airdrop with another user
    prank(CheatTarget::One(gov_addr), random_user_1, CheatSpan::TargetCalls(3));
    props.vote(prop_id_gov_upgrade, 1);
    props.vote(prop_id_airdrop, 1);
    props.vote(prop_id_vecarm_upgrade, 1);

    // Warp to future and apply proposals
    let warped_timestamp = time_zero + consteval_int!(60 * 60 * 24 * 7) + 420;
    start_warp(CheatTarget::One(gov_addr), warped_timestamp + UNLOCK_DATE);
    let upgrades = IUpgradesDispatcher { contract_address: gov_addr };

    upgrades.apply_passed_proposal(prop_id_airdrop);
    upgrades.apply_passed_proposal(prop_id_vecarm_upgrade);
    // // order is important! first others, then governance. would not work otherwise.
    // // can't apply passed proposal to upgrade vecarm because that would have to be a custom proposal under new governance
    upgrades.apply_passed_proposal(prop_id_gov_upgrade);

    // Initialize veCarm token with governance as the owner
    let vecarm = IVeCRMDispatcher { contract_address: vecarm_addr };
    vecarm.initializer();

    check_if_healthy(gov_addr);

    let staking = IStakingDispatcher { contract_address: gov_addr };
    println!("initializing floating token address");
    staking.initialize_floating_token_address();

    prank(CheatTarget::One(gov_addr), random_user_1, CheatSpan::TargetCalls(1));
    println!("Unstaking Airdrop random_user_1");
    staking.unstake_airdrop();
    let floating = IERC20Dispatcher { contract_address: floating_addr };
    assert(
        floating.balance_of(random_user_1) == 529593807488384830000000, 'wrong bal floating rndusr1'
    );

    // Try to unstake again
    prank(CheatTarget::One(gov_addr), random_user_1, CheatSpan::TargetCalls(1));
    staking.unstake_airdrop();
}


#[test]
#[fork("MAINNET")]
#[should_panic(expected: ('tokens not yet unlocked',))]
fn test_unstake_airdrop_team_member_failing() {
    let gov_addr: ContractAddress =
        0x001405ab78ab6ec90fba09e6116f373cda53b0ba557789a4578d8c1ec374ba0f
        .try_into()
        .unwrap();
    let vecarm_addr: ContractAddress =
        0x03c0286e9e428a130ae7fbbe911b794e8a829c367dd788e7cfe3efb0367548fa
        .try_into()
        .unwrap();

    //let gov_class: ContractClass = declare("Governance").expect('unable to declare gov');
    //let floating_class: ContractClass = declare("CRMToken").expect('unable to declare CRM');
    //let voting_class: ContractClass = declare("VeCRM").expect('unable to declare voting');

    let mut floating_calldata = ArrayTrait::new();
    floating_calldata.append(10000000000000000000000000); // fixed supply low
    floating_calldata.append(0); // fixed supply high
    floating_calldata.append(gov_addr.into());
    floating_calldata.append(gov_addr.into());
    let floating_addr: ContractAddress =
        0x051c4b1fe3bf6774b87ad0b15ef5d1472759076e42944fff9b9f641ff13e5bbe
        .try_into()
        .unwrap();

    let time_zero = get_block_timestamp();

    let team_member_1: ContractAddress =
        0x0011d341c6e841426448ff39aa443a6dbb428914e05ba2259463c18308b86233
        .try_into()
        .unwrap(); // Team
    let random_user_1: ContractAddress =
        0x052df7acdfd3174241fa6bd5e1b7192cd133f8fc30a2a6ed99b0ddbfb5b22dcd
        .try_into()
        .unwrap(); // Not team

    let props = IProposalsDispatcher { contract_address: gov_addr };
    prank(CheatTarget::One(gov_addr), team_member_1, CheatSpan::TargetCalls(6));

    // Upgrade governance
    let prop_id_gov_upgrade = props
        .submit_proposal(0x04bc8bc7c476c4fca95624809dab1f1aa718edb566184a9d6dfe54f65b32b507, 1);
    props.vote(prop_id_gov_upgrade, 1);

    // Upgrade veCarm token
    let prop_id_vecarm_upgrade = props
        .submit_proposal(0x008e98fd1f76f0d6fca8b03292e1dd6c8a6c5362f5aa0fd1186592168e9ad692, 2);
    props.vote(prop_id_vecarm_upgrade, 1);

    // Propose Airdrop
    // Data for merkle root and proofs at the bottom of this file
    // Call data for users also at the bottom along with claim amounts
    let airdrop_merkle_root: felt252 =
        3265573744245319827729935647380033250513704347371868070479372031121930765592;
    let prop_id_airdrop = props
        .submit_proposal(
            airdrop_merkle_root, 3
        ); // simulate airdrop proposal, no merkle tree root yet
    props.vote(prop_id_airdrop, 1);

    // Vote for airdrop with another user
    prank(CheatTarget::One(gov_addr), random_user_1, CheatSpan::TargetCalls(3));
    props.vote(prop_id_gov_upgrade, 1);
    props.vote(prop_id_airdrop, 1);
    props.vote(prop_id_vecarm_upgrade, 1);

    // Warp to future and apply proposals
    let warped_timestamp = time_zero + consteval_int!(60 * 60 * 24 * 7) + 420;
    start_warp(CheatTarget::One(gov_addr), warped_timestamp);
    let upgrades = IUpgradesDispatcher { contract_address: gov_addr };

    upgrades.apply_passed_proposal(prop_id_airdrop);
    upgrades.apply_passed_proposal(prop_id_vecarm_upgrade);
    // // order is important! first others, then governance. would not work otherwise.
    // // can't apply passed proposal to upgrade vecarm because that would have to be a custom proposal under new governance
    upgrades.apply_passed_proposal(prop_id_gov_upgrade);

    // Initialize veCarm token with governance as the owner
    let vecarm = IVeCRMDispatcher { contract_address: vecarm_addr };
    vecarm.initializer();

    check_if_healthy(gov_addr);

    let staking = IStakingDispatcher { contract_address: gov_addr };
    println!("initializing floating token address");
    staking.initialize_floating_token_address();

    prank(CheatTarget::One(gov_addr), team_member_1, CheatSpan::TargetCalls(1));
    println!("Unstaking Airdrop Team Member 1");
    staking.unstake_airdrop();
// let floating = IERC20Dispatcher { contract_address: floating_addr };
// assert(floating.balance_of(random_user_1) == 529593807488384830000000, 'wrong bal floating rndusr1');

}


const TEAM_MEMBER_1_AIRDROP_AMOUNT: u128 = 300000000000000000000000;
fn TEAM_MEMBER_1_AIRDROP_CALLDATA() -> Array<felt252> {
    let mut a: Array<felt252> = ArrayTrait::new();
    a.append(0x42d5652af139ebc5dfae0ce3b7a2b2f7c5d9532add8317e5041153e737ded88);
    a.append(0x5cca369bef6525e2ade90417566eebd2ac85025a925fc84ca3dfbb9d33516b3);
    a.append(0x748af8fd73a898cbf2b66f749116487d713bdcb1b773551c474eb82e7bfa890);
    a
}

const TEAM_MEMBER_2_AIRDROP_AMOUNT: u128 = 90000000000000000000000;
fn TEAM_MEMBER_2_AIRDROP_CALLDATA() -> Array<felt252> {
    let mut a: Array<felt252> = ArrayTrait::new();
    a.append(0x63546c463cc5386d41c51828fba7f1bed64405b69fb31bed205c8f04eff420d);
    a.append(0x5cca369bef6525e2ade90417566eebd2ac85025a925fc84ca3dfbb9d33516b3);
    a.append(0x748af8fd73a898cbf2b66f749116487d713bdcb1b773551c474eb82e7bfa890);
    a
}

const RANDOM_USER_1_AIRDROP_AMOUNT: u128 = 629593807488384830000000;
fn RANDOM_USER_1_AIRDROP_CALLDATA() -> Array<felt252> {
    let mut a: Array<felt252> = ArrayTrait::new();
    a.append(0x2e8aa6da9a6a81567f918faadda04f0b228a15c4880971c072c8fdf475a7e10);
    a.append(0x82c5e123788ccc1c13bba6483920664cff0709c8dcd54f54cea584df03b6c5);
    a.append(0x2d2c4925d246e55d70e95dd6b37cfd190a90252d9181598c9857801bede3cbd);
    a
}

const RANDOM_USER_2_AIRDROP_AMOUNT: u128 = 387298219850283398000000;
fn RANDOM_USER_2_AIRDROP_CALLDATA() -> Array<felt252> {
    let mut a: Array<felt252> = ArrayTrait::new();
    a.append(0x5e87200e18c0376ebed9f2d00334ca78484746b0d83ffc1e5132a6306e2be07);
    a.append(0x82c5e123788ccc1c13bba6483920664cff0709c8dcd54f54cea584df03b6c5);
    a.append(0x2d2c4925d246e55d70e95dd6b37cfd190a90252d9181598c9857801bede3cbd);
    a
}

const RANDOM_USER_3_AIRDROP_AMOUNT: u128 = 3637011455678970700000;
fn RANDOM_USER_3_AIRDROP_CALLDATA() -> Array<felt252> {
    let mut a: Array<felt252> = ArrayTrait::new();
    a.append(0x15a533fc7c17b8a4e9cd7aa3e3a5dc8f9c88ffa388e99226de39fa9297eb767);
    a.append(0x5c7fad4bdb8276402e72c03e9b80fcceb48174185be414a40798a97ab03d0de);
    a.append(0x2d2c4925d246e55d70e95dd6b37cfd190a90252d9181598c9857801bede3cbd);
    a
}
// Json used for generating the test merkle root
// [
//   {
//     "address": "0x11d341c6e841426448ff39aa443a6dbb428914e05ba2259463c18308b86233",
//     "amount": "300000000000000000000000"
//   },
//   {
//     "address": "0x583a9d956d65628f806386ab5b12dccd74236a3c6b930ded9cf3c54efc722a1",
//     "amount": "90000000000000000000000"
//   },
//   {
//     "address": "0x52df7acdfd3174241fa6bd5e1b7192cd133f8fc30a2a6ed99b0ddbfb5b22dcd",
//     "amount": "629593807488384830000000"
//   },
//   {
//     "address": "0x21b2b25dd73bc60b0549683653081f8963562cbe5cba2d123ec0cbcbf0913e4",
//     "amount": "387298219850283398000000"
//   },
//   {
//     "address": "0x539577df56aab4269c13ece28baff916ef08c26ba480142a3ce1739d2e848d9",
//     "amount": "3637011455678970700000"
//   }
// ]


