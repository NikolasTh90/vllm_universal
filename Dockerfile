# Use the official vLLM image as the base
FROM vllm/vllm-openai:latest

# Create a standard mount point for the persistent volume
RUN mkdir -p /root/.cache/huggingface

# Copy our startup script into the container
COPY start.sh /start.sh

# Make the script executable
RUN chmod +x /start.sh

# Set the script as the entrypoint. This will run automatically when the container starts.
ENTRYPOINT ["/start.sh"]

# Expose the vLLM API port
EXPOSE 8000