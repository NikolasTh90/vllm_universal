#!/bin/bash
# Exit immediately if a command exits with a non-zero status.
set -e

# The model name MUST be the first argument passed to vllm serve.
MODEL_NAME="${VLLM_MODEL_NAME:-mistralai/Mistral-7B-Instruct-v0.3}"

# Build the command from environment variables.
CMD="vllm serve ${MODEL_NAME}"

# Only add arguments if environment variables are populated
[ -n "${VLLM_HOST:-}" ] && CMD+=" --host ${VLLM_HOST}"
[ -n "${VLLM_PORT:-}" ] && CMD+=" --port ${VLLM_PORT}"
[ -n "${VLLM_TP_SIZE:-}" ] && CMD+=" --tensor-parallel-size ${VLLM_TP_SIZE}"
[ -n "${VLLM_DTYPE:-}" ] && CMD+=" --dtype ${VLLM_DTYPE}"
[ -n "${VLLM_MAX_MODEL_LEN:-}" ] && CMD+=" --max-model-len ${VLLM_MAX_MODEL_LEN}"
[ -n "${VLLM_MAX_NUM_SEQS:-}" ] && CMD+=" --max-num-seqs ${VLLM_MAX_NUM_SEQS}"
[ -n "${VLLM_GPU_UTIL:-}" ] && CMD+=" --gpu-memory-utilization ${VLLM_GPU_UTIL}"
[ -n "${VLLM_QUANTIZATION:-}" ] && CMD+=" --quantization ${VLLM_QUANTIZATION}"
[ -n "${VLLM_LOAD_FORMAT:-}" ] && CMD+=" --load-format ${VLLM_LOAD_FORMAT}"
# VLLM_API_KEY is read automatically by vLLM, not passed as an argument.
[ -n "${VLLM_SERVED_NAME:-}" ] && CMD+=" --served-model-name ${VLLM_SERVED_NAME}"
[ -n "${VLLM_SERVED_NAME:-}" ] || CMD+=" --served-model-name ${MODEL_NAME}"
[ -n "${VLLM_SWAP_SPACE:-}" ] && CMD+=" --swap-space ${VLLM_SWAP_SPACE}"

# Add any extra arguments at the end if populated.
[ -n "${VLLM_EXTRA_ARGS:-}" ] && CMD+=" ${VLLM_EXTRA_ARGS}"

# Execute the final command.
echo "------------------------------------"
echo "Executing vLLM with command:"
echo "${CMD}"
echo "------------------------------------"
exec ${CMD}
