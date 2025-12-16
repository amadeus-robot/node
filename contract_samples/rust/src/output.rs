use crate::types::ToBytes;

extern "C" {
    fn import_log(p: i32, l: i32);
    fn import_return(p: i32, l: i32);
}

const BUF_PTR: i32 = 8000;

fn write_buf(data: &[u8]) -> (i32, i32) {
    unsafe {
        let ptr = BUF_PTR as *mut u8;
        for (i, &byte) in data.iter().enumerate() {
            *ptr.add(i) = byte;
        }
        (BUF_PTR, data.len() as i32)
    }
}

pub fn log<T: ToBytes>(m: T) {
    let b = m.to_bytes();
    let (ptr, len) = write_buf(&b);
    unsafe { import_log(ptr, len); }
}

pub fn ret<T: ToBytes>(v: T) {
    let b = v.to_bytes();
    let (ptr, len) = write_buf(&b);
    unsafe { import_return(ptr, len); }
}
