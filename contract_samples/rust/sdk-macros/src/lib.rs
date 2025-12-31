use proc_macro::TokenStream;
use quote::quote;
use syn::{parse_macro_input, FnArg, ItemFn, ReturnType, Type};

#[proc_macro_attribute]
pub fn contract(_attr: TokenStream, item: TokenStream) -> TokenStream {
    let input = parse_macro_input!(item as ItemFn);
    let vis = &input.vis;
    let fn_name = &input.sig.ident;
    let impl_fn_name = syn::Ident::new(&format!("{}_impl", fn_name), fn_name.span());
    let inputs = &input.sig.inputs;
    let output = &input.sig.output;
    let block = &input.block;
    let attrs = &input.attrs;
    let has_return = !matches!(output, ReturnType::Default);

    let mut param_count = 0;
    let mut wrapper_params = quote!{};
    let mut deserializations = quote!{};
    let mut call_args = quote!{};

    for arg in inputs.iter() {
        if let FnArg::Typed(pat_type) = arg {
            let param_name = &pat_type.pat;
            let ptr_name = syn::Ident::new(&format!("arg{}_ptr", param_count), fn_name.span());

            let deserialize_fn = match &*pat_type.ty {
                Type::Path(tp) if quote!(#tp).to_string().contains("String") => quote!(read_string),
                _ => quote!(read_bytes),
            };

            if param_count > 0 {
                wrapper_params.extend(quote!(, #ptr_name: i32));
                call_args.extend(quote!(, #param_name));
            } else {
                wrapper_params.extend(quote!(#ptr_name: i32));
                call_args.extend(quote!(#param_name));
            }

            deserializations.extend(quote! { let #param_name = #deserialize_fn(#ptr_name); });
            param_count += 1;
        }
    }

    let wrapper_sig = if param_count == 0 {
        quote!(#[no_mangle] pub extern "C" fn #fn_name())
    } else {
        quote!(#[no_mangle] pub extern "C" fn #fn_name(#wrapper_params))
    };

    let wrapper_call = if has_return {
        quote!(ret(#impl_fn_name(#call_args));)
    } else {
        quote!(#impl_fn_name(#call_args);)
    };

    TokenStream::from(quote! {
        #wrapper_sig { #deserializations #wrapper_call }
        #(#attrs)* #vis fn #impl_fn_name(#inputs) #output #block
    })
}
