use core::num::traits::Zero;
use konoha::contract::IGovernanceDispatcher;
use konoha::contract::IGovernanceDispatcherTrait;
use konoha::proposals::IProposalsDispatcher;
use konoha::proposals::IProposalsDispatcherTrait;
use konoha::upgrades::IUpgradesDispatcher;
use konoha::upgrades::IUpgradesDispatcherTrait;
use konoha::treasury::{ITreasuryDispatcher, ITreasuryDispatcherTrait};
use amm_governance::contract::{
    IMigrateDispatcher, IMigrateDispatcherTrait, ICarmineGovernanceDispatcher,
    ICarmineGovernanceDispatcherTrait
};
use super::utils::{vote_on_proposal, IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{
    BlockId, declare, ContractClassTrait, ContractClass, start_prank, CheatTarget, start_warp
};
use starknet::{ClassHash, ContractAddress, get_block_timestamp};

#[test]
#[fork("MAINNET")]
fn test_upgrade_to_master() {
    let gov_contract_addr: ContractAddress =
        0x001405ab78ab6ec90fba09e6116f373cda53b0ba557789a4578d8c1ec374ba0f
        .try_into()
        .unwrap();
    let dispatcher = IProposalsDispatcher { contract_address: gov_contract_addr };

    // declare current and submit proposal
    let new_contract: ContractClass = declare("Governance").expect('unable to declare!');
    assert(Zero::is_non_zero(@new_contract.class_hash), 'new classhash zero??');
    let scaling_address: ContractAddress =
        0x052df7acdfd3174241fa6bd5e1b7192cd133f8fc30a2a6ed99b0ddbfb5b22dcd
        .try_into()
        .unwrap();
    start_prank(CheatTarget::One(gov_contract_addr), scaling_address);
    let new_prop_id = dispatcher.submit_proposal(new_contract.class_hash.into(), 1);
    vote_on_proposal(gov_contract_addr, new_prop_id.try_into().unwrap());

    let upgrade_dispatcher = IUpgradesDispatcher { contract_address: gov_contract_addr };
    upgrade_dispatcher.apply_passed_proposal(new_prop_id);
    let amm_governance = IMigrateDispatcher { contract_address: gov_contract_addr };
    amm_governance.add_custom_proposals();
    assert(check_if_healthy(gov_contract_addr), 'new gov not healthy');
    upgrade_amm(
        gov_contract_addr,
        0x0239b6f9eeb5ffba1df4da7f33e116d3603d724283bc01338125eed82964e729.try_into().unwrap()
    );
    test_deposit_to_amm_from_treasury(gov_contract_addr);
}

fn test_deposit_to_amm_from_treasury(gov_contract_addr: ContractAddress) {
    let treasury_class: ContractClass = declare("Treasury").expect('unable to declare Treasury');
    let mut treasury_deploy_calldata = ArrayTrait::new();
    treasury_deploy_calldata.append(gov_contract_addr.into());
    treasury_deploy_calldata
        .append(
            ICarmineGovernanceDispatcher { contract_address: gov_contract_addr }
                .get_amm_address()
                .into()
        );
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
    start_prank(CheatTarget::One(eth_addr), sequencer_address);
    let transfer_dispatcher = IERC20Dispatcher { contract_address: eth_addr };
    let oneeth = 1000000000000000000;
    let to_deposit = oneeth - 10000000000000000;
    transfer_dispatcher.transfer(treasury_address, oneeth);
    assert(transfer_dispatcher.balanceOf(treasury_address) >= to_deposit , 'balance too low??');
    let treasury_dispatcher = ITreasuryDispatcher { contract_address: treasury_address };
    start_prank(CheatTarget::One(eth_addr), gov_contract_addr);
    
    transfer_dispatcher.approve(treasury_address, to_deposit);
    start_prank(CheatTarget::One(treasury_address), gov_contract_addr);
    println!("providing liq");
    treasury_dispatcher
        .provide_liquidity_to_carm_AMM(
            0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7.try_into().unwrap(),
            0x53c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8.try_into().unwrap(),
            0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7.try_into().unwrap(),
            0,
            to_deposit.into()
        );
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
