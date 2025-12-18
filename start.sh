#!/bin/bash
# Exit immediately if a command exits with a non-zero status.
set -e

# The model name MUST be the first argument passed to vllm serve.
MODEL_NAME="${VLLM_MODEL_NAME:-mistralai/Mistral-7B-Instruct-v0.3}"

# Build the command from environment variables.
CMD="vllm serve ${MODEL_NAME}"
CMD+=" --host ${VLLM_HOST:-0.0.0.0}"
CMD+=" --port ${VLLM_PORT:-8000}"
CMD+=" --tensor-parallel-size ${VLLM_TP_SIZE:-1}"
CMD+=" --dtype ${VLLM_DTYPE:-auto}"
CMD+=" --max-model-len ${VLLM_MAX_MODEL_LEN:-8192}"
CMD+=" --max-num-seqs ${VLLM_MAX_NUM_SEQS:-256}"
CMD+=" --gpu-memory-utilization ${VLLM_GPU_UTIL:-0.95}"
CMD+=" --quantization ${VLLM_QUANTIZATION:-none}"
CMD+=" --load-format ${VLLM_LOAD_FORMAT:-auto}"
# VLLM_API_KEY is read automatically by vLLM, not passed as an argument.
CMD+=" --served-model-name ${VLLM_SERVED_NAME:-${MODEL_NAME}}"
CMD+=" --swap-space ${VLLM_SWAP_SPACE:-4}"

# Conditionally add the --enforce-eager flag if VLLM_EXTRA_ARGS is not set.
if [ -z "${VLLM_EXTRA_ARGS}" ]; then
  CMD+=" --enforce-eager"
fi

# Add any extra arguments at the end.
CMD+=" ${VLLM_EXTRA_ARGS}"

# Execute the final command.
echo "------------------------------------"
echo "Executing vLLM with command:"
echo "${CMD}"
echo "------------------------------------"
exec ${CMD}