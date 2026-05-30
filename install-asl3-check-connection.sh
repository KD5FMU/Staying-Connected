#!/usr/bin/env bash

set -euo pipefail

INSTALL_DIR="/etc/asterisk/local"
SCRIPT_FILE="${INSTALL_DIR}/check-connection.sh"
CONFIG_FILE="${INSTALL_DIR}/check-connection.conf"
CRON_MARKER_BEGIN="# BEGIN ASL3 CHECK CONNECTION"
CRON_MARKER_END="# END ASL3 CHECK CONNECTION"

show_header() {
    echo
    echo "===================================================="
    echo " AllStarLink 3 Check Connection Installer"
    echo " Debian 12 / Debian 13"
    echo "===================================================="
    echo
}

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo "ERROR: This script must be run as root."
        echo
        echo "Run it like this:"
        echo "  sudo ./install-asl3-check-connection.sh"
        echo
        exit 1
    fi
}

detect_asterisk_bin() {
    if [[ -x "/usr/sbin/asterisk" ]]; then
        echo "/usr/sbin/asterisk"
    elif [[ -x "/usr/local/sbin/asterisk" ]]; then
        echo "/usr/local/sbin/asterisk"
    elif command -v asterisk >/dev/null 2>&1; then
        command -v asterisk
    else
        echo ""
    fi
}

remove_root_cron_entry() {
    local TEMP_CRON

    TEMP_CRON="$(mktemp)"

    crontab -l 2>/dev/null | sed "/${CRON_MARKER_BEGIN}/,/${CRON_MARKER_END}/d" > "${TEMP_CRON}" || true

    if [[ -s "${TEMP_CRON}" ]]; then
        crontab "${TEMP_CRON}"
    else
        crontab -r 2>/dev/null || true
    fi

    rm -f "${TEMP_CRON}"
}

uninstall_check_connection() {
    show_header
    require_root

    echo "Uninstalling ASL3 Check Connection..."
    echo

    echo "Removing root crontab entry..."
    remove_root_cron_entry

    if [[ -f "${SCRIPT_FILE}" ]]; then
        echo
        echo "Removing script:"
        echo "  ${SCRIPT_FILE}"
        rm -f "${SCRIPT_FILE}"
    else
        echo
        echo "Script not found, skipping:"
        echo "  ${SCRIPT_FILE}"
    fi

    if [[ -f "${CONFIG_FILE}" ]]; then
        echo
        read -rp "Remove config file too? [y/N]: " REMOVE_CONFIG
        REMOVE_CONFIG="${REMOVE_CONFIG:-N}"

        if [[ "${REMOVE_CONFIG}" =~ ^[Yy]$ ]]; then
            echo "Removing config:"
            echo "  ${CONFIG_FILE}"
            rm -f "${CONFIG_FILE}"
        else
            echo "Keeping config file:"
            echo "  ${CONFIG_FILE}"
        fi
    else
        echo
        echo "Config file not found, skipping:"
        echo "  ${CONFIG_FILE}"
    fi

    echo
    echo "Uninstall complete."
    echo
    exit 0
}

install_check_connection() {
    show_header
    require_root

    ASTERISK_BIN="$(detect_asterisk_bin)"

    if [[ -z "${ASTERISK_BIN}" ]]; then
        echo "ERROR: The 'asterisk' command was not found."
        echo "This does not appear to be an AllStarLink/Asterisk system."
        exit 1
    fi

    echo "Detected Asterisk binary:"
    echo "  ${ASTERISK_BIN}"
    echo

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

# Your local AllStarLink node number
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
# Set to "no" if you want quieter cron logs.
VERBOSE="yes"

# Full path to the Asterisk binary.
ASTERISK_BIN="${ASTERISK_BIN}"
EOF

    cat > "${SCRIPT_FILE}" <<'EOF'
#!/usr/bin/env bash

set -u

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

CONFIG_FILE="/etc/asterisk/local/check-connection.conf"

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "ERROR: Config file not found: ${CONFIG_FILE}"
    exit 1
fi

# shellcheck source=/dev/null
source "${CONFIG_FILE}"

if [[ -z "${LOCAL_NODE:-}" ]]; then
    echo "ERROR: LOCAL_NODE is missing from ${CONFIG_FILE}"
    exit 1
fi

if [[ -z "${TARGET_NODES:-}" ]]; then
    echo "ERROR: TARGET_NODES is missing from ${CONFIG_FILE}"
    exit 1
fi

if [[ -z "${CONNECT_PREFIX:-}" ]]; then
    CONNECT_PREFIX="*3"
fi

if [[ -z "${RECONNECT_DELAY_SECONDS:-}" ]]; then
    RECONNECT_DELAY_SECONDS="2"
fi

if [[ -z "${ASTERISK_BIN:-}" ]]; then
    if [[ -x "/usr/sbin/asterisk" ]]; then
        ASTERISK_BIN="/usr/sbin/asterisk"
    elif [[ -x "/usr/local/sbin/asterisk" ]]; then
        ASTERISK_BIN="/usr/local/sbin/asterisk"
    else
        ASTERISK_BIN="asterisk"
    fi
fi

LOCK_FILE="/run/asl3-check-connection-${LOCAL_NODE}.lock"

exec 9>"${LOCK_FILE}"

if ! flock -n 9; then
    logger -t "asl3-check-connection" "Another check-connection instance is already running. Exiting."
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
    timeout 10 "${ASTERISK_BIN}" -rx "${CMD}" 2>/dev/null
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

    sleep "${RECONNECT_DELAY_SECONDS}"
}

main() {
    if [[ "${ASTERISK_BIN}" != "asterisk" && ! -x "${ASTERISK_BIN}" ]]; then
        log_msg "ERROR: Asterisk binary not found or not executable at ${ASTERISK_BIN}."
        exit 1
    fi

    if ! "${ASTERISK_BIN}" -rx "core show version" >/dev/null 2>&1; then
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

    echo
    echo "Installing cron entry into root crontab..."

    TEMP_CRON="$(mktemp)"

    crontab -l 2>/dev/null | sed "/${CRON_MARKER_BEGIN}/,/${CRON_MARKER_END}/d" > "${TEMP_CRON}" || true

    cat >> "${TEMP_CRON}" <<EOF

${CRON_MARKER_BEGIN}
*/${CRON_INTERVAL} * * * * ${SCRIPT_FILE} >/dev/null 2>&1
${CRON_MARKER_END}
EOF

    crontab "${TEMP_CRON}"
    rm -f "${TEMP_CRON}"

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
    echo "Cron location:"
    echo "  root crontab"
    echo
    echo "View root crontab:"
    echo "  sudo crontab -l"
    echo
    echo "Cron interval:"
    echo "  Every ${CRON_INTERVAL} minute(s)"
    echo
    echo "Manual test command:"
    echo "  sudo ${SCRIPT_FILE}"
    echo
    echo "Cron-like test command:"
    echo "  sudo env -i PATH=\"/usr/bin:/bin\" ${SCRIPT_FILE}"
    echo
    echo "View log entries:"
    echo "  journalctl -t asl3-check-connection"
    echo
}

case "${1:-install}" in
    install)
        install_check_connection
        ;;
    uninstall|remove)
        uninstall_check_connection
        ;;
    *)
        echo "Usage:"
        echo "  sudo ./install-asl3-check-connection.sh"
        echo "  sudo ./install-asl3-check-connection.sh install"
        echo "  sudo ./install-asl3-check-connection.sh uninstall"
        exit 1
        ;;
esac
