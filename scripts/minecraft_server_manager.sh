#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC2034
SCRIPT_NAME="minecraft_server_manager"

initial_pwd=$(pwd)

load_env_file() {
    local file=$1
    if [[ -f $file ]]; then
        # Export variables defined inside so that they affect the current shell
        set -a
        # shellcheck disable=SC1090
        source "$file"
        set +a
    fi
}

# Load optional configuration files before resolving defaults.
load_env_file "$initial_pwd/.env"
load_env_file "$initial_pwd/.minecraft-server.env"

SERVER_DIR=${SERVER_DIR:-"$initial_pwd"}
load_env_file "$SERVER_DIR/.env"
load_env_file "$SERVER_DIR/.minecraft-server.env"

SERVER_JAR=${SERVER_JAR:-"server.jar"}
JAVA_CMD=${JAVA_CMD:-"java"}
JAVA_ARGS=${JAVA_ARGS:-"-Xms2G -Xmx2G"}
BACKUP_DIR=${BACKUP_DIR:-"$SERVER_DIR/backups"}
WORLD_DIR=${WORLD_DIR:-"$SERVER_DIR/world"}
BACKUP_INTERVAL_MINUTES=${BACKUP_INTERVAL_MINUTES:-30}
MAX_BACKUPS=${MAX_BACKUPS:-48}
RESTART_DELAY=${RESTART_DELAY:-10}
STOP_FILE=${STOP_FILE:-"$SERVER_DIR/stop.txt"}
LOG_DIR=${LOG_DIR:-"$SERVER_DIR/logs"}
TIMESTAMP_FORMAT=${TIMESTAMP_FORMAT:-"%Y-%m-%d %H:%M:%S"}

mkdir -p "$BACKUP_DIR" "$LOG_DIR"
LOG_FILE="$LOG_DIR/server-$(date +%Y%m%d).log"

log() {
    local level=$1
    shift
    printf '%s [%s] %s\n' "$(date +"$TIMESTAMP_FORMAT")" "$level" "$*" | tee -a "$LOG_FILE"
}

stop_requested=false
server_pid=""
backup_loop_pid=""

cleanup() {
    local exit_code=$?
    stop_requested=true
    if [[ -n $backup_loop_pid && -e /proc/$backup_loop_pid ]]; then
        kill "$backup_loop_pid" 2>/dev/null || true
        wait "$backup_loop_pid" 2>/dev/null || true
    fi
    if [[ -n $server_pid && -e /proc/$server_pid ]]; then
        log WARN "Stopping Minecraft server (PID $server_pid)"
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
    log INFO "Shutting down manager (exit code $exit_code)."
}

trap cleanup EXIT
trap 'log WARN "Received SIGINT"; stop_requested=true' INT
trap 'log WARN "Received SIGTERM"; stop_requested=true' TERM

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        log ERROR "Required command '$1' not found in PATH"
        exit 1
    fi
}

require_command "$JAVA_CMD"

create_backup() {
    if [[ ! -d $WORLD_DIR ]]; then
        log WARN "World directory '$WORLD_DIR' does not exist, skipping backup"
        return
    fi

    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_path="$BACKUP_DIR/world-$timestamp"

    log INFO "Creating world backup at $backup_path"
    mkdir -p "$backup_path"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --delete "$WORLD_DIR/" "$backup_path/"
    else
        rm -rf "$backup_path"
        cp -a "$WORLD_DIR" "$backup_path"
    fi

    if [[ $MAX_BACKUPS -gt 0 ]]; then
        mapfile -t backups < <(find "$BACKUP_DIR" -maxdepth 1 -mindepth 1 -type d -printf '%P\n' | sort)
        local excess=$(( ${#backups[@]} - MAX_BACKUPS ))
        if (( excess > 0 )); then
            for backup in "${backups[@]:0:excess}"; do
                log INFO "Pruning old backup $backup"
                rm -rf "$BACKUP_DIR/$backup"
            done
        fi
    fi
}

backup_loop() {
    local interval_seconds=$(( BACKUP_INTERVAL_MINUTES * 60 ))
    while ! $stop_requested; do
        sleep "$interval_seconds" || true
        $stop_requested && break
        create_backup
    done
}

start_backup_loop() {
    backup_loop &
    backup_loop_pid=$!
    log INFO "Started backup loop (PID $backup_loop_pid) running every $BACKUP_INTERVAL_MINUTES minutes"
}

stop_backup_loop() {
    if [[ -n $backup_loop_pid && -e /proc/$backup_loop_pid ]]; then
        log INFO "Stopping backup loop (PID $backup_loop_pid)"
        kill "$backup_loop_pid" 2>/dev/null || true
        wait "$backup_loop_pid" 2>/dev/null || true
    fi
    backup_loop_pid=""
}

should_restart() {
    if [[ -f $STOP_FILE ]]; then
        log INFO "Stop file $STOP_FILE found. Removing and shutting down."
        rm -f "$STOP_FILE"
        return 1
    fi
    $stop_requested && return 1
    return 0
}

run_server_once() {
    log INFO "Launching Minecraft server"
    set +e
    (cd "$SERVER_DIR" && exec $JAVA_CMD $JAVA_ARGS -jar "$SERVER_JAR" nogui) &
    server_pid=$!
    wait "$server_pid"
    local exit_code=$?
    set -e
    log WARN "Minecraft server exited with code $exit_code"
    return $exit_code
}

main_loop() {
    start_backup_loop
    create_backup
    while should_restart; do
        run_server_once || true
        $stop_requested && break
        should_restart || break
        log INFO "Restarting server after $RESTART_DELAY seconds"
        sleep "$RESTART_DELAY"
        create_backup
    done
    stop_backup_loop
    log INFO "Server loop finished"
}

main_loop
