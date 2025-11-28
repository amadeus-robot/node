use crate::{
    consensus, BoundColumnFamily, MultiThreaded, Transaction, TransactionDB, TransactionOptions, WriteOptions
};

use crate::consensus::bic::protocol;
use crate::consensus::{bintree, consensus_kv};
use crate::consensus::consensus_muts;
use std::clone;
use std::collections::HashMap;
use std::panic::panic_any;

pub struct CallerEnv {
    pub readonly: bool,
    pub seed: Vec<u8>,
    pub seedf64: f64,
    pub entry_signer: [u8; 48],
    pub entry_prev_hash: [u8; 32],
    pub entry_slot: u64,
    pub entry_prev_slot: u64,
    pub entry_height: u64,
    pub entry_epoch: u64,
    pub entry_vr: [u8; 96],
    pub entry_vr_b3: [u8; 32],
    pub entry_dr: [u8; 32],
    pub tx_index: u64,
    pub tx_signer: [u8; 48],
    pub tx_nonce: u64,
    pub tx_hash: [u8; 32],
    pub account_origin: Vec<u8>,
    pub account_caller: Vec<u8>,
    pub account_current: Vec<u8>,
    pub attached_symbol: Vec<u8>,
    pub attached_amount: Vec<u8>,
    pub call_counter: u32,
    pub call_exec_points: u64,
    pub call_exec_points_remaining: u64,
}

pub fn make_caller_env(
    entry_signer: &[u8; 48], entry_prev_hash: &[u8; 32],
    entry_slot: u64, entry_prev_slot: u64, entry_height: u64, entry_epoch: u64,
    entry_vr: &[u8; 96], entry_vr_b3: &[u8; 32], entry_dr: &[u8; 32],
) -> CallerEnv {
    CallerEnv {
        readonly: false,
        seed: Vec::new(),
        seedf64: 1.0,
        entry_signer: *entry_signer,
        entry_prev_hash: *entry_prev_hash,
        entry_slot: entry_slot,
        entry_prev_slot: entry_prev_slot,
        entry_height: entry_height,
        entry_epoch: entry_epoch,
        entry_vr: *entry_vr,
        entry_vr_b3: *entry_vr_b3,
        entry_dr: *entry_dr,
        tx_index: 0,
        tx_signer: [0u8; 48],
        tx_nonce: 0,
        tx_hash: [0u8; 32],
        account_origin: Vec::new(),
        account_caller: Vec::new(),
        account_current: Vec::new(),
        attached_symbol: Vec::new(),
        attached_amount: Vec::new(),
        call_counter: 0,
        call_exec_points: 10_000_000,
        call_exec_points_remaining: 10_000_000,
    }
}

pub struct ApplyEnv<'db> {
    pub caller_env: CallerEnv,
    pub cf: std::sync::Arc<BoundColumnFamily<'db>>,
    pub cf_name: Vec<u8>,
    pub cf_contractstate: std::sync::Arc<BoundColumnFamily<'db>>,
    pub cf_contractstate_tree: std::sync::Arc<BoundColumnFamily<'db>>,
    pub txn: Transaction<'db, TransactionDB<MultiThreaded>>,
    pub muts_final: Vec<consensus_muts::Mutation>,
    pub muts_final_rev: Vec<consensus_muts::Mutation>,
    pub muts: Vec<consensus_muts::Mutation>,
    pub muts_gas: Vec<consensus_muts::Mutation>,
    pub muts_rev: Vec<consensus_muts::Mutation>,
    pub muts_rev_gas: Vec<consensus_muts::Mutation>,
    pub result_log: Vec<HashMap<String, String>>,
    pub testnet: bool,
    pub testnet_peddlebikes: Vec<Vec<u8>>,
}

impl<'db> ApplyEnv<'db> {
    fn into_parts(
        self,
    ) -> (
        Transaction<'db, TransactionDB<MultiThreaded>>,
        Vec<consensus_muts::Mutation>,
        Vec<consensus_muts::Mutation>,
        Vec<HashMap<String, String>>,
    ) {
        (self.txn, self.muts_final, self.muts_final_rev, self.result_log)
    }
}

pub fn make_apply_env<'db>(txn: Transaction<'db, TransactionDB<MultiThreaded>>,
    cf: std::sync::Arc<BoundColumnFamily<'db>>, cf_name: Vec<u8>,
    cf_contractstate: std::sync::Arc<BoundColumnFamily<'db>>, cf_contractstate_tree: std::sync::Arc<BoundColumnFamily<'db>>,
    entry_signer: &[u8; 48], entry_prev_hash: &[u8; 32],
    entry_slot: u64, entry_prev_slot: u64, entry_height: u64, entry_epoch: u64,
    entry_vr: &[u8; 96], entry_vr_b3: &[u8; 32], entry_dr: &[u8; 32],
    testnet: bool, testnet_peddlebikes: Vec<Vec<u8>>
) -> ApplyEnv<'db> {
    ApplyEnv {
        caller_env: make_caller_env(entry_signer, entry_prev_hash, entry_slot, entry_prev_slot, entry_height, entry_epoch, entry_vr, entry_vr_b3, entry_dr),
        cf: cf,
        cf_name: cf_name,
        cf_contractstate: cf_contractstate,
        cf_contractstate_tree: cf_contractstate_tree,
        txn: txn,
        muts_final: Vec::new(),
        muts_final_rev: Vec::new(),
        muts: Vec::new(),
        muts_gas: Vec::new(),
        muts_rev: Vec::new(),
        muts_rev_gas: Vec::new(),
        result_log: Vec::new(),
        testnet: testnet,
        testnet_peddlebikes: testnet_peddlebikes,
    }
}

pub fn set_apply_env_tx<'db>(env: &mut ApplyEnv<'db>, tx_hash: &[u8; 32], tx_signer: &[u8; 48], tx_nonce: u64) {
    env.caller_env.tx_hash = *tx_hash;
    env.caller_env.tx_nonce = tx_nonce;
    env.caller_env.tx_signer = *tx_signer;
    env.caller_env.account_origin = tx_signer.to_vec();
}

pub fn apply_entry<'db, 'a>(db: &'db TransactionDB<MultiThreaded>, pk: &[u8], sk: &[u8],
    entry_signer: &[u8; 48], entry_prev_hash: &[u8; 32],
    entry_slot: u64, entry_prev_slot: u64, entry_height: u64, entry_epoch: u64,
    entry_vr: &[u8; 96], entry_vr_b3: &[u8; 32], entry_dr: &[u8; 32],
    txus: Vec<rustler::Term<'a>>, txn: Transaction<'db, TransactionDB<MultiThreaded>>,
    testnet: bool, testnet_peddlebikes: Vec<Vec<u8>>,
) -> (Transaction<'db, TransactionDB<MultiThreaded>>, Vec<consensus_muts::Mutation>, Vec<consensus_muts::Mutation>, Vec<HashMap<String, String>>) {
    let cf_h = db.cf_handle("contractstate").unwrap();
    let cf2_h = db.cf_handle("contractstate").unwrap();
    let cf_tree_h = db.cf_handle("contractstate_tree").unwrap();
    let mut applyenv = make_apply_env(txn, cf_h, b"contractstate".to_vec(), cf2_h, cf_tree_h, entry_signer, entry_prev_hash, entry_slot, entry_prev_slot, entry_height, entry_epoch, entry_vr, entry_vr_b3, entry_dr, testnet, testnet_peddlebikes);

    call_txs_pre_upfront_cost(&mut applyenv, &txus);

    for (i, txu) in txus.clone().into_iter().enumerate() {
        let tx_hash = crate::fixed::<32>(txu.map_get(crate::atoms::hash()).unwrap()).unwrap();
        let tx = txu.map_get(crate::atoms::tx()).unwrap();
        let tx_signer = crate::fixed::<48>(tx.map_get(crate::atoms::signer()).unwrap()).unwrap();
        let tx_nonce = tx.map_get(crate::atoms::nonce()).unwrap().decode::<u64>().unwrap();
        let action = tx.map_get(crate::atoms::action()).unwrap().decode::<rustler::Term<'a>>().unwrap();

        applyenv.caller_env.tx_index = i as u64;
        applyenv.caller_env.tx_hash = tx_hash;
        applyenv.caller_env.tx_signer = tx_signer;
        applyenv.caller_env.tx_nonce = tx_nonce;
        applyenv.caller_env.account_origin = tx_signer.to_vec();
        applyenv.caller_env.account_caller = tx_signer.to_vec();

        //let op = action.map_get(crate::atoms::op()).unwrap().decode::<rustler::Binary>().unwrap().as_slice();
        let contract = action.map_get(crate::atoms::contract()).unwrap().decode::<rustler::Binary>().unwrap().to_vec();
        let function = action.map_get(crate::atoms::function()).unwrap().decode::<rustler::Binary>().unwrap().to_vec();
        let args = action.map_get(crate::atoms::args()).unwrap().decode::<Vec<rustler::Binary>>().unwrap().into_iter().map(|b| b.as_slice().to_vec()).collect();
        let attached_symbol = match action.map_get(crate::atoms::attached_symbol()).ok() {
            None => None,
            Some(t) => match t.decode::<Option<rustler::Binary>>().ok().flatten() {
                None => None,
                Some(bin) => Some(bin.as_slice().to_vec()),
            },
        };
        let attached_amount = match action.map_get(crate::atoms::attached_amount()).ok() {
            None => None,
            Some(t) => match t.decode::<Option<rustler::Binary>>().ok().flatten() {
                None => None,
                Some(bin) => Some(bin.as_slice().to_vec()),
            },
        };

        applyenv.caller_env.account_current = contract.to_vec();
        applyenv.muts = Vec::new();
        applyenv.muts_rev = Vec::new();
        applyenv.muts_gas = Vec::new();
        applyenv.muts_rev_gas = Vec::new();

        std::panic::set_hook(Box::new(|_| {}));
        let res = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            match consensus::bls12_381::validate_public_key(contract.as_slice()) {
                false => {
                    //println!("{:?}->{:?} {:?} {:?}", String::from_utf8_lossy(&contract), String::from_utf8_lossy(&function), attached_amount, attached_symbol);
                    call_bic(&mut applyenv, contract, function, args, attached_symbol, attached_amount);
                }
                true => {
                    //println!("{:?}->{:?} {:?} {:?}", bs58::encode(&contract).into_string(), String::from_utf8_lossy(&function), attached_amount, attached_symbol);
                    call_wasmvm(&mut applyenv, contract, function, args, attached_symbol, attached_amount);
                }
            }
        }));

        let tx_cost = txu.map_get(crate::atoms::tx_cost()).unwrap().decode::<i128>().unwrap();
        let tx_cost = (tx_cost as u64).to_string();
        match res {
            Ok(_) => {
                applyenv.muts_final.append(&mut applyenv.muts);
                applyenv.muts_final.append(&mut applyenv.muts_gas);
                applyenv.muts_final_rev.append(&mut applyenv.muts_rev);
                applyenv.muts_final_rev.append(&mut applyenv.muts_rev_gas);

                //max logs 100
                //max logs size 1024bytes
                //
                //status	🚨 Critical	1 = Success, 0 = Revert. Always check this first. If it is 0, ignore the rest.
                //logs	🚨 Critical	Contains the actual data of what happened (token transfers, updates).
                //gasUsed	⚠️ High	Needed to calculate the cost or debug efficiency.
                //transactionHash	ℹ️ Medium	Links the receipt back to your original request.
                //logsBloom
/*
                let mut m = std::collections::HashMap::new();
                if applyenv.caller_env.entry_height >= 416_00000 {
                    let vecpak_term = vecpak::Term::PropList(vec![
                        (vecpak::Term::Binary(b"error".to_vec()), vecpak::Term::Binary(b"ok".to_vec())),
                        (vecpak::Term::Binary(b"gas_used".to_vec()), vecpak::Term::Binary(b"0".to_vec())),
                        (vecpak::Term::Binary(b"logs".to_vec()), vecpak::Term::List(Vec::new())),
                    ]);
                    applyenv.result_log.push(vecpak::encode(vecpak_term))
                } else {
                    m.insert("error", "ok");
                    applyenv.result_log.push(m)
                }
*/
                let mut m = std::collections::HashMap::new();
                m.insert("error".to_string(), "ok".to_string());
                if applyenv.caller_env.entry_height >= 416_00000 {
                    m.insert("gas_used".to_string(), tx_cost.clone());
                }
                applyenv.result_log.push(m);
            }
            Err(payload) => {
                applyenv.muts_final.append(&mut applyenv.muts_gas);
                applyenv.muts_final_rev.append(&mut applyenv.muts_rev_gas);

                consensus_kv::revert(&mut applyenv);

                if let Some(&s) = payload.downcast_ref::<&'static str>() {
                    let mut m = std::collections::HashMap::new();
                    m.insert("error".to_string(), s.to_string());
                    if applyenv.caller_env.entry_height >= 416_00000 {
                        m.insert("gas_used".to_string(), tx_cost.clone());
                    }
                    applyenv.result_log.push(m);
                } else {
                    let mut m = std::collections::HashMap::new();
                    m.insert("error".to_string(), "unknown".to_string());
                    if applyenv.caller_env.entry_height >= 416_00000 {
                        //(tx_cost as u64).to_string().into_bytes()
                        m.insert("gas_used".to_string(), tx_cost.clone());
                    }
                    applyenv.result_log.push(m);
                }
            }
        }
    }

    call_exit(&mut applyenv);

    //Update tree
    //Select only the last muts, rest are irrelevent for tree
    let mut ops: Vec<consensus::bintree_rdb::Op> = Vec::with_capacity(10000);
    if applyenv.caller_env.entry_height >= 416_00000 {
        if applyenv.caller_env.entry_height == 416_00000 {
            let iter = applyenv.txn.iterator_cf(&applyenv.cf_contractstate, rust_rocksdb::IteratorMode::Start);
            for item in iter {
                match item {
                    Ok((key, value)) => {
                        let namespace = consensus_kv::contractstate_namespace(&key);
                        ops.push(consensus::bintree_rdb::Op::Insert(namespace, key.to_vec(), value.to_vec()))
                        //println!("Key: {} | Val: {}", key.iter().map(|b| format!("{:02x}", b)).collect::<String>(), value.iter().map(|b| format!("{:02x}", b)).collect::<String>());
                    },
                    Err(_) => {
                        panic!("Error during iteration")
                    }
                }
            }
        }

        let mut map: HashMap<Vec<u8>, consensus_muts::Mutation> = HashMap::new();
        for m in applyenv.muts_final.clone() {
            match m {
                consensus_muts::Mutation::Put { ref key, .. } | consensus_muts::Mutation::Delete { ref key, .. }
                | consensus_muts::Mutation::SetBit { ref key, .. } | consensus_muts::Mutation::ClearBit { ref key, .. }=> {
                    map.insert(key.clone(), m);
                }
            }
        }
        for (key, m) in map {
            let namespace = consensus_kv::contractstate_namespace(&key);
            let op = match m {
                consensus_muts::Mutation::Put { value, .. } => {
                    consensus::bintree_rdb::Op::Insert(namespace, key, value)
                },
                consensus_muts::Mutation::Delete { .. } => {
                    consensus::bintree_rdb::Op::Delete(namespace, key)
                },
                consensus_muts::Mutation::SetBit { .. } => {
                    let val = applyenv.txn.get_cf(&applyenv.cf, &key).unwrap().unwrap();
                    consensus::bintree_rdb::Op::Insert(namespace, key, val)
                },
                consensus_muts::Mutation::ClearBit { .. } => {
                    let val = applyenv.txn.get_cf(&applyenv.cf, &key).unwrap().unwrap();
                    consensus::bintree_rdb::Op::Insert(namespace, key, val)
                },
            };
            ops.push(op);
        }

        applyenv.cf = db.cf_handle("contractstate_tree").unwrap();
        applyenv.cf_name = b"contractstate_tree".to_vec();
        applyenv.muts = Vec::new();
        applyenv.muts_rev = Vec::new();
        let mut hubt_contractstate = consensus::bintree_rdb::RocksHubt::new(&mut applyenv);
        hubt_contractstate.batch_update(ops);
        //let hubt_contractstate_root = hubt_contractstate.root();

        let mut muts = unique_mutations(applyenv.muts.clone(), false);
        applyenv.muts_final.append(&mut muts);
        let mut muts_rev = unique_mutations(applyenv.muts_rev.clone(), true);
        applyenv.muts_final_rev.append(&mut muts_rev);

        //println!("{:?} {:?}", applyenv.caller_env.entry_height, root_receipts(txus.clone(), applyenv.result_log.clone()));
        //println!("{:?} {}", applyenv.caller_env.entry_height, hubt_contractstate_root.iter().map(|b| format!("{:02x}", b)).collect::<String>());
    }
    applyenv.into_parts()
}

fn root_receipts(
    txus: Vec<rustler::Term>,
    result_log: Vec<HashMap<&'static str, &'static str>>
) -> [u8; 32] {
    use sha2::{Sha256, Digest};
    let mut hubt = bintree::Hubt::new();
    let mut kvs = Vec::new();

    let count = txus.len();

    for (txu, log) in txus.into_iter().zip(result_log.into_iter()) {
        let tx_hash = crate::fixed::<32>(txu.map_get(crate::atoms::hash()).unwrap()).unwrap();

        let error = log.get("error")
            .expect("no_error_key_in_receipt")
            .as_bytes()
            .to_vec();

        let log_term = vecpak::encode(log.to_term());
        let log_hash = Sha256::digest(&log_term);

        kvs.push(bintree::Op::Insert(tx_hash.to_vec(), log_hash.to_vec()));
        kvs.push(bintree::Op::Insert([b"result:", &tx_hash[..]].concat(), error));
    }
    kvs.push(bintree::Op::Insert(b"count".to_vec(), (count as u64).to_string().into_bytes()));

    hubt.batch_update(kvs);
    hubt.root()
}

pub trait ToTerm {
    fn to_term(self) -> vecpak::Term;
}
impl ToTerm for HashMap<&'static str, &'static str> {
    fn to_term(self) -> vecpak::Term {
        let props: Vec<(vecpak::Term, vecpak::Term)> = self
            .into_iter()
            .map(|(k, v)| {
                (
                    vecpak::Term::Binary(k.as_bytes().to_vec()),
                    vecpak::Term::Binary(v.as_bytes().to_vec()),
                )
            })
            .collect();

        vecpak::Term::PropList(props)
    }
}
impl ToTerm for Vec<HashMap<&'static str, &'static str>> {
    fn to_term(self) -> vecpak::Term {
        let list_content: Vec<vecpak::Term> = self
            .into_iter()
            .map(|map| {
                // Convert HashMap to PropList
                let props: Vec<(vecpak::Term, vecpak::Term)> = map
                    .into_iter()
                    .map(|(k, v)| {
                        (
                            vecpak::Term::Binary(k.as_bytes().to_vec()),
                            vecpak::Term::Binary(v.as_bytes().to_vec()),
                        )
                    })
                    .collect();
                vecpak::Term::PropList(props)
            })
            .collect();
        vecpak::Term::List(list_content)
    }
}

fn call_txs_pre_upfront_cost<'a>(env: &mut ApplyEnv, txus: &[rustler::Term<'a>]) {
    env.muts = Vec::new();
    env.muts_rev = Vec::new();
    for txu in txus {
        let tx_hash = crate::fixed::<32>(txu.map_get(crate::atoms::hash()).unwrap()).unwrap();
        let tx = txu.map_get(crate::atoms::tx()).unwrap();
        let tx_signer = crate::fixed::<48>(tx.map_get(crate::atoms::signer()).unwrap()).unwrap();
        let tx_nonce = tx.map_get(crate::atoms::nonce()).unwrap().decode::<u64>().unwrap();

        set_apply_env_tx(env, &tx_hash, &tx_signer, tx_nonce);

        // Update nonce
        consensus_kv::kv_put(env, &crate::bcat(&[b"account:", &tx_signer, b":attribute:nonce"]), &tx_nonce.to_string().into_bytes());
        // Deduct tx cost
        let tx_cost = txu.map_get(crate::atoms::tx_cost()).unwrap().decode::<i128>().unwrap();
        protocol::pay_cost(env, tx_cost);
    }
    env.muts_final.append(&mut env.muts);
    env.muts_final_rev.append(&mut env.muts_rev);
}

fn call_exit(env: &mut ApplyEnv) {
    //seed RNG for random validator selection
    let vr = env.caller_env.entry_vr.to_vec();
    let seed_hash = blake3::hash(&vr);
    env.caller_env.seed = seed_hash.as_bytes().to_vec();
    // extract f64 from first 8 bytes of seed_hash in little-endian
    let seedf64 = f64::from_le_bytes(seed_hash.as_bytes()[0..8].try_into().unwrap_or([0u8; 8]));
    env.caller_env.seedf64 = seedf64;

    env.muts = Vec::new();
    env.muts_rev = Vec::new();

    if env.caller_env.entry_height % 1000 == 0 {
        let digest = blake3::hash(&env.caller_env.entry_vr);
        consensus_kv::kv_put(env, b"bic:epoch:segment_vr_hash", digest.as_bytes());
    }
    if env.caller_env.entry_height % 100_000 == 99_999 {
        consensus::bic::epoch::next(env);
    }
    if env.caller_env.entry_height == 412_99999 {
        //migrate_db(env);
    }

    env.muts_final.append(&mut env.muts);
    env.muts_final_rev.append(&mut env.muts_rev);
}

fn unique_mutations(mutations: Vec<consensus_muts::Mutation>, reverse: bool) -> Vec<consensus_muts::Mutation> {
    let mut seen = std::collections::HashSet::new();
    let mut result = Vec::new();

    // Iterate BACKWARDS (Newest -> Oldest)
    let iter: Box<dyn Iterator<Item = consensus_muts::Mutation>> = if reverse {
        Box::new(mutations.into_iter())
    } else {
        Box::new(mutations.into_iter().rev())
    };
    for m in iter {
        match m {
            consensus_muts::Mutation::Put { ref key, .. }
            | consensus_muts::Mutation::Delete { ref key, .. }
            | consensus_muts::Mutation::SetBit { ref key, .. }
            | consensus_muts::Mutation::ClearBit { ref key, .. } => {
                if seen.insert(key.clone()) {
                    result.push(m);
                }
            }
        }
    }

    if !reverse {
        result.reverse();
    }
    result
}

fn migrate_db(env: &mut ApplyEnv) {
    //"bic:epoch:trainers:85"
    //"bic:epoch:trainers:height:000039625024"
    //"bic:epoch:trainers:removed:
    let mut cursor: Vec<u8> = Vec::new();
    while let Some((next_key_wo_prefix, _val)) = crate::consensus::consensus_kv::kv_get_next(env, b"bic:epoch:trainers:height:", &cursor) {
        let height = std::str::from_utf8(&next_key_wo_prefix).ok().and_then(|s| s.parse::<u64>().ok()).unwrap_or_else(|| panic_any("invalid_epoch"));
        let trainers: Vec<vecpak::Term> = consensus::bic::epoch::kv_get_trainers(env, height)
            .into_iter()
            .map(vecpak::Term::Binary)
            .collect();
        let buf = vecpak::encode(vecpak::Term::List(trainers));
        crate::consensus::consensus_kv::kv_put(env, &crate::bcat(&[b"bic:epoch:validators:height:", &next_key_wo_prefix]), &buf);
        cursor = next_key_wo_prefix;
    }
    cursor = Vec::new();
    while let Some((next_key_wo_prefix, _val)) = crate::consensus::consensus_kv::kv_get_next(env, b"bic:epoch:trainers:", &cursor) {
        let full_key = [b"bic:epoch:trainers:" as &[u8], &next_key_wo_prefix].concat();
        crate::consensus::consensus_kv::kv_delete(env, &full_key);
        cursor = next_key_wo_prefix;
    }

    //"bic:coin:balance:???ii?????d???K\\?????c??[??y????)?o??{=?;????n?9:AMA"
    cursor = Vec::new();
    while let Some((next_key_wo_prefix, val)) = crate::consensus::consensus_kv::kv_get_next(env, b"bic:coin:balance:", &cursor) {
        let pk = &next_key_wo_prefix[..48];
        crate::consensus::consensus_kv::kv_put(env, &crate::bcat(&[b"account:", &pk, b":balance:AMA"]), &val);

        let full_key = [b"bic:coin:balance:" as &[u8], &next_key_wo_prefix].concat();
        crate::consensus::consensus_kv::kv_delete(env, &full_key);

        cursor = next_key_wo_prefix;
    }

    //"bic:base:nonce:????GH??D?ss???????dT??14o?P??nA?I&??6?????e3I??"
    cursor = Vec::new();
    while let Some((next_key_wo_prefix, val)) = crate::consensus::consensus_kv::kv_get_next(env, b"bic:base:nonce:", &cursor) {
        let pk = &next_key_wo_prefix[..48];
        crate::consensus::consensus_kv::kv_put(env, &crate::bcat(&[b"account:", &pk, b":attribute:nonce"]), &val);

        let full_key = [b"bic:base:nonce:" as &[u8], &next_key_wo_prefix].concat();
        crate::consensus::consensus_kv::kv_delete(env, &full_key);

        cursor = next_key_wo_prefix;
    }

    //"bic:epoch:emission_address:????GH??D?ss???????dT??14o?P??nA?I&??6?????e3I??"
    cursor = Vec::new();
    while let Some((next_key_wo_prefix, val)) = crate::consensus::consensus_kv::kv_get_next(env, b"bic:epoch:emission_address:", &cursor) {
        let pk = &next_key_wo_prefix[..48];
        crate::consensus::consensus_kv::kv_put(env, &crate::bcat(&[b"account:", &pk, b":attribute:emission_address"]), &val);

        let full_key = [b"bic:epoch:emission_address:" as &[u8], &next_key_wo_prefix].concat();
        crate::consensus::consensus_kv::kv_delete(env, &full_key);

        cursor = next_key_wo_prefix;
    }

    //"bic:epoch:pop:????GH??D?ss???????dT??14o?P??nA?I&??6?????e3I??"
    cursor = Vec::new();
    while let Some((next_key_wo_prefix, val)) = crate::consensus::consensus_kv::kv_get_next(env, b"bic:epoch:pop:", &cursor) {
        let pk = &next_key_wo_prefix[..48];
        crate::consensus::consensus_kv::kv_put(env, &crate::bcat(&[b"account:", &pk, b":attribute:pop"]), &val);

        let full_key = [b"bic:epoch:pop:" as &[u8], &next_key_wo_prefix].concat();
        crate::consensus::consensus_kv::kv_delete(env, &full_key);

        cursor = next_key_wo_prefix;
    }
}


pub fn valid_bic_action(contract: Vec<u8>, function: Vec<u8>) -> bool {
    let c = contract.as_slice();
    let f = function.as_slice();

    (c == b"Epoch" || c == b"Coin" || c == b"Contract")
        && (f == b"submit_sol"
            || f == b"transfer"
            || f == b"set_emission_address"
            || f == b"slash_trainer"
            || f == b"deploy"
            || f == b"create_and_mint"
            || f == b"mint"
            || f == b"pause")
}

fn call_bic(env: &mut ApplyEnv, contract: Vec<u8>, function: Vec<u8>, args: Vec<Vec<u8>>, attached_symbol: Option<Vec<u8>>, attached_amount: Option<Vec<u8>>) {
    match (contract.as_slice(), function.as_slice()) {
        (b"Coin", b"transfer") => consensus::bic::coin::call_transfer(env, args),
        //(b"Coin", b"create_and_mint") => consensus::bic::coin::call_create_and_mint(env, args),
        //(b"Coin", b"mint") => consensus::bic::coin::call_mint(env, args),
        //(b"Coin", b"pause") => consensus::bic::coin::call_pause(env, args),
        (b"Epoch", b"set_emission_address") => consensus::bic::epoch::call_set_emission_address(env, args),
        (b"Epoch", b"submit_sol") => consensus::bic::epoch::call_submit_sol(env, args),
        (b"Epoch", b"slash_trainer") => consensus::bic::epoch::call_slash_trainer(env, args),
        (b"Contract", b"deploy") => consensus::bic::contract::call_deploy(env, args),
        //(b"Lockup", b"unlock") => consensus::bic::lockup::call_unlock(env, args),
        //(b"LockupPrime", b"lock") => consensus::bic::lockup_prime::call_lock(env, args),
        //(b"LockupPrime", b"unlock") => consensus::bic::lockup_prime::call_unlock(env, args),
        //(b"LockupPrime", b"daily_checkin") => consensus::bic::lockup_prime::call_daily_checkin(env, args),
        _ => std::panic::panic_any("invalid_bic_action")
    }
}

fn call_wasmvm(env: &mut ApplyEnv, contract: Vec<u8>, function: Vec<u8>, args: Vec<Vec<u8>>, attached_symbol: Option<Vec<u8>>, attached_amount: Option<Vec<u8>>) {
    env.caller_env.attached_symbol = Vec::new();
    env.caller_env.attached_amount = Vec::new();
    //TODO: wrap this into a neat entry func prepare_wasm_call(env..)

    let bytecode = consensus::bic::contract::bytecode(env, contract.as_slice());
    if bytecode.is_none() { panic_any("account_has_no_bytecode") }

    match (attached_symbol, attached_amount) {
        (Some(attached_symbol), Some(attached_amount)) => {
            let amount = std::str::from_utf8(&attached_amount).ok().and_then(|s| s.parse::<i128>().ok()).unwrap_or_else(|| panic_any("invalid_attached_amount"));
            if amount <= 0 { panic_any("invalid_attached_amount") }
            if amount > consensus::bic::coin::balance(env, &env.caller_env.account_caller, &attached_symbol) { panic_any("attached_amount_insufficient_funds") }

            consensus_kv::kv_increment(env, &crate::bcat(&[b"account:", &contract, b":balance:", &attached_symbol]), amount);
            consensus_kv::kv_increment(env, &crate::bcat(&[b"account:", &env.caller_env.account_caller, b":balance:", &attached_symbol]), -amount);

            env.caller_env.attached_symbol = attached_symbol;
            env.caller_env.attached_amount = attached_amount;
        },
        _ => ()
    }

    std::panic::panic_any("wasm_noop")
    //let result = ();

    //exec used
    //muts
}
