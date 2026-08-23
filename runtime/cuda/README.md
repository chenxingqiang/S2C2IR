# CUDA adapter runtime

Standalone timed stand-in of the three Pilot shapes. Not linked
into `s2c2-opt`. Host protocol (`--dry-run`) is
`s2c2-cuda-adapter` and does not need this directory.

```sh
# on a machine with nvcc
nvcc -O2 -std=c++17 runtime/cuda/s2c2_cuda_adapter.cu -o s2c2-cuda-run
./s2c2-cuda-run --func=all --device=gpu --n=16777216
./s2c2-cuda-run --func=all --device=cpu --n=16777216
```

Do not commit hostnames, accounts, or passwords.
