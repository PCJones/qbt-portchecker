#!/usr/bin/with-contenv bash

# Logfunktion

log() {
    local message="$1"
    local timestamp=$(date +"%Y.%m.%dT%H:%M:%S")
    echo "${timestamp} (qbt-portchecker) ${message}"
}

GLUETUN_API_KEY=${PORTCHECKER_GLUETUN_API_KEY} # der api-key von der gluetun config.toml (auth-ordner)
SLEEP_COMPLETE=${PORTCHECKER_SLEEP:-60} # zeit, die gewartet werden soll, bis das skript den port wieder überprüft
KILL_ON_NOT_CONNECTABLE=${PORTCHECKER_KILL_ON_NOT_CONNECTABLE:-true} # qbittorrent neustarten, wenn der portcheck ergibt, dass der port nicht connectable ist. sollte qbittorrent ständig neustarten, kann diese option deaktiviert werden



VAR_UP=true

while :; do

    HTTP_STATUS=$(wget -T 5 -t 1 --server-response --spider "http://localhost:${WEBUI_PORT}" 2>&1 | awk '/HTTP\// {print $2}')

    if [[ "200" == "$HTTP_STATUS" ]]; then
        log "web ui online"
        break
    fi

    sleep 1

done

while :; do

    SLEEP=$SLEEP_COMPLETE

    PORT=$(wget -T 5 -t 1 -qO- "http://localhost:${WEBUI_PORT}/api/v2/app/preferences" | jq ".listen_port")
    NEW_PORT=$(wget --header="X-API-Key: ${GLUETUN_API_KEY}" -T 5 -t 1 -qO- "http://localhost:8000/v1/openvpn/portforwarded" | jq ".port")

    if [[ "" == "$NEW_PORT" ]]; then
        log "No port in file or file not found"
    elif [[ "" == "$PORT" ]]; then
        log "Api did not respond"
    elif [[ "$PORT" == "$NEW_PORT" ]]; then
        [[ true == "$VAR_UP" ]] && log "Port did not change (Port: $PORT)"
    else
        log "Detected port changed: old: $PORT, new: $NEW_PORT"
        curl --silent --request POST --url "http://localhost:${WEBUI_PORT}/api/v2/app/setPreferences" --data "json={\"listen_port\": $NEW_PORT}"

        if [[ $? -eq 0 ]]; then
            log "Port updated to $NEW_PORT successfully"
            PORT=$NEW_PORT
        else
            log "Error updating port"
        fi
    fi

    CONNECTABLE=$(wget -T 5 -t 1 -qO- "https://portcheck.transmissionbt.com/${NEW_PORT}" 2> /dev/null)

    if [[ -z "$CONNECTABLE" ]]; then
        log "portcheck returned no response, skipping"
    elif [[ "$CONNECTABLE" -eq 1 ]]; then
        [[ true == "$VAR_UP" ]] && log "Port $NEW_PORT is connectable, done"
        VAR_UP=false
    elif [[ "$CONNECTABLE" -eq 0 ]]; then
        log "Port $NEW_PORT is not connectable, retrying in $SLEEP seconds"
        if [[ "$KILL_ON_NOT_CONNECTABLE" == true ]]; then
            log "killing qBittorrent..."
            pkill qbittorrent-nox
        fi
    else
        log "Unexpected response from port check: $CONNECTABLE"
    fi


    [[ true == "$VAR_UP" ]] && log "Sleeping for $SLEEP, retrying afterwards"
    sleep $SLEEP

done