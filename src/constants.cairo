pub const OPTION_CALL: felt252 = 0;
pub const OPTION_PUT: felt252 = 1;
pub const TRADE_SIDE_LONG: felt252 = 0;
pub const TRADE_SIDE_SHORT: felt252 = 1;

// CLASS HASHES

// corresponds to commit 7b7db57419fdb25b93621fbea6a845005f7725d0 in protocol-cairo1 repo, branch audit-fixes
pub const LP_TOKEN_CLASS_HASH: felt252 =
    0x06d15bc862ce48375ec98fea84d76ca67b7ac5978d80c848fa5496108783fbc2;
pub const AMM_CLASS_HASH: felt252 =
    0x0217863fdd0f365bff051411a5a1c792bb24e21c80f6bb4d297cef5ceb6d22f5;
pub const OPTION_TOKEN_CLASS_HASH: felt252 =
    0x07fc0b6ecc96a698cdac8c4ae447816d73bffdd9603faacffc0a8047149d02ed;

pub const UNLOCK_DATE: u64 = 1719838800; // Mon Jul 01 2024 13:00:00 GMT+0000
