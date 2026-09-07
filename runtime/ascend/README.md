# Ascend 910B capability adapter runtime

Standalone AscendCL harness for three S²C² pairs. Not linked
into `s2c2-opt`. Host protocol (`--dry-run`) is
`s2c2-ascend-adapter` and does not need this directory.

```sh
# on a machine with CANN
source "$ASCEND_TOOLKIT_HOME/bin/setenv.bash"
g++ -O2 -std=c++17 runtime/ascend/s2c2_ascend_adapter.cpp \
  -I"$ASCEND_TOOLKIT_HOME/include" -L"$ASCEND_TOOLKIT_HOME/lib64" \
  -lascendcl -lnnopbase -lopapi -o s2c2-ascend-run
./s2c2-ascend-run --pairs --n=1048576 --k=8
# host protocol (no CANN):
s2c2-ascend-adapter --dry-run
s2c2-ascend-adapter --dry-run --cap-schema
python3 runtime/ascend/record_ascend.py --check-schema-identity
```

Pairs: `C||HtoD`, `C||C`, `HtoD||DtoH`.
Workload semantic: `elemwise` / `host_to_device` / `device_to_host`.
Capability Schema v1 keys only. No `acl_*` / `davinci_*` fields.
`T_pair` is host wall-clock over `completion(s0,s1)`.
Concurrent compute uses per-stream aclnn workspace.
Do not commit hostnames, accounts, or passwords.
Do not FileCheck microseconds.
Do not use Graph Engine / MindSpore / torch_npu / aclgraph.
Measured catalog: `docs/design/v3-dataset/ascend910b/`.
`runtime/ascend/record_ascend.py --query-cap 'C||C'`
Pinned vs pageable: `./s2c2-ascend-run --mem --n=4194304 --k=0`
C||C r-sweep: `./s2c2-ascend-run --cc-phase --n=4194304 --k=32 --r=0.5,0.75,1,1.5,2`
C||C size-boundary: `runtime/ascend/sweep_cc_size.sh`
C||C rewrite A/B: `runtime/ascend/sweep_cc_rewrite.sh`
Serial band `rewrite_license=yes` is from that A/B, not from `#69`.
SSD+MLP program wall-clock: `runtime/ascend/sweep_ssd_mlp_wallclock.sh`
(`T_evi/T_seq`, not the stage A/B; `#69` untouched).
Batch-check retained hardware files:
`python3 runtime/record_hw_ledger.py --check-hw-ledger`.
Size-band query: `python3 runtime/ascend/record_ascend.py --query-cap 'C||C' --cap-catalog docs/design/v3-dataset/ascend910b/cc-size-applicability.jsonl --n 33554432`
Does not overwrite the #69 catalog. Cross-vendor schedule:
`docs/design/pr-r3-cross-vendor.md`.
