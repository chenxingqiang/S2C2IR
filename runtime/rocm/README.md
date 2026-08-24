# ROCm capability adapter runtime

Standalone HIP harness for three S²C² pairs. Not linked into
`s2c2-opt`. Host protocol (`--dry-run`) is `s2c2-rocm-adapter`
and does not need this directory.

```sh
# on a machine with hipcc
hipcc -O2 -std=c++17 runtime/rocm/s2c2_rocm_adapter.cpp -o s2c2-rocm-run
./s2c2-rocm-run --pairs --n=4194304 --k=32
S2C2_GIT_COMMIT=$(git rev-parse HEAD) ./runtime/rocm/sweep_pairs.sh ./s2c2-rocm-run ./v3-rocm-pairs
# host protocol (no HIP):
s2c2-rocm-adapter --dry-run
s2c2-rocm-adapter --dry-run --cap-schema
python3 runtime/rocm/record_rocm.py --check-schema-identity
```

Pairs: `C||HtoD`, `C||C`, `HtoD||DtoH`.
Workload semantic: `elemwise` / `host_to_device` / `device_to_host`.
Capability Schema v1 keys only. No `hip_*` fields.
`T_pair` is host wall-clock over `completion(s0,s1)`, not a
null-stream `hipEventRecord`.
Do not commit hostnames, accounts, or passwords.
Do not FileCheck microseconds.
