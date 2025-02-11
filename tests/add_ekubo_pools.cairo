use amm_governance::constants::{
    LP_TOKEN_CLASS_HASH, AMM_CLASS_HASH, OPTION_CALL, OPTION_PUT, OPTION_TOKEN_CLASS_HASH,
    TRADE_SIDE_LONG, TRADE_SIDE_SHORT
};
use amm_governance::proposals::{IProposalsDispatcherTrait, IProposalsDispatcher};
use amm_governance::traits::{IAMMDispatcher, IAMMDispatcherTrait};
use amm_governance::traits::{IERC20Dispatcher, IERC20DispatcherTrait};
use amm_governance::types::Option_;
use core::traits::{Into, TryInto};

use cubit::f128::types::{Fixed, FixedTrait};
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
        0x0428c240649b76353644faF011B0d212e167f148fdd7479008Aa44eEaC782BfC,
        0x06717eaf502baac2b6b2c6ee3ac39b34a52e726a73905ed586e757158270a0af,
    ];
    @arr.span()
}


#[test]
#[fork("MAINNET_ADD_EKUBO_POOLS")]
fn test_add_ekubo_options() {
    let gov_addr = 0x001405ab78ab6ec90fba09e6116f373cda53b0ba557789a4578d8c1ec374ba0f
        .try_into()
        .unwrap();

    // Transfer ownership to governance
    let amm_address: ContractAddress =
        0x047472e6755afc57ada9550b6a3ac93129cc4b5f98f51c73e0644d129fd208d9
        .try_into()
        .unwrap();
    let amm = IAMMDispatcher { contract_address: amm_address };
    let amm_owner_address: ContractAddress = amm.owner();

    prank(CheatTarget::One(amm_address), amm_owner_address, CheatSpan::TargetCalls(1));
    // start_prank(CheatTarget::One(amm_address), amm_owner_address);
    amm.transfer_ownership(gov_addr);

    // Declare the new arbitrary proposal
    let arb_prop_class = declare("ArbitraryProposalAddEkuboPools");
    let props = IProposalsDispatcher { contract_address: gov_addr };

    let user1: ContractAddress =
        0x0011d341c6e841426448ff39aa443a6dbb428914e05ba2259463c18308b86233 // team m 1
        .try_into()
        .unwrap();

    start_prank(CheatTarget::One(gov_addr), user1);

    let prop_id = props.submit_proposal(arb_prop_class.unwrap().class_hash.into(), 6);

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

    let upgrades = IUpgradesDispatcher { contract_address: gov_addr };

    upgrades.apply_passed_proposal(prop_id);

    let USDC_TOKEN: ContractAddress =
        0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8
        .try_into()
        .unwrap();

    let EKUBO_TOKEN: ContractAddress =
        0x075afe6402ad5a5c20dd25e10ec3b3986acaa647b77e4ae24b0cbc9a54a27a87
        .try_into()
        .unwrap();

    // Get all lptokens
    let lpts = amm.get_all_lptoken_addresses();
    let ekubo_call_lpt = *lpts.at(lpts.len() - 2);
    let ekubo_put_lpt = *lpts.at(lpts.len() - 1);

    let ekubo_call_pool = amm.get_pool_definition_from_lptoken_address(ekubo_call_lpt);
    assert(ekubo_call_pool.quote_token_address == USDC_TOKEN, 'wrong call quote');
    assert(ekubo_call_pool.base_token_address == EKUBO_TOKEN, 'wrong call base');
    assert(ekubo_call_pool.option_type == OPTION_CALL, 'wrong call option type');

    let ekubo_put_pool = amm.get_pool_definition_from_lptoken_address(ekubo_put_lpt);
    assert(ekubo_put_pool.quote_token_address == USDC_TOKEN, 'wrong put quote');
    assert(ekubo_put_pool.base_token_address == EKUBO_TOKEN, 'wrong put base');
    assert(ekubo_put_pool.option_type == OPTION_PUT, 'wrong put option type');

    // Add some ekubo options
    let now = get_block_timestamp();
    let expiry = now + 7 * 86_400; // + week
    let strike_price = 46116860184273879040; // 2.5 * 2**64
    // start_warp(CheatTarget::One(amm_address), now);

    deploy_and_add_ekubo_options(amm_address, ekubo_call_lpt, ekubo_put_lpt, expiry, strike_price);

    // Add liquidity
    let base_token: ContractAddress = EKUBO_TOKEN;
    let quote_token: ContractAddress = USDC_TOKEN;
    let ekubo_token = IERC20Dispatcher { contract_address: base_token };
    let usdc_token = IERC20Dispatcher { contract_address: quote_token };

    let TEN_K_EKUBO: u256 = 100000000000000000000000;
    let TEN_K_USDC: u256 = 10000000000;

    // Add liquidity to ekubo call pool
    prank(CheatTarget::One(base_token), EKUBO_WHALE(), CheatSpan::TargetCalls(1));
    ekubo_token.approve(amm_address, TEN_K_EKUBO * 10);

    prank(CheatTarget::One(amm_address), EKUBO_WHALE(), CheatSpan::TargetCalls(1));
    amm.deposit_liquidity(base_token, quote_token, base_token, OPTION_CALL, TEN_K_EKUBO);

    // Add liquidity to ekubo put pool
    prank(CheatTarget::One(quote_token), USDC_WHALE(), CheatSpan::TargetCalls(1));
    usdc_token.approve(amm_address, TEN_K_EKUBO);

    prank(CheatTarget::One(amm_address), USDC_WHALE(), CheatSpan::TargetCalls(1));
    amm.deposit_liquidity(quote_token, quote_token, base_token, OPTION_PUT, TEN_K_USDC);

    // // Do some trades
    let strike_fixed = FixedTrait::new(strike_price.try_into().unwrap(), false);

    prank(CheatTarget::One(base_token), EKUBO_WHALE(), CheatSpan::TargetCalls(1));
    ekubo_token.approve(amm_address, TEN_K_EKUBO);

    prank(CheatTarget::One(amm_address), EKUBO_WHALE(), CheatSpan::TargetCalls(1));
    let _ = amm
        .trade_open(
            OPTION_CALL,
            strike_fixed,
            expiry,
            TRADE_SIDE_LONG,
            (TEN_K_EKUBO / 100).try_into().unwrap(),
            quote_token,
            base_token,
            FixedTrait::new_unscaled(1_000_000, false),
            expiry
        );

    prank(CheatTarget::One(quote_token), USDC_WHALE(), CheatSpan::TargetCalls(1));
    usdc_token.approve(amm_address, TEN_K_EKUBO);

    prank(CheatTarget::One(amm_address), USDC_WHALE(), CheatSpan::TargetCalls(1));
    let _ = amm
        .trade_open(
            OPTION_PUT,
            strike_fixed,
            expiry,
            TRADE_SIDE_LONG,
            (TEN_K_EKUBO / 100).try_into().unwrap(),
            quote_token,
            base_token,
            FixedTrait::new_unscaled(1_000_000, false),
            expiry
        );
// works
}


// Just some code for adding options
fn EKUBO_WHALE() -> ContractAddress {
    0x02a3ed03046e1042e193651e3da6d3c973e3d45c624442be936a374380a78bb5.try_into().unwrap()
}

fn USDC_WHALE() -> ContractAddress {
    0x00000005dd3d2f4429af886cd1a3b08289dbcea99a294197e9eb43b0e0325b4b.try_into().unwrap()
}


fn deploy_and_add_ekubo_options(
    amm_address: ContractAddress,
    call_lpt: ContractAddress,
    put_lpt: ContractAddress,
    expiry: u64,
    strike_price: felt252
) {
    let amm = IAMMDispatcher { contract_address: amm_address };
    let owner = amm.owner();
    let opt_class: ClassHash = OPTION_TOKEN_CLASS_HASH.try_into().unwrap();

    let TOKEN_USDC_ADDRESS: ContractAddress =
        0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8
        .try_into()
        .unwrap();

    let TOKEN_EKUBO_ADDRESS: ContractAddress =
        0x075afe6402ad5a5c20dd25e10ec3b3986acaa647b77e4ae24b0cbc9a54a27a87
        .try_into()
        .unwrap();

    let mut long_call_data = ArrayTrait::new();
    long_call_data.append('OptLongCall');
    long_call_data.append('OLC');
    long_call_data.append(amm_address.into());
    long_call_data.append(TOKEN_USDC_ADDRESS.into());
    long_call_data.append(TOKEN_EKUBO_ADDRESS.into());
    long_call_data.append(OPTION_CALL.into());
    long_call_data.append(strike_price);
    long_call_data.append(expiry.into());
    long_call_data.append(TRADE_SIDE_LONG.into());
    let long_call_depl = deploy_syscall(opt_class, 'OptLongCall', long_call_data.span(), false);
    let (long_call_address, _) = long_call_depl.unwrap_syscall();

    // // Short Call
    let mut short_call_data = ArrayTrait::new();
    short_call_data.append('OptShortCall');
    short_call_data.append('OSC');
    short_call_data.append(amm_address.into());
    short_call_data.append(TOKEN_USDC_ADDRESS.into());
    short_call_data.append(TOKEN_EKUBO_ADDRESS.into());
    short_call_data.append(OPTION_CALL.into());
    short_call_data.append(strike_price);
    short_call_data.append(expiry.into());
    short_call_data.append(TRADE_SIDE_SHORT.into());
    let short_call_depl = deploy_syscall(opt_class, 'OptshortCall', short_call_data.span(), false);
    let (short_call_address, _) = short_call_depl.unwrap_syscall();

    // // Long put
    let mut long_put_data = ArrayTrait::new();
    long_put_data.append('OptLongPut');
    long_put_data.append('OLP');
    long_put_data.append(amm_address.into());
    long_put_data.append(TOKEN_USDC_ADDRESS.into());
    long_put_data.append(TOKEN_EKUBO_ADDRESS.into());
    long_put_data.append(OPTION_PUT.into());
    long_put_data.append(strike_price);
    long_put_data.append(expiry.into());
    long_put_data.append(TRADE_SIDE_LONG.into());
    let long_put_depl = deploy_syscall(opt_class, 'OptLongput', long_put_data.span(), false);
    let (long_put_address, _) = long_put_depl.unwrap_syscall();

    // // Short put
    let mut short_put_data = ArrayTrait::new();
    short_put_data.append('OptShortPut');
    short_put_data.append('OSP');
    short_put_data.append(amm_address.into());
    short_put_data.append(TOKEN_USDC_ADDRESS.into());
    short_put_data.append(TOKEN_EKUBO_ADDRESS.into());
    short_put_data.append(OPTION_PUT.into());
    short_put_data.append(strike_price);
    short_put_data.append(expiry.into());
    short_put_data.append(TRADE_SIDE_SHORT.into());
    let short_put_depl = deploy_syscall(opt_class, 'Optshortput', short_put_data.span(), false);
    let (short_put_address, _) = short_put_depl.unwrap_syscall();

    let init_vol = FixedTrait::from_unscaled_felt(100);

    start_prank(CheatTarget::One(amm_address), owner);

    let base_token: ContractAddress = TOKEN_EKUBO_ADDRESS.try_into().unwrap();
    let quote_token: ContractAddress = TOKEN_USDC_ADDRESS.try_into().unwrap();

    // Calls
    amm
        .add_option_both_sides(
            expiry,
            FixedTrait::new(strike_price.try_into().unwrap(), false),
            quote_token,
            base_token,
            OPTION_CALL,
            call_lpt,
            long_call_address,
            short_call_address,
            init_vol
        );

    // Puts
    amm
        .add_option_both_sides(
            expiry,
            FixedTrait::new(strike_price.try_into().unwrap(), false),
            quote_token,
            base_token,
            OPTION_PUT,
            put_lpt,
            long_put_address,
            short_put_address,
            init_vol
        );

    start_prank(CheatTarget::One(amm_address), owner);

    assert(amm.get_all_options(call_lpt).len() == 2, 'Wrong amount of calls');
    assert(amm.get_all_options(put_lpt).len() == 2, 'Wrong amount of puts');
}
