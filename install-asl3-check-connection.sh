#!/usr/bin/env bash

set -euo pipefail

INSTALL_DIR="/etc/asterisk/local"
SCRIPT_FILE="${INSTALL_DIR}/check-connection.sh"
CONFIG_FILE="${INSTALL_DIR}/check-connection.conf"
CRON_FILE="/etc/cron.d/asl3-check-connection"

echo
echo "===================================================="
echo " AllStarLink 3 Check Connection Installer"
echo " Debian 12 / Debian 13"
echo "===================================================="
echo

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: This installer must be run as root."
    echo "Run it like this:"
    echo
    echo "  sudo bash install-asl3-check-connection.sh"
    echo
    exit 1
fi

if ! command -v asterisk >/dev/null 2>&1; then
    echo "ERROR: The 'asterisk' command was not found."
    echo "This does not appear to be an AllStarLink/Asterisk system."
    exit 1
fi

mkdir -p "${INSTALL_DIR}"

read -rp "Enter your local AllStarLink node number: " LOCAL_NODE

if ! [[ "${LOCAL_NODE}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Local node must be numbers only."
    exit 1
fi

echo
echo "Enter the node or nodes you want to stay connected to."
echo "Examples:"
echo "  43136"
echo "  43136 27225"
echo "  43136,27225"
echo
read -rp "Target node or nodes: " TARGET_NODES_RAW

TARGET_NODES="$(echo "${TARGET_NODES_RAW}" | tr ',' ' ' | xargs)"

if [[ -z "${TARGET_NODES}" ]]; then
    echo "ERROR: You must enter at least one target node."
    exit 1
fi

for NODE in ${TARGET_NODES}; do
    if ! [[ "${NODE}" =~ ^[0-9]+$ ]]; then
        echo "ERROR: Target node '${NODE}' is not valid. Use numbers only."
        exit 1
    fi

    if [[ "${NODE}" == "${LOCAL_NODE}" ]]; then
        echo "ERROR: Target node cannot be the same as the local node."
        exit 1
    fi
done

echo
echo "Connection mode:"
echo "  3 = Transceive connect, same as *3NODE"
echo "  2 = Monitor connect, same as *2NODE"
echo
read -rp "Choose connection mode [3]: " CONNECT_MODE
CONNECT_MODE="${CONNECT_MODE:-3}"

if [[ "${CONNECT_MODE}" != "3" && "${CONNECT_MODE}" != "2" ]]; then
    echo "ERROR: Connection mode must be 3 or 2."
    exit 1
fi

CONNECT_PREFIX="*${CONNECT_MODE}"

echo
read -rp "How often should cron run this check, in minutes? [5]: " CRON_INTERVAL
CRON_INTERVAL="${CRON_INTERVAL:-5}"

if ! [[ "${CRON_INTERVAL}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Cron interval must be a number."
    exit 1
fi

if (( CRON_INTERVAL < 1 || CRON_INTERVAL > 59 )); then
    echo "ERROR: Please choose a cron interval from 1 to 59 minutes."
    exit 1
fi

cat > "${CONFIG_FILE}" <<EOF
# AllStarLink 3 Check Connection Configuration
# Created by install-asl3-check-connection.sh

LOCAL_NODE="${LOCAL_NODE}"

# Space-separated list of target nodes that should stay connected.
TARGET_NODES="${TARGET_NODES}"

# Connection prefix:
# *3 = transceive connect
# *2 = monitor connect
CONNECT_PREFIX="${CONNECT_PREFIX}"

# Wait this many seconds after issuing each reconnect command.
RECONNECT_DELAY_SECONDS="2"

# Set to "yes" for extra terminal output when run manually.
VERBOSE="yes"
EOF

cat > "${SCRIPT_FILE}" <<'EOF'
#!/usr/bin/env bash

set -u

CONFIG_FILE="/etc/asterisk/local/check-connection.conf"

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "ERROR: Config file not found: ${CONFIG_FILE}"
    exit 1
fi

# shellcheck source=/dev/null
source "${CONFIG_FILE}"

LOCK_FILE="/run/asl3-check-connection-${LOCAL_NODE}.lock"

exec 9>"${LOCK_FILE}"

if ! flock -n 9; then
    echo "Another check-connection instance is already running. Exiting."
    exit 0
fi

log_msg() {
    local MESSAGE="$1"

    logger -t "asl3-check-connection" "${MESSAGE}"

    if [[ "${VERBOSE:-no}" == "yes" ]]; then
        echo "${MESSAGE}"
    fi
}

run_asterisk_cmd() {
    local CMD="$1"
    timeout 10 asterisk -rx "${CMD}" 2>/dev/null
}

is_node_connected() {
    local TARGET_NODE="$1"
    local NODES_OUTPUT

    NODES_OUTPUT="$(run_asterisk_cmd "rpt nodes ${LOCAL_NODE}")"

    if [[ -z "${NODES_OUTPUT}" ]]; then
        log_msg "WARNING: No output received from: rpt nodes ${LOCAL_NODE}"
        return 1
    fi

    echo "${NODES_OUTPUT}" | grep -Eq "(^|[^0-9])${TARGET_NODE}([^0-9]|$)"
}

connect_node() {
    local TARGET_NODE="$1"
    local CONNECT_COMMAND="${CONNECT_PREFIX}${TARGET_NODE}"

    log_msg "Node ${LOCAL_NODE} is not connected to ${TARGET_NODE}. Reconnecting with ${CONNECT_COMMAND}."

    run_asterisk_cmd "rpt fun ${LOCAL_NODE} ${CONNECT_COMMAND}" >/dev/null

    sleep "${RECONNECT_DELAY_SECONDS:-2}"
}

main() {
    if ! command -v asterisk >/dev/null 2>&1; then
        log_msg "ERROR: asterisk command not found."
        exit 1
    fi

    if ! asterisk -rx "core show version" >/dev/null 2>&1; then
        log_msg "ERROR: Unable to communicate with Asterisk. Is Asterisk running?"
        exit 1
    fi

    for TARGET_NODE in ${TARGET_NODES}; do
        if is_node_connected "${TARGET_NODE}"; then
            log_msg "Node ${LOCAL_NODE} is already connected to ${TARGET_NODE}. No action needed."
        else
            connect_node "${TARGET_NODE}"
        fi
    done
}

main "$@"
EOF

chmod 755 "${SCRIPT_FILE}"
chmod 644 "${CONFIG_FILE}"

cat > "${CRON_FILE}" <<EOF
# AllStarLink 3 Check Connection cron job
# Runs every ${CRON_INTERVAL} minute(s)
*/${CRON_INTERVAL} * * * * root ${SCRIPT_FILE} >/dev/null 2>&1
EOF

chmod 644 "${CRON_FILE}"

echo
echo "===================================================="
echo " Installation Complete"
echo "===================================================="
echo
echo "Main script:"
echo "  ${SCRIPT_FILE}"
echo
echo "Config file:"
echo "  ${CONFIG_FILE}"
echo
echo "Cron file:"
echo "  ${CRON_FILE}"
echo
echo "Cron interval:"
echo "  Every ${CRON_INTERVAL} minute(s)"
echo
echo "Manual test command:"
echo "  sudo ${SCRIPT_FILE}"
echo
echo "View log entries:"
echo "  journalctl -t asl3-check-connection"
echo
echo "Or:"
echo "  grep asl3-check-connection /var/log/syslog"
echo
