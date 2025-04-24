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


/// Struct containing fee configuration for a market
/// Both fees are specified in basis points (bps)
#[derive(Copy, Drop, Serde, Debug, Eq, PartialEq)]
pub struct Fees {
    pub taker_fee_bps: u16,
    pub maker_fee_bps: u16
}

#[derive(Copy, Drop, Serde, Debug, Eq, PartialEq)]
pub struct MarketConfig {
    /// token representing the base asset of the market.
    pub base_token: ContractAddress,
    /// token representing the quote asset of the market.
    pub quote_token: ContractAddress,
    /// The minimum price increment (must divide the order price).
    pub tick_size: u256,
    /// The minimum order size increment (must divide the order amount).
    pub lot_size: u256,
    /// Whether this market currently allows trading
    pub trading_enabled: bool,
    /// Fees config
    pub fees: Fees
}
