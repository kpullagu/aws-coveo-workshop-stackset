#!/bin/bash
# Create a Lambda Layer with shared dependencies
# This significantly speeds up Lambda deployments

set -e

REGION="${1:-us-east-1}"
STACK_PREFIX="workshop"
LAYER_NAME="${STACK_PREFIX}-python-dependencies"

echo "====================================="
echo "Creating Lambda Layer"
echo "====================================="
echo "Layer Name: $LAYER_NAME"
echo "Region: $REGION"
echo ""

# Create temp directory
TEMP_DIR="./temp_lambda_layer"
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR/python"

# Create requirements file with common dependencies
cat > "$TEMP_DIR/requirements.txt" << 'EOF'
# Common dependencies for all Lambdas
boto3>=1.26.0
urllib3>=1.26.0,<2.0.0
requests>=2.28.0
EOF

echo "📦 Installing dependencies..."
pip install -r "$TEMP_DIR/requirements.txt" -t "$TEMP_DIR/python/" --upgrade --no-cache-dir 2>&1 | grep -v "Requirement already satisfied" || true

# Check if dependencies were installed
if [ ! -d "$TEMP_DIR/python" ] || [ -z "$(ls -A $TEMP_DIR/python)" ]; then
    echo "❌ ERROR: Dependencies were not installed"
    echo "   The python/ directory is empty"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "  ✅ Dependencies installed"

# Create ZIP
ZIP_FILE="./lambda-layer.zip"
cd "$TEMP_DIR"

# Check if python directory has files
if [ ! -d "python" ] || [ -z "$(ls -A python)" ]; then
    echo "❌ ERROR: python/ directory is empty, cannot create layer"
    cd ..
    rm -rf "$TEMP_DIR"
    exit 1
fi

zip -r "../$ZIP_FILE" python/
cd ..

# Check if ZIP was created
if [ ! -f "$ZIP_FILE" ]; then
    echo "❌ ERROR: ZIP file was not created"
    rm -rf "$TEMP_DIR"
    exit 1
fi

ZIP_SIZE=$(du -h "$ZIP_FILE" | cut -f1)
echo "  ✅ Layer ZIP created: $ZIP_SIZE"

# Publish Lambda Layer
echo ""
echo "📤 Publishing Lambda Layer..."
LAYER_VERSION=$(aws lambda publish-layer-version \
    --layer-name "$LAYER_NAME" \
    --description "Shared Python dependencies for workshop Lambdas (boto3, requests, urllib3)" \
    --zip-file "fileb://$ZIP_FILE" \
    --compatible-runtimes python3.9 python3.10 python3.11 python3.12 \
    --region "$REGION" \
    --query 'Version' \
    --output text)

echo "  ✅ Layer published: Version $LAYER_VERSION"

# Get Layer ARN
LAYER_ARN=$(aws lambda list-layer-versions \
    --layer-name "$LAYER_NAME" \
    --region "$REGION" \
    --query 'LayerVersions[0].LayerVersionArn' \
    --output text)

echo "  ✅ Layer ARN: $LAYER_ARN"

# Store Layer ARN in SSM for easy reference
echo ""
echo "💾 Storing Layer ARN in SSM..."
aws ssm put-parameter \
    --name "/${STACK_PREFIX}/lambda-layer-arn" \
    --value "$LAYER_ARN" \
    --type String \
    --overwrite \
    --region "$REGION" > /dev/null

echo "  ✅ Stored in SSM: /${STACK_PREFIX}/lambda-layer-arn"

# Cleanup
rm -rf "$TEMP_DIR" "$ZIP_FILE"

echo ""
echo "====================================="
echo "🎉 Lambda Layer Created!"
echo "====================================="
echo ""
echo "Layer ARN: $LAYER_ARN"
echo "Version: $LAYER_VERSION"
echo ""
echo "Next Steps:"
echo "1. Update CloudFormation templates to use this layer"
echo "2. Remove dependencies from Lambda requirements.txt files"
echo "3. Redeploy Lambdas (they'll be much smaller and faster)"
echo ""
echo "To attach this layer to a Lambda:"
echo "  aws lambda update-function-configuration \\"
echo "    --function-name <function-name> \\"
echo "    --layers $LAYER_ARN \\"
echo "    --region $REGION"
echo ""
