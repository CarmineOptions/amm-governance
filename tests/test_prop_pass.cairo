use amm_governance::proposals::{IProposalsDispatcherTrait, IProposalsDispatcher};
use amm_governance::staking::{IStakingDispatcherTrait, IStakingDispatcher};
use openzeppelin::token::erc20::interface::{IERC20DispatcherTrait, IERC20Dispatcher};

use snforge_std::{CheatSpan, CheatTarget, prank, start_warp};
use starknet::{ContractAddress, get_block_timestamp};

const DECS: u128 = 1000000000000000000; // 10*18

fn get_team_addresses() -> @Span<felt252> {
    let arr = array![
        0x0583a9d956d65628f806386ab5b12dccd74236a3c6b930ded9cf3c54efc722a1,
        0x06717eaf502baac2b6b2c6ee3ac39b34a52e726a73905ed586e757158270a0af,
        0x058d2ddce3e4387dc0da7e45c291cb436bb809e00a4c132bcc5758e4574f55c7,
        0x05e61dfb8a9863e446981e804a203a7ad3a2d15495c85b79cfd053ec63e9bfb3,
        0x04379c63976feaca8019db2c08f7af8e976b11aef7eda9dfe2ef604e76fc99d2,
        0x0011d341c6e841426448ff39aa443a6dbb428914e05ba2259463c18308b86233,
        0x00d79a15d84f5820310db21f953a0fae92c95e25d93cb983cc0c27fc4c52273c,
        0x03d1525605db970fa1724693404f5f64cba8af82ec4aab514e6ebd3dec4838ad,
        0x06fd0529AC6d4515dA8E5f7B093e29ac0A546a42FB36C695c8f9D13c5f787f82,
        0x04d2FE1Ff7c0181a4F473dCd982402D456385BAE3a0fc38C49C0A99A620d1abe,
        0x062c290f0afa1ea2d6b6d11f6f8ffb8e626f796e13be1cf09b84b2edaa083472,
        0x01714ab9a05b062e0c09cf635fd469ce664c914ef9d9ff2394928e31707ce9a6,
        0x06c59d2244250f2540a2694472e3c31262e887ff02582ef864bf0e76c34e1298,
        0x0528f064c43e2d6Ee73bCbfB725bAa293CD31Ea1f1861EA2F80Bc283Ea4Ad728,
        0x05105649f42252f79109356e1c8765b7dcdb9bf4a6a68534e7fc962421c7efd2,
        0x00777558f1c767126461540d1f10118981d30bd620707e99686bfc9f00ae66f0,
        0x06e2c2a5da2e5478b1103d452486afba8378e91f32a124f0712f09edd3ccd923,
        0x035e0845154423c485e5216f70496130079b5ddc8ac66e3e316184482788e2a0,
        0x0244dda2c6581eb158db225992153c9d49e92c412424daeb83a773fa9822eeef, // team multisig
        0x059c0d4c5dde72e8cab06105be5f2beeb4de52dc516ccbafcaa0b58894d16397, // company wallet
    ];
    @arr.span()
}

fn get_investor_addresses() -> @Span<felt252> {
    let arr = array![
        0x05a4523982b437aadd1b5109b6618c46f7b1c42f5f9e7de1a3b84091f87d411b,
        0x056d761e1e5d1918dba05de02afdbd8de8da01a63147dce828c9b1fe9227077d, // investor multisig
    ];
    @arr.span()
}

fn get_adjusted_group_voting_power(contract: IStakingDispatcher, investors: bool) -> u128 {
    let mut total: u128 = 0;
    let mut addresses = *get_team_addresses();
    loop {
        match addresses.pop_front() {
            Option::Some(addr) => {
                total += contract.get_adjusted_voting_power((*addr).try_into().unwrap());
            },
            Option::None(_) => { break total; }
        }
    }
}


fn get_total_group_voting_power(contract: IStakingDispatcher, investors: bool) -> u128 {
    let mut total: u128 = 0;
    let mut addresses = if investors {
        *get_investor_addresses()
    } else {
        *get_team_addresses()
    };
    loop {
        match addresses.pop_front() {
            Option::Some(addr) => {
                total += contract.get_total_voting_power((*addr).try_into().unwrap());
            },
            Option::None(_) => { break total; }
        }
    }
}

fn get_total_voted_adjusted(
    proposals: IProposalsDispatcher, staking: IStakingDispatcher, prop_id: u32
) -> u128 {
    let mut addresses = *get_team_addresses();
    let mut total = 0;
    loop {
        match addresses.pop_front() {
            Option::Some(addr) => {
                if (proposals.get_user_voted((*addr).try_into().unwrap(), prop_id.into()) != 0) {
                    total += staking.get_adjusted_voting_power((*addr).try_into().unwrap());
                }
            },
            Option::None(_) => { break total; }
        }
    }
}

#[test]
#[fork("MAINNET")]
fn test_prop_pass() {
    let staking = IStakingDispatcher {
        contract_address: 0x001405ab78ab6ec90fba09e6116f373cda53b0ba557789a4578d8c1ec374ba0f
            .try_into()
            .unwrap()
    };
    let total_team_adj = get_adjusted_group_voting_power(staking, false);
    println!("total team adjusted: {:?}", total_team_adj / DECS);
    let total_team_total = get_total_group_voting_power(staking, false);
    println!("total team total: {:?}", total_team_total / DECS);
    let investors_total = get_total_group_voting_power(staking, true);
    println!("investors total: {:?}", investors_total);
    let vecrm = IERC20Dispatcher {
        contract_address: 0x3c0286e9e428a130ae7fbbe911b794e8a829c367dd788e7cfe3efb0367548fa
            .try_into()
            .unwrap()
    };
    println!("vecrm total supply: {:?}", vecrm.total_supply() / DECS.into());
    let props = IProposalsDispatcher {
        contract_address: 0x001405ab78ab6ec90fba09e6116f373cda53b0ba557789a4578d8c1ec374ba0f
            .try_into()
            .unwrap()
    };
    let total_voted_on_prop_adj = get_total_voted_adjusted(props, staking, 77);
    println!("total adjusted votes on prop: {:?}", total_voted_on_prop_adj / DECS);
    let (yay, _nay) = props.get_vote_counts(77);
    println!("recorded vote count: {:?}", yay / DECS);
}

#[test]
#[fork("MAINNET")]
fn test_can_pass_next_prop() {
    let user1: ContractAddress =
        0x0011d341c6e841426448ff39aa443a6dbb428914e05ba2259463c18308b86233 // team m 1
        .try_into()
        .unwrap();
    let gov_addr = 0x001405ab78ab6ec90fba09e6116f373cda53b0ba557789a4578d8c1ec374ba0f
        .try_into()
        .unwrap();
    let props = IProposalsDispatcher { contract_address: gov_addr };
    let staking = IStakingDispatcher { contract_address: gov_addr };
    let vecrm = IERC20Dispatcher {
        contract_address: 0x3c0286e9e428a130ae7fbbe911b794e8a829c367dd788e7cfe3efb0367548fa
            .try_into()
            .unwrap()
    };
    prank(CheatTarget::One(gov_addr), user1, CheatSpan::TargetCalls(1));
    let prop_id = props.submit_proposal(0x42, 0x4);
    prank(CheatTarget::One(gov_addr), user1, CheatSpan::TargetCalls(1));
    props.vote(prop_id, 1);

    let user2: ContractAddress = 0x0583a9d956d65628f806386ab5b12dccd74236a3c6b930ded9cf3c54efc722a1
        .try_into()
        .unwrap(); // team o
    prank(CheatTarget::One(gov_addr), user2, CheatSpan::TargetCalls(1));
    props.vote(prop_id, 1);

    let user3: ContractAddress = 0x03d1525605db970fa1724693404f5f64cba8af82ec4aab514e6ebd3dec4838ad
        .try_into()
        .unwrap(); //team d
    prank(CheatTarget::One(gov_addr), user3, CheatSpan::TargetCalls(1));
    props.vote(prop_id, 1);

    let user4: ContractAddress = 0x00d79a15d84f5820310db21f953a0fae92c95e25d93cb983cc0c27fc4c52273c
        .try_into()
        .unwrap(); //team m 2
    prank(CheatTarget::One(gov_addr), user4, CheatSpan::TargetCalls(1));
    props.vote(prop_id, 1);

    let community1: ContractAddress =
        0x0428c240649b76353644faF011B0d212e167f148fdd7479008Aa44eEaC782BfC
        .try_into()
        .unwrap(); // community m 1
    prank(CheatTarget::One(gov_addr), community1, CheatSpan::TargetCalls(1));
    props.vote(prop_id, 1);
    let community1_balance: u128 = vecrm.balance_of(community1).try_into().unwrap();

    let user5: ContractAddress = 0x06717eaf502baac2b6b2c6ee3ac39b34a52e726a73905ed586e757158270a0af
        .try_into()
        .unwrap(); //team a 1
    prank(CheatTarget::One(gov_addr), user5, CheatSpan::TargetCalls(1));
    props.vote(prop_id, 1);

    let (yay, _nay) = props.get_vote_counts(prop_id);
    assert(
        get_total_voted_adjusted(props, staking, prop_id.try_into().unwrap())
            + community1_balance == yay,
        'votes dont match??'
    );
    println!("voted on prop_id: {:?}", yay / DECS);

    let curr_timestamp = get_block_timestamp();
    let warped_timestamp = curr_timestamp + consteval_int!(60 * 60 * 24 * 7) + 420;

    start_warp(CheatTarget::One(gov_addr), warped_timestamp);
    assert(props.get_proposal_status(prop_id) == 1, 'prop not passed');
}
