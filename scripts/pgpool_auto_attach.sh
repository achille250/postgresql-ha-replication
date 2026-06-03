#!/bin/bash
#========================================================
# Pgpool-II Auto Node Reattach Script (Dynamic Version)
#========================================================
# - Detects all Pgpool-II nodes dynamically
# - Logs only when a DOWN node is reattached
# - Creates log directory/file when missing
#========================================================

# Pgpool PCP Config
PCP_HOST="${PRIMARY_HOST}"
PCP_PORT=9898
PCP_USER="pgpool_user"
PCP_PASSFILE="/root/.pcppass"

# Log file
LOG_DIR="/home/logs"
LOG_FILE="${LOG_DIR}/pgpool_attached.log"

# Export passfile
export PCPPASSFILE="${PCP_PASSFILE}"

# Create log directory if missing
mkdir -p "${LOG_DIR}"

echo "[$(date)] Checking Pgpool-II nodes..."

# Get total backend nodes dynamically
TOTAL_NODES=$(pcp_node_count -h "$PCP_HOST" -p "$PCP_PORT" -U "$PCP_USER" -w 2>/dev/null)

if [[ $? -ne 0 || -z "$TOTAL_NODES" ]]; then
    echo "❌ Cannot retrieve node count. Check PCP settings."
    exit 1
fi

echo "  Found ${TOTAL_NODES} nodes."

ANY_REATTACHED=0  # Track if any node was fixed

for NODE_ID in $(seq 0 $((TOTAL_NODES - 1))); do

    NODE_INFO=$(pcp_node_info -h "$PCP_HOST" -p "$PCP_PORT" -U "$PCP_USER" -n "$NODE_ID" -w 2>/dev/null)

    if [[ $? -ne 0 ]]; then
        echo "  ❌ Failed to get node info for node $NODE_ID."
        continue
    fi

    NODE_STATUS=$(echo "$NODE_INFO" | awk '{print $3}')

    # Pgpool status mapping:
    # 0 = unused/init, 1 = up, 2 = up/pooling, 3 = down
    if [[ "$NODE_STATUS" == "3" ]]; then
        echo "  ⚠️  Node $NODE_ID is DOWN. Attempting reattach..."

        if pcp_attach_node -h "$PCP_HOST" -p "$PCP_PORT" -U "$PCP_USER" -n "$NODE_ID" -w >/dev/null 2>&1; then
            echo "  ✅ Node $NODE_ID successfully reattached."

            echo "[$(date)] Node $NODE_ID was DOWN and REATTACHED." \
                >> "$LOG_FILE"

            ANY_REATTACHED=1
        else
            echo "  ❌ Failed to reattach node $NODE_ID."

            echo "[$(date)] Node $NODE_ID FAILED to reattach." \
                >> "$LOG_FILE"
            ANY_REATTACHED=1
        fi
    else
        echo "  ✅ Node $NODE_ID is UP (status=$NODE_STATUS)."
    fi

done

if [[ $ANY_REATTACHED -eq 0 ]]; then
    echo "🟢 All nodes are UP — no logs written."
else
    echo "📄 Log updated: ${LOG_FILE}"
fi

echo "[$(date)] Pgpool-II node check completed."
