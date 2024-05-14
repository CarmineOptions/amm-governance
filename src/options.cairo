use amm_governance::types::FutureOption;
use core::array::SpanTrait;
// Handles adding new options to the AMM and linking them to the liquidity pool.
// I have chosen this perhaps rather complex type layout in expectation of generating the options soon –
// – first generating FutureOption, then generating everything from Pragma data

// This contract (actually just a class) will be library_call'd from the main governance contract
// This add options to the AMM.

use starknet::contract_address::{ContractAddress};

#[starknet::interface]
trait IOptionDeployer<TContractState> {
    fn add_options(
        ref self: TContractState, amm_address: ContractAddress, options: Span<FutureOption>
    );
}


#[starknet::contract]
mod OptionDeployer {
    use amm_governance::constants::{
        OPTION_CALL, OPTION_PUT, TRADE_SIDE_LONG, TRADE_SIDE_SHORT, OPTION_TOKEN_CLASS_HASH
    };
    use amm_governance::types::{FutureOption, OptionSide, OptionType};
    use core::array::{ArrayTrait, SpanTrait};
    use core::option::OptionTrait;
    use core::traits::{Into, TryInto};

    use cubit::f128::types::{Fixed, FixedTrait};
    use amm_governance::traits::{
        IAMMDispatcher, IAMMDispatcherTrait, IOptionTokenDispatcher, IOptionTokenDispatcherTrait
    };
    use starknet::ClassHash;
    use starknet::SyscallResult;

    use starknet::SyscallResultTrait;
    use starknet::class_hash;
    use starknet::contract_address::{ContractAddress};
    use starknet::get_contract_address;
    use starknet::syscalls::deploy_syscall;

    // empty since this will be library-called from governance.
    // true contents of Storage are same as main contract
    #[storage]
    struct Storage {}

    #[constructor]
    fn constructor(ref self: ContractState) {
        assert!(
            false,
            "This class should never be deployed as it's designed to be library called from the governance contract."
        )
    }

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        fn add_option(
            ref self: ContractState, amm_address: ContractAddress, option: @FutureOption
        ) {
            let o = *option;

            // Yes, this 'overflows', but it's expected and wanted.
            let custom_salt: felt252 = 42
                + o.strike_price.mag.into()
                + o.maturity.into()
                + o.option_type
                + o.lptoken_address.into();

            let opt_class_hash: ClassHash = OPTION_TOKEN_CLASS_HASH.try_into().unwrap();
            let mut optoken_long_calldata = array![];
            optoken_long_calldata.append(o.name_long);
            optoken_long_calldata.append('C-OPT');
            optoken_long_calldata.append(amm_address.into());
            optoken_long_calldata.append((*option.quote_token_address).try_into().unwrap());
            optoken_long_calldata.append((*option.base_token_address).try_into().unwrap());
            optoken_long_calldata.append(o.option_type);
            optoken_long_calldata.append(o.strike_price.mag.into());
            optoken_long_calldata.append(o.maturity.into());
            optoken_long_calldata.append(TRADE_SIDE_LONG);
            let deploy_retval = deploy_syscall(
                opt_class_hash, custom_salt + 1, optoken_long_calldata.span(), false
            );
            let (optoken_long_addr, _) = deploy_retval.unwrap_syscall();

            let mut optoken_short_calldata = array![];
            optoken_short_calldata.append(o.name_short);
            optoken_short_calldata.append('C-OPT');
            optoken_short_calldata.append(amm_address.into());
            optoken_short_calldata.append((*option.quote_token_address).try_into().unwrap());
            optoken_short_calldata.append((*option.base_token_address).try_into().unwrap());
            optoken_short_calldata.append(o.option_type);
            optoken_short_calldata.append(o.strike_price.mag.into());
            optoken_short_calldata.append(o.maturity.into());
            optoken_short_calldata.append(TRADE_SIDE_SHORT);
            let deploy_retval = deploy_syscall(
                opt_class_hash, custom_salt + 2, optoken_short_calldata.span(), false
            );
            let (optoken_short_addr, _) = deploy_retval.unwrap_syscall();

            IAMMDispatcher { contract_address: amm_address }
                .add_option_both_sides(
                    o.maturity.try_into().unwrap(),
                    o.strike_price,
                    *option.quote_token_address,
                    *option.base_token_address,
                    o.option_type,
                    o.lptoken_address,
                    optoken_long_addr,
                    optoken_short_addr,
                    o.initial_volatility
                );
        }
    }

    #[abi(embed_v0)]
    impl OptionDeployer of super::IOptionDeployer<ContractState> {
        fn add_options(
            ref self: ContractState, amm_address: ContractAddress, mut options: Span<FutureOption>
        ) {
            // TODO use block hash from block_hash syscall as salt // actually doable with the new syscall
            loop {
                match options.pop_front() {
                    Option::Some(option) => { self.add_option(amm_address, option); },
                    Option::None(()) => { break (); },
                };
            }
        }
    }
}
