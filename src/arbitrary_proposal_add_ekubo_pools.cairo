use starknet::ClassHash;

use starknet::ContractAddress;

#[starknet::interface]
trait IArbitraryProposalAddOptions<TContractState> {
    fn execute_arbitrary_proposal(ref self: TContractState);
}


#[starknet::contract]
pub mod ArbitraryProposalAddEkuboPools {
    use amm_governance::constants::{LP_TOKEN_CLASS_HASH, AMM_CLASS_HASH, OPTION_CALL, OPTION_PUT};
    use amm_governance::traits::{
        IAMMDispatcher, IAMMDispatcherTrait, IOptionTokenDispatcher, IOptionTokenDispatcherTrait
    };

    use core::integer::BoundedInt;
    use core::traits::{Into, TryInto};

    use cubit::f128::types::{Fixed, FixedTrait};
    use starknet::ClassHash;
    use starknet::ContractAddress;
    use starknet::SyscallResult;
    use starknet::SyscallResultTrait;
    use starknet::syscalls::deploy_syscall;


    #[storage]
    struct Storage {}

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {}

    #[constructor]
    fn constructor(ref self: ContractState) {}


    #[abi(embed_v0)]
    impl ArbitraryProposalAddOptions of super::IArbitraryProposalAddOptions<ContractState> {
        fn execute_arbitrary_proposal(ref self: ContractState) {
            let AMM_ADDRESS: ContractAddress =
                0x047472e6755afc57ada9550b6a3ac93129cc4b5f98f51c73e0644d129fd208d9
                .try_into()
                .unwrap();

            let USDC_TOKEN: ContractAddress =
                0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8
                .try_into()
                .unwrap();

            let EKUBO_TOKEN: ContractAddress =
                0x075afe6402ad5a5c20dd25e10ec3b3986acaa647b77e4ae24b0cbc9a54a27a87
                .try_into()
                .unwrap();

            // Create amm dispatcher
            let amm = IAMMDispatcher { contract_address: AMM_ADDRESS };

            // Upgrade AMM to newest class hash
            amm.upgrade(AMM_CLASS_HASH.try_into().unwrap());

            // Deploy new lp tokens
            let lptoken_class = LP_TOKEN_CLASS_HASH.try_into().unwrap();

            // Ekubo Call Calldata
            let mut ekubo_call_lpt_calldata = array![];
            ekubo_call_lpt_calldata.append('Carmine EKUBO/USDC call pool'); // Name 
            ekubo_call_lpt_calldata.append('C-EKUBOUSDC-C'); //  Symbol
            ekubo_call_lpt_calldata.append(AMM_ADDRESS.into()); // Owner

            // Ekubo Put Calldata
            let mut ekubo_put_lpt_calldata = array![];
            ekubo_put_lpt_calldata.append('Carmine EKUBO/USDC put pool'); // Name 
            ekubo_put_lpt_calldata.append('C-EKUBOUSDC-P'); //  Symbol
            ekubo_put_lpt_calldata.append(AMM_ADDRESS.into()); // Owner

            // Call deploy
            let call_deploy_retval = deploy_syscall(
                lptoken_class, 'ekubousdc call', ekubo_call_lpt_calldata.span(), false
            );
            let (call_lpt_address, _) = call_deploy_retval.unwrap_syscall();
            // Put deploy
            let put_deploy_retval = deploy_syscall(
                lptoken_class, 'ekubousdc put', ekubo_put_lpt_calldata.span(), false
            );
            let (put_lpt_address, _) = put_deploy_retval.unwrap_syscall();

            // Add the lptokens to the AMM
            let call_voladjspd = FixedTrait::new_unscaled(10_000, false);
            let put_voladjspd = FixedTrait::new_unscaled(50_000, false);

            // Call
            amm
                .add_lptoken(
                    USDC_TOKEN,
                    EKUBO_TOKEN,
                    OPTION_CALL,
                    call_lpt_address,
                    call_voladjspd,
                    BoundedInt::<u256>::max()
                );

            // Put
            amm
                .add_lptoken(
                    USDC_TOKEN,
                    EKUBO_TOKEN,
                    OPTION_PUT,
                    put_lpt_address,
                    put_voladjspd,
                    BoundedInt::<u256>::max()
                );
        }
    }
}
