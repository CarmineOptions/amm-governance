use amm::pragma::get_pragma_median_price;
use amm_governance::types::FutureOption;
use amm_governance::types::OptionType;
use core::array::SpanTrait;
use cubit::f128::types::fixed::{Fixed, FixedTrait};
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

#[derive(Copy, Drop, Serde)]
struct PreparedOption {
    name_long: felt252,
    name_short: felt252,
    maturity: u64,
    strike_price: Fixed,
    option_type: OptionType,
    lptoken_address: ContractAddress,
    quote_token_address: ContractAddress,
    base_token_address: ContractAddress,
    initial_volatility: Fixed
}


#[starknet::contract]
mod OptionDeployer {
    use amm_governance::constants::{
        OPTION_CALL, OPTION_PUT, TRADE_SIDE_LONG, TRADE_SIDE_SHORT, OPTION_TOKEN_CLASS_HASH
    };
    use amm_governance::traits::{
        IAMMDispatcher, IAMMDispatcherTrait, IOptionTokenDispatcher, IOptionTokenDispatcherTrait
    };
    use amm_governance::types::{FutureOption, OptionSide, OptionType};
    use core::array::{ArrayTrait, SpanTrait};
    use core::option::OptionTrait;
    use core::traits::{Into, TryInto};

    use cubit::f128::types::{Fixed, FixedTrait};
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
            ref self: ContractState, amm_address: ContractAddress, option: @PreparedOption
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

        fn get_name(option: @FutureOption) -> (felt252, felt252) {
            ('name long', 'namshort')
        }

        fn get_rounding_unit(
            quote_token_address: ContractAddress, base_token_address: ContractAddress
        ) -> Fixed {
            FixedTrait::ONE() * 1000
        }
    }

    #[abi(embed_v0)]
    impl OptionDeployer of super::IOptionDeployer<ContractState> {
        fn add_options(
            ref self: ContractState, amm_address: ContractAddress, options: Span<FutureOption>
        ) {
            let mut prepared_options = ArrayTrait::new();

            loop {
                match options.pop_front() {
                    Option::Some(option) => {
                        let spot_price = get_pragma_median_price(
                            *option.quote_token_address, *option.base_token_address
                        );
                        let strike_price = spot_price
                            * (FixedTrait::ONE() + option.strike_price_offset);
                        let rounding_unit = self
                            .get_rounding_unit(
                                option.quote_token_address, option.base_token_address
                            );
                        let strike_price_rounded = if (strike_price % rounding_unit) > 50 {
                            strike_price + (rounding_unit - strike_price % rounding_unit)
                        } else {
                            strike_price - (strike_price % rounding_unit)
                        };

                        let (name_long, name_short) = self.get_name(@option);
                        let prepared_option = super::PreparedOption {
                            name_long: name_long,
                            name_short: name_short,
                            maturity: *option.maturity,
                            strike_price: strike_price,
                            option_type: option.option_type,
                            lptoken_address: *option.lptoken_address,
                            quote_token_address: *option.quote_token_address,
                            base_token_address: *option.base_token_address,
                            initial_volatility: option.initial_volatility
                        };

                        prepared_options.append(prepared_option);
                    },
                    Option::None(()) => { break (); },
                };
            };

            let mut prepared_options_span = prepared_options.span();
            loop {
                match prepared_options_span.pop_front() {
                    Option::Some(prepared_option) => {
                        self.add_option(amm_address, prepared_option);
                    },
                    Option::None(()) => { break (); },
                };
            }
        }
    }
}
