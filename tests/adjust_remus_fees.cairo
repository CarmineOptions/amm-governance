use amm_governance::arbitrary_proposal_adjust_remus_fees::REMUS_ADDRESS;


use amm_governance::proposals::{IProposalsDispatcherTrait, IProposalsDispatcher};
use amm_governance::traits::{IERC20Dispatcher, IERC20DispatcherTrait};
use amm_governance::traits::{IRemusDEXDispatcher, IRemusDEXDispatcherTrait};
use amm_governance::types::{MarketConfig, Fees};


use konoha::upgrades::IUpgradesDispatcher;
use konoha::upgrades::IUpgradesDispatcherTrait;
use snforge_std::{
    CheatSpan, CheatTarget, ContractClassTrait, ContractClass, start_prank, prank, start_warp,
    declare
};
use starknet::ClassHash;
use starknet::SyscallResult;
use starknet::SyscallResultTrait;
use starknet::syscalls::deploy_syscall;

use starknet::{ContractAddress, get_block_timestamp};

fn get_voter_addresses() -> @Span<felt252> {
    let arr = array![
        0x0011d341c6e841426448ff39aa443a6dbb428914e05ba2259463c18308b86233,
        0x0583a9d956d65628f806386ab5b12dccd74236a3c6b930ded9cf3c54efc722a1,
        0x03d1525605db970fa1724693404f5f64cba8af82ec4aab514e6ebd3dec4838ad,
        0x00d79a15d84f5820310db21f953a0fae92c95e25d93cb983cc0c27fc4c52273c,
        // 0x0428c240649b76353644faF011B0d212e167f148fdd7479008Aa44eEaC782BfC,
        0x06717eaf502baac2b6b2c6ee3ac39b34a52e726a73905ed586e757158270a0af,
    ];
    @arr.span()
}


#[test]
#[fork("MAINNET_ADJUST_REMUS_FEES")]
fn test_adjust_remus_fees() {
    let proposal_hash = 0x05f3c6cd06f9390ed46e4ea2a350039297d8b809a120ddcf03098446081e8d26;

    let gov_addr: ContractAddress =
        0x001405ab78ab6ec90fba09e6116f373cda53b0ba557789a4578d8c1ec374ba0f
        .try_into()
        .unwrap();

    let props = IProposalsDispatcher { contract_address: gov_addr };

    let user1: ContractAddress =
        0x0011d341c6e841426448ff39aa443a6dbb428914e05ba2259463c18308b86233 // team m 1
        .try_into()
        .unwrap();

    start_prank(CheatTarget::One(gov_addr), user1);

    let prop_id = props.submit_proposal(proposal_hash, 6);

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

    let curr_timestamp = get_block_timestamp();
    let proposal_wait_time = consteval_int!(60 * 60 * 24 * 7) + 420;
    let warped_timestamp = curr_timestamp + proposal_wait_time;

    start_warp(CheatTarget::One(gov_addr), warped_timestamp);
    assert(props.get_proposal_status(prop_id) == 1, 'arbitrary proposal not passed');

    let mut dex = IRemusDEXDispatcher { contract_address: REMUS_ADDRESS.try_into().unwrap() };

    let old_configs = dex.get_all_market_configs();

    let upgrades = IUpgradesDispatcher { contract_address: gov_addr };
    upgrades.apply_passed_proposal(prop_id);

    // Now try to add some market
    let new_configs = dex.get_all_market_configs();

    let mut i = 0;

    assert(new_configs.len() == old_configs.len(), 'Configs len mismatch');

    while i < new_configs
        .len() {
            let (_, oc) = *old_configs.at(i);
            let (_, nc) = *new_configs.at(i);

            assert(oc.base_token == nc.base_token, 'wrong base');
            assert(oc.quote_token == nc.quote_token, 'wrong quote');
            assert(oc.tick_size == nc.tick_size, 'wrong tick');
            assert(oc.lot_size == nc.lot_size, 'wrong lot');
            assert(oc.trading_enabled == oc.trading_enabled, 'wrong trading');

            assert(nc.fees.taker_fee_bps == 0, 'wrong taker fee');
            assert(nc.fees.maker_fee_bps == 0, 'wrong maker fee');

            i += 1;
        }
}
