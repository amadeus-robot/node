use rustler::{Atom, Binary, Env, Error, NewBinary, NifResult, Term};

rustler::atoms! {
    signer,
    tx,
    action,
    contract,
    function,
    args,
    nonce,
    hash,
}
const ZERO: &[u8] = &[0u8];
// 20 digits is enough for u64::MAX (18,446,744,073,709,551,615)
const NONCE_LEN: usize = 20;

#[inline(always)]
pub fn create_filter_key(parts: &[&[u8]]) -> [u8; 16] {
    let mut hasher = blake3::Hasher::new();
    for part in parts {
        hasher.update(part);
    }
    let mut output = [0u8; 16];
    hasher.finalize_xof().fill(&mut output);
    output
}

#[inline(always)]
fn write_padded_nonce(buffer: &mut [u8], mut n: u64) {
    for b in buffer.iter_mut() { *b = b'0'; }

    let mut i = NONCE_LEN - 1;
    while n > 0 {
        buffer[i] = b'0' + (n % 10) as u8;
        n /= 10;
        if i == 0 { break; }
        i -= 1;
    }
}

pub fn build_tx_hashfilters<'a>(env: Env<'a>, txus: Vec<Term<'a>>) -> NifResult<Vec<(Binary<'a>, Binary<'a>)>> {
    let mut all_filters = Vec::with_capacity(txus.len() * 8);
    let mut nonce_str_buf = [b'0'; NONCE_LEN];

    for txu in txus {

        let tx_hash: Binary = txu.map_get(hash())?.decode()?;

        let tx = txu.map_get(tx())?;

        let nonce_u64: u64 = tx.map_get(nonce())?.decode()?;
        write_padded_nonce(&mut nonce_str_buf, nonce_u64);

        let signer_bin: Binary = tx.map_get(signer())?.decode()?;
        let signer = signer_bin.as_slice();

        let action_map = tx.map_get(action())?;
        let contract_bin: Binary = action_map.map_get(contract())?.decode()?;
        let contract = contract_bin.as_slice();
        let function_bin: Binary = action_map.map_get(function())?.decode()?;
        let func = function_bin.as_slice();

        let args_list: Vec<Term> = action_map.map_get(args())?.decode()?;
        let arg0 = if let Some(first_arg) = args_list.first() {
            let b: Binary = first_arg.decode()?;
            b.as_slice()
        } else {
            ZERO
        };

        const BIN_SIZE: usize = 16 + 1 + NONCE_LEN;

        let mut push_key = |parts: &[&[u8]]| {
            let raw_hash = create_filter_key(parts);

            let mut bin = NewBinary::new(env, BIN_SIZE);
            let s = bin.as_mut_slice();

            s[0..16].copy_from_slice(&raw_hash);
            s[16] = b':';
            s[17..].copy_from_slice(&nonce_str_buf);

            all_filters.push((bin.into(), tx_hash));
        };

        push_key(&[signer, ZERO, ZERO, ZERO]);
        push_key(&[ZERO, arg0, ZERO, ZERO]);
        push_key(&[signer, arg0, ZERO, ZERO]);
        push_key(&[signer, ZERO, contract, ZERO]);
        push_key(&[signer, ZERO, contract, func]);
        push_key(&[ZERO, arg0, contract, ZERO]);
        push_key(&[ZERO, arg0, contract, func]);
        push_key(&[signer, arg0, contract, func]);
    }

    Ok(all_filters)
}
