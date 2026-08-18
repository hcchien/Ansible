//! Android JNI bridge for the pinned ZKPassport UltraHonk backend.
//!
//! The boundary deliberately accepts only a circuit manifest, generated
//! witness-input JSON, a pinned verification key, and a local SRS path.  It
//! performs no network I/O, does not log, and never writes passport/MRZ/DG
//! bytes to disk.  The Flutter layer is responsible for obtaining and pinning
//! public circuit artifacts before they cross this boundary.

use std::collections::HashMap;
use std::sync::Mutex;

use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use jni::objects::{JClass, JString};
use jni::sys::jstring;
use jni::JNIEnv;
use noir_rs::{
    acir::native_types::{Witness, WitnessMap},
    barretenberg::{
        prove::prove_ultra_honk,
        srs::setup_srs,
        verify::verify_ultra_honk,
    },
    FieldElement,
};
use once_cell::sync::Lazy;
use rquickjs::{Context, Runtime};
use serde_json::{json, Value};

// This bundle is compiled into the signed native library; Android never loads
// it through WebView, a URL, filesystem path, or network bridge.  It is a
// transitional compatibility host for ZKPassport's currently JavaScript-only
// proof-plan implementation.  The surrounding Rust/JNI API and all circuit
// artifact resolution stay native and fail closed.
const REVIEWED_PLANNER_RUNTIME: &str = include_str!("../../../assets/zkpassport/runtime.js");
// QuickJS intentionally has no browser globals.  These two encoding-only
// shims are sufficient for the reviewed planner bundle and do not provide any
// transport, persistence, randomness, or host callbacks.
const PLANNER_POLYFILLS: &str = r#"
if (typeof TextEncoder === "undefined") {
  globalThis.TextEncoder = class {
    encode(value) {
      const utf8 = unescape(encodeURIComponent(String(value)));
      const bytes = new Uint8Array(utf8.length);
      for (let i = 0; i < utf8.length; i++) bytes[i] = utf8.charCodeAt(i);
      return bytes;
    }
  };
}
if (typeof TextDecoder === "undefined") {
  globalThis.TextDecoder = class {
    decode(bytes) {
      let raw = "";
      for (const byte of bytes) raw += String.fromCharCode(byte);
      return decodeURIComponent(escape(raw));
    }
  };
}
"#;

#[derive(Default)]
struct NativeState {
    circuits: HashMap<String, Circuit>,
    srs_points: u32,
}

struct Circuit {
    bytecode: String,
    abi: Vec<Value>,
}

static STATE: Lazy<Mutex<NativeState>> = Lazy::new(|| Mutex::new(NativeState::default()));

/// A deliberately small JNI surface: Kotlin supplies an operation and JSON
/// payload, and every response is JSON.  This avoids marshalling nested
/// private witness maps through Java reflection and makes failure handling
/// deterministic.  Errors are category-only: no witness value or passport
/// data is included in the returned message.
#[no_mangle]
pub extern "system" fn Java_io_trisaura_ansible_1node_AndroidZkPassportNative_call(
    mut env: JNIEnv,
    _class: JClass,
    operation: JString,
    payload: JString,
) -> jstring {
    let outcome = (|| -> Result<Value, &'static str> {
        let operation: String = env.get_string(&operation).map_err(|_| "invalid_request")?.into();
        let payload: String = env.get_string(&payload).map_err(|_| "invalid_request")?.into();
        let payload: Value = serde_json::from_str(&payload).map_err(|_| "invalid_request")?;
        dispatch(&operation, payload)
    })();
    let response = match outcome {
        Ok(value) => json!({"ok": true, "value": value}),
        Err(code) => json!({"ok": false, "code": code}),
    };
    let encoded = response.to_string();
    match env.new_string(encoded) {
        Ok(value) => value.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

fn dispatch(operation: &str, payload: Value) -> Result<Value, &'static str> {
    match operation {
        "initialize_srs" => {
            let circuit_size = payload_u32(&payload, "circuit_size")?;
            let path = payload_string(&payload, "srs_path")?;
            if path.is_empty() {
                return Err("invalid_request");
            }
            let points = setup_srs(circuit_size, Some(&path)).map_err(|_| "srs_initialize_failed")?;
            let mut state = STATE.lock().map_err(|_| "native_state_failed")?;
            state.srs_points = points;
            Ok(json!(points))
        }
        "prepare" => {
            let manifest = payload_string(&payload, "manifest_json")?;
            let manifest: Value = serde_json::from_str(&manifest).map_err(|_| "invalid_manifest")?;
            let bytecode = manifest
                .get("bytecode")
                .and_then(Value::as_str)
                .filter(|value| !value.is_empty())
                .ok_or("invalid_manifest")?
                .to_owned();
            let id = manifest
                .get("hash")
                .and_then(Value::as_str)
                .filter(|value| !value.is_empty())
                .ok_or("invalid_manifest")?
                .to_owned();
            let abi = manifest
                .get("abi")
                .and_then(|value| value.get("parameters"))
                .and_then(Value::as_array)
                .filter(|value| !value.is_empty())
                .ok_or("invalid_manifest")?
                .to_vec();
            let mut state = STATE.lock().map_err(|_| "native_state_failed")?;
            if state.srs_points == 0 {
                return Err("srs_not_initialized");
            }
            state.circuits.insert(id.clone(), Circuit { bytecode, abi });
            Ok(json!(id))
        }
        "prove" => {
            let circuit_id = payload_string(&payload, "circuit_id")?;
            let inputs = payload.get("inputs").ok_or("invalid_request")?;
            let verification_key = payload_string(&payload, "verification_key_base64")?;
            let verification_key = BASE64.decode(verification_key).map_err(|_| "invalid_request")?;
            let state = STATE.lock().map_err(|_| "native_state_failed")?;
            let circuit = state.circuits.get(&circuit_id).ok_or("unknown_circuit")?;
            let witness = witness_map(inputs, &circuit.abi)?;
            let proof = prove_ultra_honk(
                &circuit.bytecode,
                witness,
                verification_key,
                false,
                Some(0),
            ).map_err(|_| "proof_generation_failed")?;
            Ok(json!(BASE64.encode(proof)))
        }
        "verify" => {
            let proof = BASE64.decode(payload_string(&payload, "proof_base64")?)
                .map_err(|_| "invalid_request")?;
            let verification_key = BASE64.decode(payload_string(&payload, "verification_key_base64")?)
                .map_err(|_| "invalid_request")?;
            let verified = verify_ultra_honk(proof, verification_key)
                .map_err(|_| "proof_verification_failed")?;
            Ok(json!(verified))
        }
        "plan" => plan(payload),
        "planner_runtime_self_test" => planner_runtime_self_test(),
        "clear" => {
            let mut state = STATE.lock().map_err(|_| "native_state_failed")?;
            state.circuits.clear();
            Ok(Value::Null)
        }
        _ => Err("unsupported_operation"),
    }
}

fn planner_runtime_self_test() -> Result<Value, &'static str> {
    let runtime = Runtime::new().map_err(|_| "planner_initialization_failed")?;
    let context = Context::full(&runtime).map_err(|_| "planner_initialization_failed")?;
    context.with(|context| {
        load_reviewed_planner(&context)?;
        let marker = context
            .eval::<String, _>("ElixZKPassport.bufferCompatibilityCheck()")
            .map_err(|_| "planner_initialization_failed")?;
        if marker == "454c4958" { Ok(json!(marker)) } else { Err("planner_initialization_failed") }
    })
}

fn plan(payload: Value) -> Result<Value, &'static str> {
    // Keep the full request in native process memory.  We deliberately never
    // surface QuickJS exceptions: they could contain MRZ/DG/SOD-derived text.
    let request = payload.get("request").cloned().ok_or("invalid_request")?;
    let request = serde_json::to_string(&request).map_err(|_| "invalid_request")?;
    let runtime = Runtime::new().map_err(|_| "planner_initialization_failed")?;
    let context = Context::full(&runtime).map_err(|_| "planner_initialization_failed")?;
    context.with(|context| {
        load_reviewed_planner(&context)?;
        let invocation = format!(
            r#"
            globalThis.__elixPlanResult = "";
            globalThis.__elixPlanFailed = false;
            ElixZKPassport.createProofPlan({request}, () => {{}})
              .then((value) => {{
                globalThis.__elixPlanResult = JSON.stringify(value, (_key, item) =>
                  typeof item === "bigint" ? item.toString(10) :
                  (ArrayBuffer.isView(item) ? Array.from(item) : item));
              }})
              .catch(() => {{ globalThis.__elixPlanFailed = true; }});
            "#,
        );
        context.eval::<(), _>(invocation).map_err(|_| "plan_failed")?;
        let mut drained = false;
        for _ in 0..100_000 {
            if !context.execute_pending_job() {
                drained = true;
                break;
            }
        }
        if !drained { return Err("plan_timed_out"); }
        let failed = context
            .eval::<bool, _>("globalThis.__elixPlanFailed")
            .map_err(|_| "plan_failed")?;
        if failed { return Err("plan_failed"); }
        let encoded = context
            .eval::<String, _>("globalThis.__elixPlanResult")
            .map_err(|_| "plan_failed")?;
        if encoded.is_empty() { return Err("plan_failed"); }
        serde_json::from_str(&encoded).map_err(|_| "invalid_plan")
    })
}

fn load_reviewed_planner(context: &rquickjs::Ctx<'_>) -> Result<(), &'static str> {
    context.eval::<(), _>(PLANNER_POLYFILLS).map_err(|_| "planner_initialization_failed")?;
    context.eval::<(), _>(REVIEWED_PLANNER_RUNTIME).map_err(|_| "planner_initialization_failed")
}

fn payload_string(payload: &Value, key: &str) -> Result<String, &'static str> {
    payload.get(key)
        .and_then(Value::as_str)
        .map(str::to_owned)
        .ok_or("invalid_request")
}

fn payload_u32(payload: &Value, key: &str) -> Result<u32, &'static str> {
    payload.get(key)
        .and_then(Value::as_u64)
        .and_then(|value| u32::try_from(value).ok())
        .ok_or("invalid_request")
}

fn witness_map(inputs: &Value, parameters: &[Value]) -> Result<WitnessMap<FieldElement>, &'static str> {
    let inputs = inputs.as_object().ok_or("invalid_witness")?;
    let mut values = Vec::new();
    for parameter in parameters {
        let name = parameter.get("name").and_then(Value::as_str).ok_or("invalid_manifest")?;
        let kind = parameter.get("type").ok_or("invalid_manifest")?;
        let input = inputs.get(name).ok_or("invalid_witness")?;
        flatten_witness(kind, input, &mut values)?;
    }
    let mut witness = WitnessMap::new();
    for (index, value) in values.into_iter().enumerate() {
        let value = FieldElement::try_from_str(&value).ok_or("invalid_witness")?;
        witness.insert(Witness(index as u32), value);
    }
    Ok(witness)
}

fn flatten_witness(kind: &Value, input: &Value, output: &mut Vec<String>) -> Result<(), &'static str> {
    let tag = kind.get("kind").and_then(Value::as_str).ok_or("invalid_manifest")?;
    match tag {
        "field" | "integer" => output.push(field_text(input)?),
        "boolean" => output.push(match input {
            Value::Bool(true) => "1".to_owned(),
            Value::Bool(false) => "0".to_owned(),
            _ => field_text(input)?,
        }),
        "string" => {
            let expected = kind.get("length").and_then(Value::as_u64).ok_or("invalid_manifest")? as usize;
            let value = input.as_str().ok_or("invalid_witness")?;
            let bytes = value.as_bytes();
            if bytes.len() != expected { return Err("invalid_witness"); }
            output.extend(bytes.iter().map(|byte| byte.to_string()));
        }
        "struct" => {
            let fields = kind.get("fields").and_then(Value::as_array).ok_or("invalid_manifest")?;
            let object = input.as_object().ok_or("invalid_witness")?;
            for field in fields {
                let name = field.get("name").and_then(Value::as_str).ok_or("invalid_manifest")?;
                flatten_witness(field.get("type").ok_or("invalid_manifest")?, object.get(name).ok_or("invalid_witness")?, output)?;
            }
        }
        "array" => {
            let values = input.as_array().ok_or("invalid_witness")?;
            let expected = kind.get("length").and_then(Value::as_u64).ok_or("invalid_manifest")? as usize;
            if values.len() != expected { return Err("invalid_witness"); }
            let element = kind.get("type").ok_or("invalid_manifest")?;
            for value in values { flatten_witness(element, value, output)?; }
        }
        _ => return Err("invalid_manifest"),
    }
    Ok(())
}

fn field_text(value: &Value) -> Result<String, &'static str> {
    match value {
        Value::String(value) if !value.is_empty() => Ok(value.clone()),
        Value::Number(value) => Ok(value.to_string()),
        _ => Err("invalid_witness"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reviewed_planner_bundle_runs_without_a_browser_host() {
        let runtime = Runtime::new().unwrap();
        let context = Context::full(&runtime).unwrap();
        context.with(|context| {
            if load_reviewed_planner(&context).is_err() {
                let exception = context.catch();
                context.globals().set("__elixPlannerException", exception).unwrap();
                let message = context.eval::<String, _>("String(__elixPlannerException.stack || __elixPlannerException)").unwrap();
                panic!("planner bundle error: {message}");
            }
            assert_eq!(
                context.eval::<String, _>("ElixZKPassport.bufferCompatibilityCheck()").unwrap(),
                "454c4958",
            );
        });
    }

    #[test]
    fn planner_rejects_an_invalid_request_without_exposing_input() {
        assert_eq!(plan(json!({"request": {"version": "invalid"}})), Err("plan_failed"));
    }
}
