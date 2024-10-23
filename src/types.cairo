use cubit::f128::types::Fixed;
use starknet::ContractAddress;

pub type OptionSide = felt252;
pub type OptionType = felt252;

// TODO add auto generation of FutureOption structs once string contacenation exists
#[derive(Copy, Drop, Serde)]
pub struct FutureOption {
    pub name_long: felt252,
    pub name_short: felt252,
    pub maturity: u64,
    pub strike_price: Fixed,
    pub option_type: OptionType,
    pub lptoken_address: ContractAddress,
    pub quote_token_address: ContractAddress,
    pub base_token_address: ContractAddress,
    pub initial_volatility: Fixed
}

#[derive(Copy, Drop, Serde)]
pub struct Option_ {
    pub option_side: OptionSide,
    pub maturity: u64,
    pub strike_price: Fixed,
    pub quote_token_address: ContractAddress,
    pub base_token_address: ContractAddress,
    pub option_type: OptionType
}

#[derive(Copy, Drop, Serde)]
pub struct Pool {
    pub quote_token_address: ContractAddress,
    pub base_token_address: ContractAddress,
    pub option_type: OptionType,
}
