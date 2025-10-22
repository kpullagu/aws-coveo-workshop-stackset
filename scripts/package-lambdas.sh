#!/bin/bash
# Bash script to package all Lambda functions and upload to S3
# Usage: bash scripts/package-lambdas.sh <bucket-name> [region] [--force]

# Don't exit on error for counting operations
set +e  # Allow errors for increment operations
set -o pipefail  # But still catch pipe failures

BUCKET_NAME="${1:-}"
REGION="${2:-us-east-1}"
FORCE_BUILD=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_BUILD=true
            shift
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        *)
            if [ -z "$BUCKET_NAME" ]; then
                BUCKET_NAME="$1"
            fi
            shift
            ;;
    esac
done

if [ -z "$BUCKET_NAME" ]; then
    echo "❌ ERROR: Bucket name required"
    echo "Usage: bash scripts/package-lambdas.sh <bucket-name> [region] [--force]"
    echo ""
    echo "Options:"
    echo "  --force    Force rebuild all Lambdas (skip change detection)"
    exit 1
fi

echo "====================================="
echo "Lambda Function Packaging & Upload"
echo "====================================="
echo "Force build: $FORCE_BUILD"
echo ""

# Check if Lambda Layer exists (dependencies will be in layer)
LAYER_ARN=$(aws ssm get-parameter \
    --name "/workshop/lambda-layer-arn" \
    --query "Parameter.Value" \
    --output text \
    --region "$REGION" 2>/dev/null || echo "")

if [ -n "$LAYER_ARN" ]; then
    echo "✅ Lambda Layer found: Using layer for dependencies"
    echo "   Layer ARN: $LAYER_ARN"
    USE_LAYER=true
else
    echo "ℹ️  No Lambda Layer found: Will bundle dependencies with Lambdas"
    USE_LAYER=false
fi
echo ""

# Lambda functions to package
LAMBDA_FUNCTIONS=(
    "search_proxy"
    "passages_proxy"
    "answering_proxy"
    "query_suggest_proxy"
    "html_proxy"
    "coveo_passage_tool_py"
    "agentcore_runtime_py"
    "bedrock_agent_chat"
)

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$PROJECT_ROOT/temp_lambda_packages"

# Create temp directory
if [ -d "$TEMP_DIR" ]; then
    echo "🧹 Cleaning existing temp directory..."
    rm -rf "$TEMP_DIR"
fi
mkdir -p "$TEMP_DIR"

SUCCESS_COUNT=0
FAIL_COUNT=0

for FUNC_NAME in "${LAMBDA_FUNCTIONS[@]}"; do
    echo ""
    echo "📦 Packaging: $FUNC_NAME"
    echo "-----------------------------------"
    
    SOURCE_DIR="$PROJECT_ROOT/lambdas/$FUNC_NAME"
    ZIP_FILE="$TEMP_DIR/${FUNC_NAME}.zip"
    S3_KEY="lambdas/${FUNC_NAME}.zip"
    
    # Check if source directory exists
    if [ ! -d "$SOURCE_DIR" ]; then
        echo "❌ ERROR: Source directory not found: $SOURCE_DIR"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi
    
    # Check if lambda_function.py exists
    if [ ! -f "$SOURCE_DIR/lambda_function.py" ]; then
        echo "❌ ERROR: lambda_function.py not found in $SOURCE_DIR"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi
    
    # Skip if not forced and Lambda hasn't changed
    if [ "$FORCE_BUILD" = false ]; then
        # Check if S3 object exists and get its last modified time
        S3_MODIFIED=$(aws s3api head-object \
            --bucket "$BUCKET_NAME" \
            --key "$S3_KEY" \
            --region "$REGION" \
            --query 'LastModified' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$S3_MODIFIED" ]; then
            # Check if source files are newer than S3 object
            NEWEST_FILE=$(find "$SOURCE_DIR" -type f -name "*.py" -o -name "requirements.txt" | xargs ls -t | head -1)
            if [ -n "$NEWEST_FILE" ]; then
                # Compare modification times (simplified check)
                LOCAL_MODIFIED=$(stat -c %Y "$NEWEST_FILE" 2>/dev/null || stat -f %m "$NEWEST_FILE" 2>/dev/null || echo "0")
                S3_EPOCH=$(date -d "$S3_MODIFIED" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "$S3_MODIFIED" +%s 2>/dev/null || echo "0")
                
                if [ "$LOCAL_MODIFIED" -lt "$S3_EPOCH" ]; then
                    echo "  ⏭️  Skipping (no changes detected)"
                    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                    continue
                fi
            fi
        fi
    fi
    
    # Create a temporary build directory for this Lambda
    BUILD_DIR="$TEMP_DIR/${FUNC_NAME}_build"
    mkdir -p "$BUILD_DIR"
    
    # Copy Lambda code to build directory
    echo "  ▶ Copying Lambda code..."
    cp -r "$SOURCE_DIR"/* "$BUILD_DIR/"
    
    # Install dependencies only if Lambda Layer is not being used
    if [ "$USE_LAYER" = false ] && [ -f "$BUILD_DIR/requirements.txt" ]; then
        echo "  ▶ Installing dependencies from requirements.txt..."
        pip install -q -r "$BUILD_DIR/requirements.txt" -t "$BUILD_DIR/" --upgrade 2>/dev/null || {
            echo "  ⚠️  Warning: pip install failed, trying with --no-deps..."
            pip install -q -r "$BUILD_DIR/requirements.txt" -t "$BUILD_DIR/" --no-deps 2>/dev/null || {
                echo "  ⚠️  Warning: Could not install dependencies"
            }
        }
    elif [ "$USE_LAYER" = true ]; then
        echo "  ⏭️  Skipping dependencies (using Lambda Layer)"
    fi
    
    # Create ZIP file from build directory
    echo "  ▶ Creating ZIP: $ZIP_FILE"
    
    cd "$BUILD_DIR"
    zip -q -r "$ZIP_FILE" . -x "*.pyc" -x "__pycache__/*" -x ".DS_Store" -x "requirements.txt"
    cd "$PROJECT_ROOT"
    
    # Clean up build directory
    rm -rf "$BUILD_DIR"
    
    # Check ZIP was created
    if [ ! -f "$ZIP_FILE" ]; then
        echo "❌ ERROR: ZIP file was not created"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi
    
    ZIP_SIZE=$(du -h "$ZIP_FILE" | cut -f1)
    echo "  ✅ ZIP created: $ZIP_SIZE"
    
    # Upload to S3
    echo "  ▶ Uploading to S3: s3://$BUCKET_NAME/$S3_KEY"
    
    if aws s3 cp "$ZIP_FILE" "s3://$BUCKET_NAME/$S3_KEY" --region "$REGION"; then
        echo "  ✅ Uploaded successfully"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "  ❌ ERROR: S3 upload failed"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

# Cleanup temp directory
echo ""
echo "🧹 Cleaning up temp directory..."
rm -rf "$TEMP_DIR"

# Summary
echo ""
echo "====================================="
echo "Summary"
echo "====================================="
TOTAL_COUNT=${#LAMBDA_FUNCTIONS[@]}
echo "✅ Successfully packaged: $SUCCESS_COUNT / $TOTAL_COUNT"

if [ $FAIL_COUNT -gt 0 ]; then
    echo "❌ Failed: $FAIL_COUNT / $TOTAL_COUNT"
fi

echo ""
echo "S3 Bucket: s3://$BUCKET_NAME/lambdas/"
echo ""

# Verify uploads
echo "Verifying S3 uploads..."
aws s3 ls "s3://$BUCKET_NAME/lambdas/" --region "$REGION" || true

echo ""
if [ $FAIL_COUNT -eq 0 ]; then
    echo "🎉 All Lambda functions packaged and uploaded successfully!"
    exit 0
else
    echo "⚠️ Some Lambda functions failed to package/upload"
    exit 1
fi
