#![no_std]
extern crate alloc;

pub mod context;
pub mod storage;
pub mod output;
pub mod call;
pub mod encoding;
pub mod types;

pub use context::*;
pub use storage::*;
pub use output::*;
pub use call::*;
pub use encoding::*;
pub use types::*;

use core::panic::PanicInfo;

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
            $crate::output::log($msg);
            core::arch::wasm32::unreachable();
        }
    };
}
