#!/bin/bash

# netbird peer group manager
# grabs local FQDN, finds peer ID, shows current groups, allows join/leave

set -euo pipefail

# load .env if it exists
[[ -f .env ]] && source .env

# check if TOKEN is set
if [[ -z "${NETBIRD_TOKEN:-}" ]]; then
    echo "error: NETBIRD_TOKEN environment variable not set"
    echo "add NETBIRD_TOKEN=<your_token> to .env file"
    exit 1
fi
# extract FQDN from netbird status
echo "[+] getting local FQDN..."
FQDN=$(netbird status -d | grep "^FQDN:" | awk '{print $2}')

if [[ -z "$FQDN" ]]; then
    echo "error: couldn't extract FQDN from netbird status"
    exit 1
fi

echo "[+] found FQDN: $FQDN"

# hit the API for peer data
echo "[+] querying netbird API for peers..."
PEER_RESPONSE=$(curl -s -X GET https://api.netbird.io/api/peers \
    -H 'Accept: application/json' \
    -H "Authorization: Token $NETBIRD_TOKEN")

if [[ $? -ne 0 ]]; then
    echo "error: peer API request failed"
    exit 1
fi

# parse JSON to find matching peer info
echo "[+] parsing peer data..."
PEER_DATA=$(echo "$PEER_RESPONSE" | jq ".[] | select(.dns_label == \"$FQDN\")")
PEER_ID=$(echo "$PEER_DATA" | jq -r ".id")
PEER_NAME=$(echo "$PEER_DATA" | jq -r ".name")

if [[ -z "$PEER_ID" || "$PEER_ID" == "null" ]]; then
    echo "error: no peer found with FQDN $FQDN"
    exit 1
fi

echo "[+] peer ID: $PEER_ID (name: $PEER_NAME)"

# show current groups with numbering
echo "[+] current groups:"
declare -a CURRENT_GROUP_IDS=()
declare -a CURRENT_GROUP_NAMES=()
counter=1

CURRENT_GROUPS_JSON=$(echo "$PEER_DATA" | jq -r '.groups[]')
if [[ -n "$CURRENT_GROUPS_JSON" && "$CURRENT_GROUPS_JSON" != "null" ]]; then
    while IFS='|' read -r group_id group_name peer_count; do
        printf "  %2d. %-20s (%d peers)\n" "$counter" "$group_name" "$peer_count"
        CURRENT_GROUP_IDS+=("$group_id")
        CURRENT_GROUP_NAMES+=("$group_name")
        ((counter++))
    done < <(echo "$PEER_DATA" | jq -r '.groups[] | "\(.id)|\(.name)|\(.peers_count)"')
else
    echo "  - none"
fi

# ask about leaving groups
if [[ ${#CURRENT_GROUP_IDS[@]} -gt 0 ]]; then
    echo ""
    read -p "leave a group? select number (1-$((counter-1))/n): " leave_choice
    
    if [[ "$leave_choice" != "n" && "$leave_choice" != "N" && -n "$leave_choice" ]]; then
        # validate number input
        if ! [[ "$leave_choice" =~ ^[0-9]+$ ]] || [[ "$leave_choice" -lt 1 ]] || [[ "$leave_choice" -gt $((counter-1)) ]]; then
            echo "error: invalid selection. must be between 1 and $((counter-1))"
            exit 1
        fi
        
        # get selected group info
        LEAVE_INDEX=$((leave_choice-1))
        LEAVE_GROUP_ID="${CURRENT_GROUP_IDS[$LEAVE_INDEX]}"
        LEAVE_GROUP_NAME="${CURRENT_GROUP_NAMES[$LEAVE_INDEX]}"
        
        echo "[+] leaving group: $LEAVE_GROUP_NAME (id: $LEAVE_GROUP_ID)"
        
        # get current group configuration
        echo "[+] fetching group details..."
        GROUP_CONFIG=$(curl -s -X GET "https://api.netbird.io/api/groups/$LEAVE_GROUP_ID" \
            -H 'Accept: application/json' \
            -H "Authorization: Token $NETBIRD_TOKEN")
        
        if [[ $? -ne 0 ]]; then
            echo "error: failed to fetch group details"
            exit 1
        fi
        
        GROUP_NAME=$(echo "$GROUP_CONFIG" | jq -r '.name')
        
        # remove our peer from the group
        UPDATED_PEERS=$(echo "$GROUP_CONFIG" | jq --arg peer_id "$PEER_ID" '.peers // [] | map(.id) | map(select(. != $peer_id))')
        UPDATED_RESOURCES=$(echo "$GROUP_CONFIG" | jq '.resources // []')
        
        # send PUT request to update group
        echo "[+] updating group membership..."
        PAYLOAD=$(jq -n \
            --arg name "$GROUP_NAME" \
            --argjson peers "$UPDATED_PEERS" \
            --argjson resources "$UPDATED_RESOURCES" \
            '{name: $name, peers: $peers, resources: $resources}')
        
        UPDATE_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X PUT "https://api.netbird.io/api/groups/$LEAVE_GROUP_ID" \
            -H 'Accept: application/json' \
            -H 'Content-Type: application/json' \
            -H "Authorization: Token $NETBIRD_TOKEN" \
            --data-raw "$PAYLOAD")
        
        HTTP_STATUS=$(echo "$UPDATE_RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
        RESPONSE_BODY=$(echo "$UPDATE_RESPONSE" | sed '/HTTP_STATUS:/d')
        
        if [[ "$HTTP_STATUS" -eq 200 ]]; then
            echo "[+] successfully left group: $GROUP_NAME"
        else
            echo "error: failed to leave group (HTTP $HTTP_STATUS)"
            echo "response: $RESPONSE_BODY"
            exit 1
        fi
        exit 0
    fi
fi

# get all available groups
echo "[+] fetching all groups..."
GROUPS_RESPONSE=$(curl -s -X GET https://api.netbird.io/api/groups \
    -H 'Accept: application/json' \
    -H "Authorization: Token $NETBIRD_TOKEN")

if [[ $? -ne 0 ]]; then
    echo "error: groups API request failed"
    exit 1
fi

# show available groups (excluding current ones) with numbering
echo ""
echo "[+] available groups:"

# create current group IDs string for filtering
CURRENT_GROUP_IDS_STR=""
for gid in "${CURRENT_GROUP_IDS[@]}"; do
    CURRENT_GROUP_IDS_STR+=" $gid "
done

# create arrays for group selection
declare -a AVAILABLE_GROUP_IDS=()
declare -a AVAILABLE_GROUP_NAMES=()
counter=1

while IFS='|' read -r group_id group_name peer_count; do
    if [[ ! "$CURRENT_GROUP_IDS_STR" =~ " $group_id " ]]; then
        printf "  %2d. %-20s (%d peers)\n" "$counter" "$group_name" "$peer_count"
        AVAILABLE_GROUP_IDS+=("$group_id")
        AVAILABLE_GROUP_NAMES+=("$group_name")
        ((counter++))
    fi
done < <(echo "$GROUPS_RESPONSE" | jq -r '.[] | "\(.id)|\(.name)|\(.peers_count)"')

if [[ ${#AVAILABLE_GROUP_IDS[@]} -eq 0 ]]; then
    echo "  - no additional groups available"
    exit 0
fi

echo ""
read -p "join a group? select number (1-$((counter-1))/n): " choice

if [[ "$choice" == "n" || "$choice" == "N" || -z "$choice" ]]; then
    echo "[+] exiting without changes"
    exit 0
fi

# validate number input
if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt $((counter-1)) ]]; then
    echo "error: invalid selection. must be between 1 and $((counter-1))"
    exit 1
fi

# get selected group info
SELECTED_INDEX=$((choice-1))
SELECTED_GROUP_ID="${AVAILABLE_GROUP_IDS[$SELECTED_INDEX]}"
SELECTED_GROUP_NAME="${AVAILABLE_GROUP_NAMES[$SELECTED_INDEX]}"

echo "[+] joining group: $SELECTED_GROUP_NAME (id: $SELECTED_GROUP_ID)"

# get current group configuration
echo "[+] fetching group details..."
GROUP_CONFIG=$(curl -s -X GET "https://api.netbird.io/api/groups/$SELECTED_GROUP_ID" \
    -H 'Accept: application/json' \
    -H "Authorization: Token $NETBIRD_TOKEN")

if [[ $? -ne 0 ]]; then
    echo "error: failed to fetch group details"
    exit 1
fi

GROUP_NAME=$(echo "$GROUP_CONFIG" | jq -r '.name')

# add our peer to the group (peers array contains just ID strings)
CURRENT_PEERS=$(echo "$GROUP_CONFIG" | jq '.peers // []')
UPDATED_PEERS=$(echo "$CURRENT_PEERS" | jq --arg peer_id "$PEER_ID" '. + [$peer_id] | unique')
UPDATED_RESOURCES=$(echo "$GROUP_CONFIG" | jq '.resources // []')

# send PUT request to update group
echo "[+] updating group membership..."
PAYLOAD=$(jq -n \
    --arg name "$GROUP_NAME" \
    --argjson peers "$UPDATED_PEERS" \
    --argjson resources "$UPDATED_RESOURCES" \
    '{name: $name, peers: $peers, resources: $resources}')

UPDATE_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X PUT "https://api.netbird.io/api/groups/$SELECTED_GROUP_ID" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -H "Authorization: Token $NETBIRD_TOKEN" \
    --data-raw "$PAYLOAD")

HTTP_STATUS=$(echo "$UPDATE_RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
RESPONSE_BODY=$(echo "$UPDATE_RESPONSE" | sed '/HTTP_STATUS:/d')

if [[ "$HTTP_STATUS" -eq 200 ]]; then
    echo "[+] successfully joined group: $GROUP_NAME"
else
    echo "error: failed to join group (HTTP $HTTP_STATUS)"
    echo "response: $RESPONSE_BODY"
    exit 1
fi
