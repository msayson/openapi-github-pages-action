#!/usr/bin/env bash
#
# This script generates ReDoc API documentation
# for a given OpenAPI JSON spec file.
#
# Pre-requisites:
# 1. jq has been installed, ref: https://jqlang.github.io/jq/download/
# 2. yq has been installed, ref: https://github.com/mikefarah/yq
# 3. (If specify Git branch to retrieve OpenAPI specs from) gh has been installed, ref: https://github.com/cli/cli#installation
#    - Once installed, set up your credentials via `gh auth login`
# 4. redoc-cli has been installed, ref: https://github.com/Redocly/redoc
#    - eg. `npm install -g @redocly/cli`
set -e

apiConfig=$(echo $1 | jq)

branchToFetchApiSpecFrom=$(echo $apiConfig | jq -r .branch)
commandToGenerateApiSpec=$(echo $apiConfig | jq -r .\"generate-api-spec-command\")
openApiJsonFilepath=$(echo $apiConfig | jq -r .\"openapi-json-filepath\")
apiDocFilepath=$(echo $apiConfig | jq -r .\"api-doc-filepath\")

# Validate required config parameters
if [ "${openApiJsonFilepath}" = "null" ]; then
    echo "Failed to generate API doc since missing openapi-json-filepath in API config '$apiConfig'"
    exit 1
fi
if [ "${apiDocFilepath}" = "null" ]; then
    echo "Failed to generate API doc since missing api-doc-filepath in API config '$apiDocFilepath'"
    exit 1
fi

# Fetch OpenAPI JSON spec if provided branch config
cd $WORKSPACE_DIR
if [ "${branchToFetchApiSpecFrom}" = "null" ]; then
    echo "No Git branch provided for API spec, falling back to local directory"

    if [ "${commandToGenerateApiSpec}" != "null" ]; then
        echo "Running $commandToGenerateApiSpec to generate OpenAPI JSON spec"
        eval $commandToGenerateApiSpec
    fi
else
    if ! command -v gh &> /dev/null; then
        echo "Failed to fetch API spec files since gh was not installed"
        exit 1
    fi

    echo "Fetching API spec file $openApiJsonFilepath from branch $branchToFetchApiSpecFrom"

    apiSpecFetchUri="/repos/$GH_ACTION_REPOSITORY/contents/$openApiJsonFilepath?ref=$branchToFetchApiSpecFrom"
    echo "Submitting gh api request to endpoint $apiSpecFetchUri"

    # Ref: https://docs.github.com/en/rest/repos/contents?apiVersion=2022-11-28#get-repository-content
    gh api \
        -H "Accept: application/vnd.github.raw+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        $apiSpecFetchUri > $openApiJsonFilepath
fi

# Go to the source directory if provided
if [ -n "$SRC_DIR" ]; then
    echo "Changing directory to SRC_DIR: $SRC_DIR"
    cd "${SRC_DIR}"
fi

# Validate OpenAPI JSON spec exists
if [ ! -f "$openApiJsonFilepath" ]; then
    echo "Failed to generate API documentation since API spec was not found at $openApiJsonFilepath"
    exit 1
fi

# Generate OpenAPI YAML spec from the existing JSON
uniqueId=($(md5sum $openApiJsonFilepath))
openApiYamlDir="$WORKSPACE_DIR/build/tmp/$branchToFetchApiSpecFrom-$uniqueId/openapi-yaml"
openApiYamlFilepath="$openApiYamlDir/openapi.yaml"
mkdir -p $openApiYamlDir
echo "Converting OpenAPI JSON spec file $openApiJsonFilepath to YAML"
yq eval -P $openApiJsonFilepath -o yaml > $openApiYamlFilepath
echo "Successfully generated OpenAPI YAML spec file at $openApiYamlFilepath"

# Generate API documentation from the OpenAPI YAML spec
fullyQualifiedApiFilepath="$WORKSPACE_DIR/$API_DOCS_DIR/$apiDocFilepath"
apiFileDir=$(dirname $fullyQualifiedApiFilepath)
mkdir -p $apiFileDir
echo "Generating ReDoc API docs at $fullyQualifiedApiFilepath"
npx @redocly/cli build-docs $openApiYamlFilepath -o $fullyQualifiedApiFilepath

if [ ! -f "$fullyQualifiedApiFilepath" ]; then
    echo "Failed to generate API documentation, generated doc not found at $fullyQualifiedApiFilepath"
    exit 1
else
    echo "Successfully generated API documentation at $fullyQualifiedApiFilepath"
fi
