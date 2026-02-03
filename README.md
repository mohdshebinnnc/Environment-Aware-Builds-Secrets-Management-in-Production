# QuickServe CI/CD Deployment Loop - Case Study Analysis & Solution

## 📋 Executive Summary

This document analyzes the "Never-Ending Deployment Loop" issue at QuickServe, a food delivery startup experiencing persistent CI/CD pipeline failures. We identify root causes, explain the proper "chain of trust" in deployment workflows, and provide a comprehensive solution architecture.

---

## 🔍 Problem Analysis

### The Symptoms

QuickServe's deployment pipeline exhibits three critical failure patterns:

1. **"Environment variable not found"** - Runtime failures due to missing configuration
2. **"Port already in use"** - New containers cannot bind to required ports
3. **Version inconsistency** - Old containers persist alongside new deployments

### Root Cause Analysis

#### 1. **Environment Variable Mismanagement**

**What's Going Wrong:**

- Environment variables are hardcoded in Dockerfiles or not properly injected at runtime
- Secrets are committed to version control (security risk)
- Different environments (dev/staging/prod) use inconsistent variable names
- No validation of required variables before deployment

**Impact:**

- Application crashes on startup when accessing undefined variables
- Deployment succeeds but application fails health checks
- Rollback is triggered, but the issue persists in the next deployment

#### 2. **Port Conflicts & Container Lifecycle Issues**

**What's Going Wrong:**

- Old containers aren't gracefully stopped before new deployment
- No proper container cleanup in CI/CD pipeline
- Multiple containers attempt to bind to the same host port
- Container orchestration lacks proper health checks and readiness probes

**Impact:**

- New containers fail to start due to port binding errors
- Old and new versions run simultaneously, causing inconsistent responses
- Load balancers route traffic to both versions unpredictably

#### 3. **Broken Chain of Trust**

**What's Going Wrong:**

- No versioning strategy for Docker images (using `latest` tag)
- Missing validation steps between pipeline stages
- No rollback mechanism when deployment fails
- Lack of proper health checks and smoke tests post-deployment

**Impact:**

- Cannot identify which version is deployed
- Failed deployments leave infrastructure in unknown state
- No way to quickly revert to last known good version

---

## 🔗 The Chain of Trust: Proper Deployment Workflow

A robust CI/CD pipeline requires each stage to validate and hand off cleanly to the next:

```mermaid
graph LR
    A[Code Commit] -->|Trigger| B[Build Stage]
    B -->|Validate| C[Test Stage]
    C -->|Pass| D[Container Build]
    D -->|Tag & Push| E[Registry]
    E -->|Pull| F[Deployment]
    F -->|Health Check| G[Traffic Routing]
    G -->|Monitor| H[Production]

    B -.->|Fail| I[Notify Developer]
    C -.->|Fail| I
    F -.->|Fail| J[Rollback]
    G -.->|Fail| J
```

### Stage-by-Stage Breakdown

#### **Stage 1: Code Commit → Build**

- **Trigger**: Git push to main/release branch
- **Validation**: Linting, code quality checks
- **Hand-off**: Clean build artifacts
- **Failure Mode**: Build errors, dependency issues

#### **Stage 2: Build → Test**

- **Trigger**: Successful build completion
- **Validation**: Unit tests, integration tests
- **Hand-off**: Test coverage reports
- **Failure Mode**: Test failures, coverage below threshold

#### **Stage 3: Test → Container Build**

- **Trigger**: All tests pass
- **Validation**: Dockerfile syntax, security scanning
- **Hand-off**: Docker image with semantic version tag
- **Failure Mode**: Image build errors, security vulnerabilities

#### **Stage 4: Container Build → Registry**

- **Trigger**: Successful image build
- **Validation**: Image scanning, vulnerability assessment
- **Hand-off**: Signed, versioned image in registry
- **Failure Mode**: Push failures, authentication issues

#### **Stage 5: Registry → Deployment**

- **Trigger**: Image available in registry
- **Validation**: Environment variable validation, infrastructure checks
- **Hand-off**: Running container with proper configuration
- **Failure Mode**: Missing env vars, port conflicts, resource constraints

#### **Stage 6: Deployment → Environment Setup**

- **Trigger**: Container started successfully
- **Validation**: Health checks, readiness probes
- **Hand-off**: Healthy service ready for traffic
- **Failure Mode**: Application crashes, health check failures

#### **Stage 7: Environment Setup → Production Traffic**

- **Trigger**: Health checks pass
- **Validation**: Smoke tests, canary deployment validation
- **Hand-off**: Full production traffic routing
- **Failure Mode**: Performance degradation, error rate spikes

---

## ✅ Comprehensive Solution

### 1. Proper Containerization

#### **Multi-Stage Dockerfile**

```dockerfile
# Build stage - dependencies cached separately
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

# Production stage - minimal attack surface
FROM node:18-alpine
RUN addgroup -g 1001 -S nodejs && adduser -S nodejs -u 1001
WORKDIR /app
COPY --from=builder --chown=nodejs:nodejs /app/node_modules ./node_modules
COPY --chown=nodejs:nodejs . .
USER nodejs
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node healthcheck.js
CMD ["node", "server.js"]
```

**Key Improvements:**

- ✅ Multi-stage build reduces image size
- ✅ Non-root user for security
- ✅ Built-in health check
- ✅ Proper layer caching for faster builds

#### **.dockerignore**

```
node_modules
npm-debug.log
.git
.env*
!.env.example
*.md
.DS_Store
```

### 2. Environment Variable Handling

#### **Strategy: 12-Factor App Principles**

**Never Do:**

- ❌ Hardcode secrets in Dockerfile
- ❌ Commit `.env` files to git
- ❌ Use different variable names across environments

**Always Do:**

- ✅ Use environment-specific secret management (AWS Secrets Manager, Azure Key Vault)
- ✅ Validate required variables at startup
- ✅ Provide `.env.example` template in repository

#### **Implementation**

**.env.example** (committed to git):

```bash
# Application
NODE_ENV=production
PORT=3000
APP_NAME=QuickServe

# Database
DATABASE_URL=postgresql://user:password@host:5432/dbname

# AWS
AWS_REGION=us-east-1
S3_BUCKET_NAME=quickserve-uploads

# External APIs
STRIPE_API_KEY=sk_live_xxxxx
TWILIO_AUTH_TOKEN=xxxxx
```

**Startup Validation** (server.js):

```javascript
const requiredEnvVars = ["DATABASE_URL", "AWS_REGION", "STRIPE_API_KEY"];

requiredEnvVars.forEach((varName) => {
  if (!process.env[varName]) {
    console.error(`Missing required environment variable: ${varName}`);
    process.exit(1);
  }
});
```

### 3. CI/CD Pipeline Configuration

#### **GitHub Actions Workflow** (.github/workflows/deploy.yml)

```yaml
name: Deploy to AWS

on:
  push:
    branches: [main]

env:
  AWS_REGION: us-east-1
  ECR_REPOSITORY: quickserve
  ECS_SERVICE: quickserve-service
  ECS_CLUSTER: quickserve-cluster

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Run tests
        run: |
          npm ci
          npm test

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v1

      - name: Build and tag Docker image
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          IMAGE_TAG: ${{ github.sha }}
        run: |
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
          docker tag $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG \
                     $ECR_REGISTRY/$ECR_REPOSITORY:latest

      - name: Scan image for vulnerabilities
        run: |
          docker scan $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG

      - name: Push image to ECR
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          IMAGE_TAG: ${{ github.sha }}
        run: |
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:latest

      - name: Deploy to ECS
        run: |
          aws ecs update-service \
            --cluster $ECS_CLUSTER \
            --service $ECS_SERVICE \
            --force-new-deployment \
            --wait

      - name: Wait for deployment to stabilize
        run: |
          aws ecs wait services-stable \
            --cluster $ECS_CLUSTER \
            --services $ECS_SERVICE

      - name: Run smoke tests
        run: |
          ./scripts/smoke-test.sh
```

**Key Features:**

- ✅ Semantic versioning using git SHA
- ✅ Security scanning before deployment
- ✅ Graceful service updates with health checks
- ✅ Post-deployment validation

### 4. AWS ECS Configuration

#### **Task Definition** (deploy/aws-task-definition.json)

```json
{
  "family": "quickserve-task",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "containerDefinitions": [
    {
      "name": "quickserve-app",
      "image": "${ECR_REGISTRY}/quickserve:${IMAGE_TAG}",
      "portMappings": [
        {
          "containerPort": 3000,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "NODE_ENV",
          "value": "production"
        },
        {
          "name": "PORT",
          "value": "3000"
        }
      ],
      "secrets": [
        {
          "name": "DATABASE_URL",
          "valueFrom": "arn:aws:secretsmanager:us-east-1:xxx:secret:db-url"
        },
        {
          "name": "STRIPE_API_KEY",
          "valueFrom": "arn:aws:secretsmanager:us-east-1:xxx:secret:stripe-key"
        }
      ],
      "healthCheck": {
        "command": [
          "CMD-SHELL",
          "curl -f http://localhost:3000/health || exit 1"
        ],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      },
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/quickserve",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
```

**Key Features:**

- ✅ Secrets pulled from AWS Secrets Manager (not hardcoded)
- ✅ Health checks ensure container readiness
- ✅ Centralized logging for debugging
- ✅ Resource limits prevent runaway containers

### 5. Deployment Strategy: Blue-Green with Rollback

```bash
#!/bin/bash
# deploy/deploy.sh

set -e

CLUSTER="quickserve-cluster"
SERVICE="quickserve-service"
IMAGE_TAG="${1:-latest}"

echo "🚀 Deploying version: $IMAGE_TAG"

# Get current task definition
CURRENT_TASK_DEF=$(aws ecs describe-services \
  --cluster $CLUSTER \
  --services $SERVICE \
  --query 'services[0].taskDefinition' \
  --output text)

echo "📋 Current task definition: $CURRENT_TASK_DEF"

# Update task definition with new image
NEW_TASK_DEF=$(aws ecs register-task-definition \
  --cli-input-json file://deploy/aws-task-definition.json \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)

echo "📋 New task definition: $NEW_TASK_DEF"

# Update service
aws ecs update-service \
  --cluster $CLUSTER \
  --service $SERVICE \
  --task-definition $NEW_TASK_DEF \
  --force-new-deployment

echo "⏳ Waiting for deployment to stabilize..."

# Wait for service to become stable
if aws ecs wait services-stable \
  --cluster $CLUSTER \
  --services $SERVICE; then
  echo "✅ Deployment successful!"
else
  echo "❌ Deployment failed! Rolling back..."
  aws ecs update-service \
    --cluster $CLUSTER \
    --service $SERVICE \
    --task-definition $CURRENT_TASK_DEF
  exit 1
fi

# Run smoke tests
echo "🧪 Running smoke tests..."
if ./scripts/smoke-test.sh; then
  echo "✅ All smoke tests passed!"
else
  echo "❌ Smoke tests failed! Rolling back..."
  aws ecs update-service \
    --cluster $CLUSTER \
    --service $SERVICE \
    --task-definition $CURRENT_TASK_DEF
  exit 1
fi
```

---

## 🔧 Troubleshooting Guide

### Issue: "Environment variable not found"

**Diagnosis:**

```bash
# Check container environment
docker exec <container-id> env | grep DATABASE_URL

# Check ECS task definition
aws ecs describe-task-definition --task-definition quickserve-task \
  | jq '.taskDefinition.containerDefinitions[0].environment'
```

**Solution:**

1. Verify secrets exist in AWS Secrets Manager
2. Ensure IAM role has `secretsmanager:GetSecretValue` permission
3. Check task definition references correct secret ARN

### Issue: "Port already in use"

**Diagnosis:**

```bash
# Find process using port
lsof -i :3000

# List all running containers
docker ps -a

# Check ECS service tasks
aws ecs list-tasks --cluster quickserve-cluster --service-name quickserve-service
```

**Solution:**

1. Ensure old tasks are terminated before new deployment
2. Use ECS deployment configuration with `minimumHealthyPercent: 100` and `maximumPercent: 200`
3. Implement graceful shutdown in application

### Issue: Version inconsistency

**Diagnosis:**

```bash
# Check running container versions
docker ps --format "table {{.Image}}\t{{.Status}}"

# Check ECS task versions
aws ecs describe-tasks --cluster quickserve-cluster \
  --tasks $(aws ecs list-tasks --cluster quickserve-cluster \
  --service-name quickserve-service --query 'taskArns' --output text)
```

**Solution:**

1. Always use semantic versioning (git SHA or semver)
2. Never use `latest` tag in production
3. Implement proper task draining in ECS

---

## 📊 Monitoring & Observability

### Health Check Endpoint

```javascript
// healthcheck.js
const http = require("http");

const options = {
  host: "localhost",
  port: 3000,
  path: "/health",
  timeout: 2000,
};

const request = http.request(options, (res) => {
  if (res.statusCode === 200) {
    process.exit(0);
  } else {
    process.exit(1);
  }
});

request.on("error", () => process.exit(1));
request.end();
```

### Application Health Endpoint

```javascript
// server.js
app.get("/health", async (req, res) => {
  const health = {
    uptime: process.uptime(),
    timestamp: Date.now(),
    status: "OK",
    version: process.env.IMAGE_TAG || "unknown",
  };

  try {
    // Check database connectivity
    await db.query("SELECT 1");
    health.database = "connected";
  } catch (error) {
    health.database = "disconnected";
    health.status = "DEGRADED";
    return res.status(503).json(health);
  }

  res.status(200).json(health);
});
```

---

## 🎯 Best Practices Summary

### Docker

- ✅ Use multi-stage builds
- ✅ Run as non-root user
- ✅ Include health checks
- ✅ Optimize layer caching
- ✅ Use `.dockerignore`

### Environment Variables

- ✅ Never commit secrets to git
- ✅ Use secret management services
- ✅ Validate required variables at startup
- ✅ Provide `.env.example` template

### CI/CD Pipeline

- ✅ Run tests before deployment
- ✅ Use semantic versioning
- ✅ Scan images for vulnerabilities
- ✅ Implement health checks
- ✅ Enable automatic rollback

### Deployment

- ✅ Use blue-green or rolling deployments
- ✅ Implement graceful shutdown
- ✅ Monitor deployment metrics
- ✅ Run smoke tests post-deployment
- ✅ Maintain deployment history

---

## 📚 Additional Resources

- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [12-Factor App Methodology](https://12factor.net/)
- [AWS ECS Deployment Types](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-types.html)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)

---

## 🎬 Video Walkthrough

See [VIDEO_SCRIPT.md](file:///Users/shebin.cee/Kalvium/Sem%203/Livebook/Simulated%20Work/secrets%20management/VIDEO_SCRIPT.md) for the detailed presentation script covering:

- Live demonstration of the deployment loop problem
- Step-by-step solution implementation
- Complete CI/CD workflow walkthrough
- Best practices and recommendations
