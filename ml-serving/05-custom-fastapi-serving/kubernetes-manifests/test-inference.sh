#!/usr/bin/env bash
# =============================================================================
# FILE: ml-serving/05-custom-fastapi-serving/kubernetes-manifests/test-inference.sh
# PURPOSE: Send a test inference request to the deployed ML FastAPI server.
# =============================================================================

set -e
set -u

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

ENDPOINT="http://localhost:30001/api/v1/predict"

echo -e "${CYAN}Sending test prediction to ML Inference Server...${RESET}"
echo -e "Endpoint: ${YELLOW}${ENDPOINT}${RESET}\n"

# JSON payload matching the WineFeatures Pydantic schema
# These are realistic values for a Class 0 wine from the UCI dataset
PAYLOAD=$(cat <<EOF
{
  "alcohol": 14.23,
  "malic_acid": 1.71,
  "ash": 2.43,
  "alcalinity_of_ash": 15.6,
  "magnesium": 127.0,
  "total_phenols": 2.80,
  "flavanoids": 3.06,
  "nonflavanoid_phenols": 0.28,
  "proanthocyanins": 2.29,
  "color_intensity": 5.64,
  "hue": 1.04,
  "od280_od315_of_diluted_wines": 3.92,
  "proline": 1065.0
}
EOF
)

# Use curl to send the POST request
# -s : silent
# -w : write-out format (getting HTTP status code)
echo -e "${BOLD}Request Payload:${RESET}"
echo "$PAYLOAD" | jq . || echo "$PAYLOAD"
echo ""

echo -e "${BOLD}Response:${RESET}"
HTTP_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST "${ENDPOINT}" \
  -H "Content-Type: application/json" \
  -d "${PAYLOAD}")

# Parse the body and the status code from the curl output
HTTP_BODY=$(echo "$HTTP_RESPONSE" | sed -e 's/HTTP_STATUS\:.*//g')
HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tr -d '\n' | sed -e 's/.*HTTP_STATUS://')

if [ "$HTTP_STATUS" -eq 200 ]; then
    echo -e "${GREEN}Success! HTTP $HTTP_STATUS${RESET}"
    echo "$HTTP_BODY" | jq . || echo "$HTTP_BODY"
else
    echo -e "\033[0;31mFailed! HTTP $HTTP_STATUS\033[0m"
    echo "$HTTP_BODY"
    exit 1
fi
