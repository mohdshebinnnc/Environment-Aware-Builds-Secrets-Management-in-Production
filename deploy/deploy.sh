#!/bin/bash

##############################################################################
# QuickServe Deployment Script
# This script deploys the QuickServe application to AWS ECS with rollback
# capability and comprehensive health checks.
##############################################################################

set -e  # Exit on error
set -o pipefail  # Exit on pipe failure

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER="${ECS_CLUSTER:-quickserve-cluster}"
SERVICE="${ECS_SERVICE:-quickserve-service}"
IMAGE_TAG="${1:-latest}"
TASK_DEF_FILE="deploy/aws-task-definition.json"
MAX_WAIT_TIME=600  # 10 minutes

# Functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured properly."
        exit 1
    fi
    
    # Check if task definition file exists
    if [ ! -f "$TASK_DEF_FILE" ]; then
        log_error "Task definition file not found: $TASK_DEF_FILE"
        exit 1
    fi
    
    log_success "Prerequisites validated"
}

# Get current task definition
get_current_task_definition() {
    log_info "Getting current task definition..."
    
    CURRENT_TASK_DEF=$(aws ecs describe-services \
        --cluster "$CLUSTER" \
        --services "$SERVICE" \
        --query 'services[0].taskDefinition' \
        --output text 2>/dev/null)
    
    if [ -z "$CURRENT_TASK_DEF" ] || [ "$CURRENT_TASK_DEF" == "None" ]; then
        log_warning "No existing task definition found. This might be a first deployment."
        CURRENT_TASK_DEF=""
    else
        log_success "Current task definition: $CURRENT_TASK_DEF"
    fi
}

# Register new task definition
register_task_definition() {
    log_info "Registering new task definition..."
    
    # Create temporary file with substituted values
    TEMP_TASK_DEF=$(mktemp)
    cp "$TASK_DEF_FILE" "$TEMP_TASK_DEF"
    
    # Get ECR registry URL
    ECR_REGISTRY=$(aws ecr describe-repositories \
        --repository-names quickserve \
        --query 'repositories[0].repositoryUri' \
        --output text | cut -d'/' -f1)
    
    # Substitute placeholders
    sed -i.bak "s|\${ECR_REGISTRY}|$ECR_REGISTRY|g" "$TEMP_TASK_DEF"
    sed -i.bak "s|\${IMAGE_TAG}|$IMAGE_TAG|g" "$TEMP_TASK_DEF"
    
    # Register task definition
    NEW_TASK_DEF=$(aws ecs register-task-definition \
        --cli-input-json file://"$TEMP_TASK_DEF" \
        --query 'taskDefinition.taskDefinitionArn' \
        --output text)
    
    # Cleanup
    rm -f "$TEMP_TASK_DEF" "$TEMP_TASK_DEF.bak"
    
    if [ -z "$NEW_TASK_DEF" ]; then
        log_error "Failed to register new task definition"
        exit 1
    fi
    
    log_success "New task definition registered: $NEW_TASK_DEF"
}

# Update ECS service
update_service() {
    log_info "Updating ECS service..."
    
    aws ecs update-service \
        --cluster "$CLUSTER" \
        --service "$SERVICE" \
        --task-definition "$NEW_TASK_DEF" \
        --force-new-deployment \
        --output json > /dev/null
    
    log_success "Service update initiated"
}

# Wait for service to stabilize
wait_for_stable_service() {
    log_info "Waiting for service to stabilize (max ${MAX_WAIT_TIME}s)..."
    
    if timeout "$MAX_WAIT_TIME" aws ecs wait services-stable \
        --cluster "$CLUSTER" \
        --services "$SERVICE"; then
        log_success "Service is stable"
        return 0
    else
        log_error "Service failed to stabilize within ${MAX_WAIT_TIME} seconds"
        return 1
    fi
}

# Run health checks
run_health_checks() {
    log_info "Running health checks..."
    
    # Get task ARNs
    TASK_ARNS=$(aws ecs list-tasks \
        --cluster "$CLUSTER" \
        --service-name "$SERVICE" \
        --desired-status RUNNING \
        --query 'taskArns' \
        --output text)
    
    if [ -z "$TASK_ARNS" ]; then
        log_error "No running tasks found"
        return 1
    fi
    
    # Check task health
    for TASK_ARN in $TASK_ARNS; do
        HEALTH_STATUS=$(aws ecs describe-tasks \
            --cluster "$CLUSTER" \
            --tasks "$TASK_ARN" \
            --query 'tasks[0].healthStatus' \
            --output text)
        
        log_info "Task health status: $HEALTH_STATUS"
        
        if [ "$HEALTH_STATUS" != "HEALTHY" ] && [ "$HEALTH_STATUS" != "UNKNOWN" ]; then
            log_warning "Task is not healthy: $TASK_ARN"
        fi
    done
    
    log_success "Health checks completed"
    return 0
}

# Rollback to previous version
rollback() {
    log_warning "Rolling back to previous task definition..."
    
    if [ -z "$CURRENT_TASK_DEF" ]; then
        log_error "No previous task definition to rollback to"
        return 1
    fi
    
    aws ecs update-service \
        --cluster "$CLUSTER" \
        --service "$SERVICE" \
        --task-definition "$CURRENT_TASK_DEF" \
        --force-new-deployment \
        --output json > /dev/null
    
    log_success "Rollback initiated"
    
    if wait_for_stable_service; then
        log_success "Rollback completed successfully"
        return 0
    else
        log_error "Rollback failed to stabilize"
        return 1
    fi
}

# Main deployment flow
main() {
    echo ""
    log_info "🚀 Starting QuickServe deployment"
    log_info "Cluster: $CLUSTER"
    log_info "Service: $SERVICE"
    log_info "Image Tag: $IMAGE_TAG"
    echo ""
    
    # Step 1: Validate
    validate_prerequisites
    
    # Step 2: Get current state
    get_current_task_definition
    
    # Step 3: Register new task definition
    register_task_definition
    
    # Step 4: Update service
    update_service
    
    # Step 5: Wait for stability
    if ! wait_for_stable_service; then
        log_error "Deployment failed!"
        rollback
        exit 1
    fi
    
    # Step 6: Health checks
    if ! run_health_checks; then
        log_warning "Health checks failed, but service is stable"
    fi
    
    echo ""
    log_success "🎉 Deployment completed successfully!"
    log_info "Image: $ECR_REGISTRY/quickserve:$IMAGE_TAG"
    log_info "Task Definition: $NEW_TASK_DEF"
    echo ""
}

# Run main function
main "$@"
