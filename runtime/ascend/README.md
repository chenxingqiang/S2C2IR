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
