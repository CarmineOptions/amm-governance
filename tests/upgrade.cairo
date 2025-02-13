use amm_governance::constants::UNLOCK_DATE;
use amm_governance::contract::{
    IMigrateDispatcher, IMigrateDispatcherTrait, ICarmineGovernanceDispatcher,
    ICarmineGovernanceDispatcherTrait
};
use amm_governance::staking::{IStakingDispatcher, IStakingDispatcherTrait};
use amm_governance::vecarm::{IVeCRMDispatcher, IVeCRMDispatcherTrait};
use core::num::traits::Zero;
use konoha::constants;

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
    BlockId, declare, ContractClassTrait, ContractClass, start_prank, stop_prank, CheatTarget,
    prank, CheatSpan, roll, start_warp
};
use starknet::{ClassHash, ContractAddress, get_block_timestamp, get_block_number};
use super::utils::vote_on_proposal;


#[test]
#[fork("MAINNET")]
fn test_upgrade_to_master() {
    let gov_contract_addr: ContractAddress =
        0x001405ab78ab6ec90fba09e6116f373cda53b0ba557789a4578d8c1ec374ba0f
        .try_into()
        .unwrap();
    let dispatcher = IProposalsDispatcher { contract_address: gov_contract_addr };

    // declare current and submit proposal
    let gov_class: ContractClass = declare("Governance").expect('unable to declare!');
    assert(Zero::is_non_zero(@gov_class.class_hash), 'new classhash zero??');
    let user2_address: ContractAddress =
        0x06e2c2a5da2e5478b1103d452486afba8378e91f32a124f0712f09edd3ccd923
        .try_into()
        .unwrap();
    prank(CheatTarget::One(gov_contract_addr), user2_address, CheatSpan::TargetCalls(1));
    let new_prop_id = dispatcher.submit_proposal(gov_class.class_hash.into(), 1);
    println!("Prop submitted: {:?}", new_prop_id);
    vote_on_proposal(gov_contract_addr, new_prop_id.try_into().unwrap());

    //simulate passage of time
    let current_timestamp = get_block_timestamp();
    let end_timestamp = current_timestamp + constants::PROPOSAL_VOTING_SECONDS;
    start_warp(CheatTarget::One(gov_contract_addr), end_timestamp + 1);

    let upgrade_dispatcher = IUpgradesDispatcher { contract_address: gov_contract_addr };
    upgrade_dispatcher.apply_passed_proposal(new_prop_id);
}

fn test_deposit_to_amm_from_treasury(gov_contract_addr: ContractAddress) {
    let treasury_class: ContractClass = declare("Treasury").expect('unable to declare Treasury');
    let mut treasury_deploy_calldata = ArrayTrait::new();
    treasury_deploy_calldata.append(gov_contract_addr.into());
    let amm_addr: ContractAddress =
        0x047472e6755afc57ada9550b6a3ac93129cc4b5f98f51c73e0644d129fd208d9
        .try_into()
        .unwrap();
    treasury_deploy_calldata.append(amm_addr.into());
    let (treasury_address, _) = treasury_class
        .deploy(@treasury_deploy_calldata)
        .expect('unable to deploy treasury');

    let eth_addr: ContractAddress =
        0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7
        .try_into()
        .unwrap();
    let sequencer_address: ContractAddress =
        0x01176a1bd84444c89232ec27754698e5d2e7e1a7f1539f12027f28b23ec9f3d8
        .try_into()
        .unwrap(); // random whale
    let transfer_dispatcher = IERC20Dispatcher { contract_address: eth_addr };
    let oneeth = 1000000000000000000;
    let to_deposit = 900000000000000000;
    prank(CheatTarget::One(eth_addr), sequencer_address, CheatSpan::TargetCalls(1));
    transfer_dispatcher.transfer(treasury_address, oneeth);
    assert(transfer_dispatcher.balanceOf(treasury_address) >= to_deposit, 'balance too low??');

    prank(CheatTarget::One(eth_addr), sequencer_address, CheatSpan::TargetCalls(1));
    transfer_dispatcher.approve(treasury_address, to_deposit);

    let treasury_dispatcher = ITreasuryDispatcher { contract_address: treasury_address };
    prank(CheatTarget::One(treasury_address), gov_contract_addr, CheatSpan::TargetCalls(2));
    treasury_dispatcher
        .provide_liquidity_to_carm_AMM(
            0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7.try_into().unwrap(),
            0x53c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8.try_into().unwrap(),
            0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7.try_into().unwrap(),
            0,
            to_deposit.into()
        );
    println!("provided liq");
    roll(
        CheatTarget::All, get_block_number() + 1, CheatSpan::Indefinite
    ); // to bypass sandwich guard
    treasury_dispatcher
        .withdraw_liquidity(
            0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7.try_into().unwrap(),
            0x53c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8.try_into().unwrap(),
            0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7.try_into().unwrap(),
            0,
            (to_deposit - 100000000000000000).into()
        );
    assert(transfer_dispatcher.balanceOf(treasury_address) >= to_deposit, 'balance too low??');
}

fn check_if_healthy(gov_contract_addr: ContractAddress) -> bool {
    let dispatcher = IProposalsDispatcher { contract_address: gov_contract_addr };
    dispatcher.get_proposal_status(0);
    let prop_details = dispatcher.get_proposal_details(0);
    (prop_details.payload + prop_details.to_upgrade) != 0
}

fn upgrade_amm(gov_contract_addr: ContractAddress, new_classhash: ClassHash) {
    let proposals = IProposalsDispatcher { contract_address: gov_contract_addr };
    let mut calldata = ArrayTrait::new();
    calldata.append(new_classhash.into());

    let prop_id = proposals.submit_custom_proposal(0, calldata.span());
    vote_on_proposal(gov_contract_addr, prop_id);
    let upgrades = IUpgradesDispatcher { contract_address: gov_contract_addr };
    upgrades.apply_passed_proposal(prop_id.into());
}

fn test_upgrade_amm_back(amm: ContractAddress, owner: ContractAddress, new_classhash: ClassHash) {
    let upgradable_amm = IUpgradeableDispatcher { contract_address: amm };
    prank(CheatTarget::One(amm), owner, CheatSpan::TargetCalls(1));
    upgradable_amm.upgrade(new_classhash);
}
