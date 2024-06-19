use starknet::ContractAddress;

// This component should not be used along with delegation, as when the tokens are unstaked, they are not automatically undelegated.
// TODO add later unstaking for team&investors

#[starknet::interface]
pub trait IStaking<TContractState> {
    fn stake(ref self: TContractState, length: u64, amount: u128) -> u32; // returns stake ID
    fn unstake(ref self: TContractState, id: u32);
    fn unstake_airdrop(ref self: TContractState);

    fn set_curve_point(ref self: TContractState, length: u64, conversion_rate: u16);
    fn set_floating_token_address(ref self: TContractState, address: ContractAddress);
    fn initialize_floating_token_address(ref self: TContractState);

    fn get_floating_token_address(self: @TContractState) -> ContractAddress;
    fn get_stake(self: @TContractState, address: ContractAddress, stake_id: u32) -> staking::Stake;
    fn get_total_voting_power(self: @TContractState, address: ContractAddress) -> u128;
    fn get_adjusted_voting_power(self: @TContractState, address: ContractAddress) -> u128;
}

#[starknet::component]
pub(crate) mod staking {
    use amm_governance::constants::UNLOCK_DATE;
    use core::array::SpanTrait;
    use core::option::OptionTrait;
    use core::traits::Into;
    use core::zeroable::NonZero;
    use konoha::traits::{
        get_governance_token_address_self, IERC20Dispatcher, IERC20DispatcherTrait
    };
    use starknet::{
        ContractAddress, get_block_timestamp, get_caller_address, get_contract_address,
        storage_access::StorePacking
    };

    #[derive(Copy, Drop, Serde)]
    pub(crate) struct Stake {
        amount_staked: u128,
        amount_voting_token: u128,
        start_date: u64,
        length: u64,
        withdrawn: bool
    }

    const TWO_POW_32: u128 = 0x100000000;
    const TWO_POW_64: u128 = 0x10000000000000000;
    const TWO_POW_128: felt252 = 0x100000000000000000000000000000000;
    const TWO_POW_192: felt252 = 0x1000000000000000000000000000000000000000000000000;

    impl StakeStorePacking of StorePacking<Stake, (felt252, felt252)> {
        fn pack(value: Stake) -> (felt252, felt252) {
            let fst = value.amount_staked.into() + value.start_date.into() * TWO_POW_128;
            let snd = value.amount_voting_token.into()
                + value.length.into() * TWO_POW_128
                + value.withdrawn.into() * TWO_POW_192;
            (fst.into(), snd.into())
        }

        fn unpack(value: (felt252, felt252)) -> Stake {
            let (fst, snd) = value;
            let fst: u256 = fst.into();
            let amount_staked = fst.low;
            let start_date = fst.high;
            let snd: u256 = snd.into();
            let amount_voting_token = snd.low;
            let two_pow_64: NonZero<u128> = TWO_POW_64.try_into().unwrap();
            let (withdrawn, length) = DivRem::div_rem(snd.high, two_pow_64);
            assert(withdrawn == 0 || withdrawn == 1, 'wrong val: withdrawn');
            Stake {
                amount_staked,
                amount_voting_token,
                start_date: start_date.try_into().expect('unwrap fail start_date'),
                length: length.try_into().expect('unpack fail length'),
                withdrawn: withdrawn != 0
            }
        }
    }

    #[storage]
    struct Storage {
        stake: LegacyMap::<
            (ContractAddress, u32), Stake
        >, // STAKE(address, ID) → Stake{amount staked, amount voting token, start date, length of stake, withdrawn}
        curve: LegacyMap::<
            u64, u16
        >, // length of stake > CRM to veCRM conversion rate (conversion rate is expressed in % – 2:1 is 200)
        floating_token_address: ContractAddress
    }

    #[derive(starknet::Event, Drop)]
    struct Staked {
        user: ContractAddress,
        stake_id: u32,
        amount: u128,
        amount_voting_token: u128,
        start_date: u64,
        length: u64
    }

    #[derive(starknet::Event, Drop)]
    struct Unstaked {
        user: ContractAddress,
        stake_id: u32,
        amount: u128,
        amount_voting_token: u128,
        start_date: u64,
        length: u64
    }

    #[derive(starknet::Event, Drop)]
    struct UnstakedAirdrop {
        user: ContractAddress,
        amount: u128
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    pub(crate) enum Event {
        Staked: Staked,
        Unstaked: Unstaked,
        UnstakedAirdrop: UnstakedAirdrop
    }

    #[inline(always)]
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
        ];
        @arr.span()
    }

    #[inline(always)]
    fn get_investor_addresses() -> @Span<felt252> {
        let arr = array![
            0x05a4523982b437aadd1b5109b6618c46f7b1c42f5f9e7de1a3b84091f87d411b
            // TODO add multisig
        ];
        @arr.span()
    }

    fn is_team(potential_team_member_address: ContractAddress) -> bool {
        let potential_address: felt252 = potential_team_member_address.into();
        let mut team_addresses = *get_team_addresses();
        loop {
            match team_addresses.pop_front() {
                Option::Some(addr) => { if (*addr == potential_address) {
                    break true;
                } },
                Option::None(_) => { break false; }
            }
        }
    }

    fn is_investor(potential_investor_address: ContractAddress) -> bool {
        let potential_address: felt252 = potential_investor_address.into();
        let mut investor_addresses = *get_investor_addresses();
        loop {
            match investor_addresses.pop_front() {
                Option::Some(addr) => { if (*addr == potential_address) {
                    break true;
                } },
                Option::None(_) => { break false; }
            }
        }
    }

    #[embeddable_as(StakingImpl)]
    impl Staking<
        TContractState, +HasComponent<TContractState>,
    > of super::IStaking<ComponentState<TContractState>> {
        fn stake(ref self: ComponentState<TContractState>, length: u64, amount: u128) -> u32 {
            let caller = get_caller_address();

            assert(amount != 0, 'amount to stake is zero');
            let conversion_rate: u16 = self.curve.read(length);
            assert(conversion_rate != 0, 'unsupported stake length');

            let floating_token = IERC20Dispatcher {
                contract_address: self.floating_token_address.read()
            };
            floating_token.transfer_from(caller, get_contract_address(), amount.into());

            let amount_voting_token = (amount * conversion_rate.into()) / 100;
            let free_id = self.get_free_stake_id(caller);

            self
                .stake
                .write(
                    (caller, free_id),
                    Stake {
                        amount_staked: amount,
                        amount_voting_token,
                        start_date: get_block_timestamp(),
                        length,
                        withdrawn: false
                    }
                );

            let voting_token = IERC20Dispatcher {
                contract_address: get_governance_token_address_self()
            };
            voting_token.mint(caller, amount_voting_token.into());
            self
                .emit(
                    Staked {
                        user: caller,
                        stake_id: free_id,
                        amount,
                        amount_voting_token,
                        start_date: get_block_timestamp(),
                        length
                    }
                );
            free_id
        }

        fn unstake(ref self: ComponentState<TContractState>, id: u32) {
            let caller = get_caller_address();
            let res: Stake = self.stake.read((caller, id));

            assert(!res.withdrawn, 'stake withdrawn already');

            assert(res.amount_staked != 0, 'no stake found, check stake id');
            let unlock_date = res.start_date + res.length;
            assert(get_block_timestamp() > unlock_date, 'unlock time not yet reached');

            let voting_token = IERC20Dispatcher {
                contract_address: get_governance_token_address_self()
            };
            voting_token.burn(caller, res.amount_voting_token.into());

            let floating_token = IERC20Dispatcher {
                contract_address: self.floating_token_address.read()
            };
            // user gets back the same amount of tokens they put in.
            // the payoff is in holding voting tokens, which make the user eligible for distributions of protocol revenue
            // works for tokens with fixed max float
            floating_token.transfer(caller, res.amount_staked.into());
            self
                .stake
                .write(
                    (caller, id),
                    Stake {
                        amount_staked: res.amount_staked,
                        amount_voting_token: res.amount_voting_token,
                        start_date: res.start_date,
                        length: res.length,
                        withdrawn: true
                    }
                );
            self
                .emit(
                    Unstaked {
                        user: caller,
                        stake_id: id,
                        amount: res.amount_staked,
                        amount_voting_token: res.amount_voting_token,
                        start_date: res.start_date,
                        length: res.length
                    }
                );
        }

        fn unstake_airdrop(ref self: ComponentState<TContractState>) {
            let caller = get_caller_address();
            if (is_team(caller) || is_investor(caller)) {
                assert(get_block_timestamp() > UNLOCK_DATE, 'tokens not yet unlocked');
            }

            let total_staked = self.get_total_staked_accounted(caller); // manually staked tokens
            let voting_token = IERC20Dispatcher {
                contract_address: get_governance_token_address_self()
            };
            let voting_token_balance = voting_token.balance_of(caller).try_into().unwrap();
            assert(
                voting_token_balance > total_staked, 'no extra tokens to unstake'
            ); // potentially unnecessary (underflow checks), but provides for a better error message
            let to_unstake = voting_token_balance - total_staked;

            // burn voting token, mint floating token
            let voting_token = IERC20Dispatcher {
                contract_address: get_governance_token_address_self()
            };
            voting_token.burn(caller, to_unstake.into());
            let floating_token = IERC20Dispatcher {
                contract_address: self.floating_token_address.read()
            };
            floating_token.transfer(caller, to_unstake.into());
            self.emit(UnstakedAirdrop { user: caller, amount: to_unstake });
        }

        fn set_curve_point(
            ref self: ComponentState<TContractState>, length: u64, conversion_rate: u16
        ) {
            let caller = get_caller_address();
            let myaddr = get_contract_address();
            assert(caller == myaddr, 'can only call from proposal');
            self.curve.write(length, conversion_rate);
        }

        fn set_floating_token_address(
            ref self: ComponentState<TContractState>, address: ContractAddress
        ) {
            let caller = get_caller_address();
            let myaddr = get_contract_address();
            assert(caller == myaddr, 'can only call from proposal');
            self.floating_token_address.write(address);
        }

        fn get_floating_token_address(self: @ComponentState<TContractState>) -> ContractAddress {
            self.floating_token_address.read()
        }

        fn initialize_floating_token_address(ref self: ComponentState<TContractState>) {
            let curr = self.floating_token_address.read();
            assert(curr.into() == 0, 'floating token already init');
            let default_address: ContractAddress =
                0x71cc3fbda6eb62d60c57c84eb995338fcb74a31dfb58e64f88185d1ac8ae8b8
                .try_into()
                .unwrap(); // TODO fix
            self.floating_token_address.write(default_address);
        }

        fn get_stake(
            self: @ComponentState<TContractState>, address: ContractAddress, stake_id: u32
        ) -> Stake {
            self.stake.read((address, stake_id))
        }

        // returns total voting power, NOT adjusted for whether it's team or not
        // counts only non-expired stakes, NOT airdropped tokens
        fn get_total_voting_power(
            self: @ComponentState<TContractState>, address: ContractAddress
        ) -> u128 {
            let mut id = 0;
            let mut acc = 0;
            let currtime = get_block_timestamp();
            loop {
                let res: Stake = self.stake.read((address, id));
                if (res.amount_voting_token == 0) {
                    break acc;
                }
                id += 1;
                let not_expired: bool = currtime < (res.length + res.start_date);
                if (not_expired) {
                    acc += res.amount_voting_token;
                }
            }
        }

        // returns voting power adjusted for whether the person is team or not
        fn get_adjusted_voting_power(
            self: @ComponentState<TContractState>, address: ContractAddress
        ) -> u128 {
            let nonadjusted_voting_power = self.get_total_voting_power(address);
            let investor = is_investor(address);
            let team = is_team(address);
            if (!investor && !team) {
                return nonadjusted_voting_power;
            }
            let total_supply: u128 = IERC20Dispatcher {
                contract_address: get_governance_token_address_self()
            }
                .total_supply()
                .try_into()
                .unwrap();
            let total_team = self.get_total_group_voting_power(false);
            let total_investor = self.get_total_group_voting_power(true);
            let max_group_supply = ((total_supply-total_team)-total_investor) / 2;
            let total_group = if investor { total_investor } else { total_team };
            if (total_group < max_group_supply) {
                return nonadjusted_voting_power;
            }
            let adj_factor = (TWO_POW_32 * max_group_supply) / total_group;
            (adj_factor * nonadjusted_voting_power) / TWO_POW_32
        }
    }

    #[generate_trait]
    impl InternalImpl<
        TContractState, +HasComponent<TContractState>
    > of InternalTrait<TContractState> {
        fn get_free_stake_id(
            self: @ComponentState<TContractState>, address: ContractAddress
        ) -> u32 {
            self._get_free_stake_id(address, 0)
        }

        fn _get_free_stake_id(
            self: @ComponentState<TContractState>, address: ContractAddress, id: u32
        ) -> u32 {
            let res: Stake = self.stake.read((address, id));
            if (res.amount_staked == 0) {
                id
            } else {
                self._get_free_stake_id(address, id + 1)
            }
        }

        fn get_total_staked_accounted(
            self: @ComponentState<TContractState>, address: ContractAddress
        ) -> u128 {
            let mut id = 0;
            let mut acc = 0;
            loop {
                let res: Stake = self.stake.read((address, id));
                if (res.amount_voting_token == 0) {
                    break acc;
                }
                id += 1;
                if (!res.withdrawn) {
                    acc += res.amount_voting_token;
                }
            }
        }

        fn get_total_group_voting_power(self: @ComponentState<TContractState>, investors: bool) -> u128 {
            let mut total: u128 = 0;
            let mut addresses = if investors {*get_investor_addresses()} else {*get_team_addresses()};
            loop {
                match addresses.pop_front() {
                    Option::Some(addr) => {
                        total += self.get_total_voting_power((*addr).try_into().unwrap());
                    },
                    Option::None(_) => { break total; }
                }
            }
        }
    }
}
