use crate::Payload;
use crate::encoding::*;
use alloc::{vec, borrow::Cow, vec::Vec};

pub const BURN_ADDRESS: &[u8] = &[0u8; 48];

pub fn seed() -> Vec<u8> { read_bytes(1100) }
pub fn entry_slot() -> u64 { read_u64(2000) }
pub fn entry_height() -> u64 { read_u64(2010) }
pub fn entry_epoch() -> u64 { read_u64(2020) }
pub fn entry_signer() -> Vec<u8> { read_bytes(2100) }
pub fn entry_prev_hash() -> Vec<u8> { read_bytes(2200) }
pub fn entry_vr() -> Vec<u8> { read_bytes(2300) }
pub fn entry_dr() -> Vec<u8> { read_bytes(2400) }
pub fn tx_nonce() -> u64 { read_u64(3000) }
pub fn tx_signer() -> Vec<u8> { read_bytes(3100) }
pub fn account_current() -> Vec<u8> { read_bytes(4000) }
pub fn account_caller() -> Vec<u8> { read_bytes(4100) }
pub fn account_origin() -> Vec<u8> { read_bytes(4200) }
pub fn attached_symbol() -> Vec<u8> { read_bytes(5000) }
pub fn attached_amount() -> Vec<u8> { read_bytes(5100) }

pub fn get_attachment() -> (bool, (Vec<u8>, Vec<u8>)) {
    unsafe {
        let header = core::ptr::read_unaligned(5000 as *const u32);
        if header == 0 {
            return (false, (Vec::new(), Vec::new()));
        }
    }
    (true, (attached_symbol(), attached_amount()))
}

extern "C" {
    fn import_log(p: *const u8, l: usize);
    fn import_return(p: *const u8, l: usize);
    fn import_call(args_ptr: *const u8, extra_args_ptr: *const u8) -> i32;
}

pub fn log(line: impl Payload) {
    let line_cow = line.to_payload();
    let line_bytes = line_cow.as_ref();
    unsafe { import_log(line_bytes.as_ptr(), line_bytes.len()); }
}

pub fn ret(val: impl Payload) {
    let val_cow = val.to_payload();
    let val_bytes = val_cow.as_ref();
    unsafe { import_return(val_bytes.as_ptr(), val_bytes.len()); }
}

// [Count (u32)] [Ptr1 (u32)] [Len1 (u32)] [Ptr2 (u32)] [Len2 (u32)] ...
fn build_table(items: &[Cow<[u8]>]) -> Vec<u8> {
    let count = items.len();
    let table_size = 4 + (count * 8);
    let mut table = vec![0u8; table_size];

    let count_bytes = (count as u32).to_le_bytes();
    table[0..4].copy_from_slice(&count_bytes);

    for (i, item) in items.iter().enumerate() {
        let bytes = item.as_ref();

        let ptr_val = bytes.as_ptr() as u32;
        let len_val = bytes.len() as u32;

        let offset = 4 + (i * 8);

        table[offset..offset+4].copy_from_slice(&ptr_val.to_le_bytes());
        table[offset+4..offset+8].copy_from_slice(&len_val.to_le_bytes());
    }

    table
}

pub fn call(contract: impl Payload, func: impl Payload, args: &[&dyn Payload], extra_args: &[&dyn Payload]) -> Vec<u8> {
    let mut main_owners = Vec::with_capacity(2 + args.len());

    main_owners.push(contract.to_payload());
    main_owners.push(func.to_payload());
    for arg in args {
        main_owners.push(arg.to_payload());
    }

    let main_table = build_table(&main_owners);

    let (_extra_owners, extra_ptr) = if extra_args.is_empty() {
        (Vec::new(), core::ptr::null())
    } else {
        let mut owners = Vec::with_capacity(extra_args.len());
        for arg in extra_args {
            owners.push(arg.to_payload());
        }
        let t = build_table(&owners);
        let p = t.as_ptr();
        (owners, p)
    };

    unsafe {
        let error_ptr = import_call(main_table.as_ptr(), extra_ptr);
        read_bytes(error_ptr)
    }
}

#[macro_export]
macro_rules! call {
    ($contract:expr, $func:expr, [ $( $arg:expr ),* ], [ $( $earg:expr ),* ]) => {
        {
            let args_slice: &[&dyn $crate::Payload] = &[ $( &$arg ),* ];
            let extra_slice: &[&dyn $crate::Payload] = &[ $( &$earg ),* ];
            $crate::call($contract, $func, args_slice, extra_slice)
        }
    };

    ($contract:expr, $func:expr, [ $( $arg:expr ),* ]) => {
        {
            let args_slice: &[&dyn $crate::Payload] = &[ $( &$arg ),* ];
            let empty_extra: &[&dyn $crate::Payload] = &[];
            $crate::call($contract, $func, args_slice, empty_extra)
        }
    };
}
