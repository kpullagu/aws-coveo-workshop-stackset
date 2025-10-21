# Multi-stage Dockerfile for React frontend with Node.js backend
FROM node:18-alpine AS build

# Set working directory for React build
WORKDIR /app/client

# Copy React app package files
COPY client/package.json ./
RUN npm install

# Copy React app source
COPY client/src ./src
COPY client/public ./public

# Build React app
RUN npm run build

# Production stage
FROM node:18-alpine AS production

# Set working directory
WORKDIR /app

# Copy backend package files
COPY package*.json ./
RUN npm install --only=production

# Copy backend source
COPY server.js ./

# Note: .env is copied from parent directory during docker build
# Use: docker build -f frontend/Dockerfile -t workshop-ui .

# Copy built React app from build stage
COPY --from=build /app/client/build ./client/build

# Create non-root user
RUN addgroup -g 1001 -S nodejs
RUN adduser -S nextjs -u 1001

# Change ownership of the app directory
RUN chown -R nextjs:nodejs /app
USER nextjs

# Expose port
EXPOSE 3003

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:3003/health || exit 1

# Start the application
CMD ["node", "server.js"]