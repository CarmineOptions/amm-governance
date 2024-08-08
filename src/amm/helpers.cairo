use core::integer;
use integer::U128DivRem;

fn pow(a: u128, b: u128) -> u128 {
    let mut x: u128 = a;
    let mut n = b;

    if n == 0 {
        // 0**0 is undefined
        assert(x > 0, 'Undefined pow action');

        return 1;
    }

    let mut y = 1;

    loop {
        if n <= 1 {
            break;
        }

        let (div, rem) = integer::u128_safe_divmod(n, two);

        if rem == 1 {
            y = x * y;
        }

        x = x * x;
        n = div;
    };
    x * y
}