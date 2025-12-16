use alloc::vec::Vec;
use crate::types::ToBytes;

extern "C" {
    fn import_call(ap: i32, ep: i32) -> i32;
}

fn read_bytes(p: i32) -> Vec<u8> {
    unsafe {
        let len = *(p as *const i32);
        if len == -1 { return Vec::new(); }
        let data = (p + 4) as *const u8;
        core::slice::from_raw_parts(data, len as usize).to_vec()
    }
}

const CALL_BUF: i32 = 7000;

pub fn call<C: ToBytes, F: ToBytes, A: ToBytes>(c: C, f: F, args: &[A]) -> Vec<u8> {
    call_with_extra(c, f, args, &[] as &[&[u8]])
}

pub fn call_with_extra<C: ToBytes, F: ToBytes, A: ToBytes, E: ToBytes>(
    c: C, f: F, args: &[A], extra: &[E]
) -> Vec<u8> {
    let cb = c.to_bytes();
    let fb = f.to_bytes();

    let mut ba = Vec::new();
    ba.push(cb);
    ba.push(fb);
    for a in args { ba.push(a.to_bytes()); }

    let mut offset = CALL_BUF + 4;
    unsafe {
        let tbl_ptr = CALL_BUF as *mut u8;
        *(tbl_ptr as *mut i32) = (2 + args.len()) as i32;

        let mut ptrs = Vec::new();
        for b in &ba {
            for (i, &byte) in b.iter().enumerate() {
                *tbl_ptr.add(offset as usize + i) = byte;
            }
            ptrs.push(CALL_BUF + offset);
            offset += b.len() as i32;
        }

        for (i, ptr) in ptrs.iter().enumerate() {
            let tbl_offset = 4 + (i * 8);
            *((tbl_ptr.add(tbl_offset)) as *mut i32) = *ptr;
            *((tbl_ptr.add(tbl_offset + 4)) as *mut i32) = ba[i].len() as i32;
        }

        read_bytes(import_call(CALL_BUF, 0))
    }
}
