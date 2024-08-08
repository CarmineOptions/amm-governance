use cubit::f128::types::Fixed;
use starknet::ContractAddress;

pub type OptionSide = felt252;
pub type OptionType = felt252;

#[derive(Copy, Drop, Serde)]
pub struct FutureOption {
    pub maturity: u64,
    pub strike_price_offset: Fixed,
    pub option_type: OptionType,
    pub lptoken_address: ContractAddress,
    pub quote_token_address: ContractAddress,
    pub base_token_address: ContractAddress,
    pub initial_volatility: Fixed
}
