# Z.U.L.U. Backend - Zcash Relay on Starknet
FROM node:20-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    curl \
    bash \
    jq \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install Starknet Foundry (sncast)
RUN curl -L https://raw.githubusercontent.com/foundry-rs/starknet-foundry/master/scripts/install.sh | sh
ENV PATH="/root/.local/bin:$PATH"
RUN snfoundryup

# Set working directory
WORKDIR /app

# Copy package files first (for better caching)
COPY backend/package*.json ./backend/
RUN cd backend && npm install

# Copy Python requirements and install
COPY scripts/requirements.txt ./scripts/
RUN python3 -m pip install --break-system-packages -r scripts/requirements.txt

# Copy the rest of the application
COPY backend/ ./backend/
COPY scripts/ ./scripts/
COPY frontend/src/data/ ./frontend/src/data/

# Create the starknet accounts directory and file
RUN mkdir -p /root/.starknet_accounts

# Create persistent data directory (will be mounted as Railway volume)
RUN mkdir -p /app/data

# The accounts file will be created from env var at runtime
# Copy a template that will be populated by entrypoint
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Make scripts executable
RUN chmod +x scripts/*.sh 2>/dev/null || true

# Expose port
EXPOSE 3001

# Set environment
ENV NODE_ENV=production
ENV PORT=3001

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["node", "backend/index.js"]
