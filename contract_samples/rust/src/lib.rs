#![no_std]
extern crate alloc;

pub mod context;
pub mod storage;
pub mod encoding;

pub use context::*;
pub use storage::*;
pub use encoding::*;

use core::panic::PanicInfo;

use alloc::{borrow::Cow, vec::Vec, string::String, string::ToString};


#[cfg(not(test))]
#[panic_handler]
fn panic(_: &PanicInfo) -> ! {
    loop {}
}

#[global_allocator]
static ALLOC: dlmalloc::GlobalDlmalloc = dlmalloc::GlobalDlmalloc;

#[macro_export]
macro_rules! assert {
    ($cond:expr, $msg:expr) => {
        if !$cond {
            $crate::context::log($msg);

            #[cfg(target_arch = "wasm32")]
            core::arch::wasm32::unreachable();
        }
    };
}

#[macro_export]
macro_rules! abort {
    ($msg:expr) => {
        {
            $crate::context::log($msg);

            #[cfg(target_arch = "wasm32")]
            core::arch::wasm32::unreachable();
        }
    };
}

#[macro_export]
macro_rules! b {
    ( $( $x:expr ),* ) => {
        {
            let mut temp_vec = alloc::vec::Vec::new();
            $(
                temp_vec.extend_from_slice($x.as_ref());
            )*
            temp_vec
        }
    };
}

macro_rules! impl_payload_for_ints {
    ( $($t:ty),* ) => {
        $(
            impl Payload for $t {
                fn to_payload<'a>(&'a self) -> Cow<'a, [u8]> {
                    Cow::Owned(self.to_string().into_bytes())
                }
            }
        )*
    };
}

pub trait Payload {
    fn to_payload<'a>(&'a self) -> Cow<'a, [u8]>;
}

impl Payload for &str {
    fn to_payload<'a>(&'a self) -> Cow<'a, [u8]> { Cow::Borrowed(self.as_bytes()) }
}

impl Payload for String {
    fn to_payload<'a>(&'a self) -> Cow<'a, [u8]> { Cow::Borrowed(self.as_bytes()) }
}

impl Payload for &[u8] {
    fn to_payload<'a>(&'a self) -> Cow<'a, [u8]> { Cow::Borrowed(self) }
}

impl Payload for Vec<u8> {
    fn to_payload<'a>(&'a self) -> Cow<'a, [u8]> { Cow::Borrowed(self.as_slice()) }
}

impl Payload for &alloc::vec::Vec<u8> {
    fn to_payload<'a>(&'a self) -> alloc::borrow::Cow<'a, [u8]> {
        alloc::borrow::Cow::Borrowed(self.as_slice())
    }
}

impl_payload_for_ints!(u8, u16, u32, u64, u128, usize);
impl_payload_for_ints!(i8, i16, i32, i64, i128, isize);
