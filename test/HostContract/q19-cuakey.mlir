// CUDA analyze key map. Query only. No semantic cut.
// This lit test is not in check-host. Do not call run_analyzer.
// RUN: python3 %S/../../runtime/record_q19_cuakey.py --print-q19-cuakey | FileCheck %s --check-prefix=Q19 --implicit-check-not=can-run-plan=yes
// Q19: q19-cuakey gate=query
// Q19: analyze cap-schema --analyze-cap-schema
// Q19: analyze cap --analyze-cap
// Q19: analyze phase --analyze-phase
// Q19: analyze pipe --analyze-pipe
// Q19: analyze pipe-tiles --analyze-pipe-tiles
// Q19: analyze cuda-val --analyze-cuda-val
// Q19: analyze cuda-val-mem --analyze-cuda-val-mem
// Q19: analyze cuda-val-cc --analyze-cuda-val-cc
// Q19: analyze cuda-val-async --analyze-cuda-val-async
// Q19: analyze matched --analyze-matched
// Q19: analyze ratio --analyze-ratio
// Q19: q19-cuakey yes
// Q19: can-run-plan no
