#!/bin/bash
# PMX - Proxmox Monitoring X

# --- Couleurs & Icones (insérées par l'installateur) ---
CLR_G="\e[32m"; CLR_R="\e[31m"; CLR_B="\e[34m"; CLR_Y="\e[33m"; CLR_RESET="\e[0m"; CLR_GR="\e[90m"

# --- Fonctions de recherche ---
find_target() {
    local query=$1
    # On cherche par VMID ou par Nom dans les données Proxmox
    pvesh get /cluster/resources --output-format json 2>/dev/null | jq -r ".[] | select(.vmid == $query or .name == \"$query\") | \"\(.vmid)|\(.type)|\(.status)\"" | head -n 1
}

do_action() {
    local action=$1; local vid=$2; local vtype=$3
    if [[ "$vtype" == "qemu" ]]; then
        [[ "$action" == "start" ]] && qm start "$vid"
        [[ "$action" == "stop" ]] && qm stop "$vid"
        [[ "$action" == "term" ]] && qm terminal "$vid"
    else
        [[ "$action" == "start" ]] && pct start "$vid"
        [[ "$action" == "stop" ]] && pct stop "$vid"
        [[ "$action" == "term" ]] && pct enter "$vid"
    fi
}

show_help() {
    echo -e "${CLR_B}Usage:${RESET} pmx [action] [ID/Nom]"
    echo -e "  pmx perf          : Dashboard live"
    echo -e "  pmx on <id/nom>   : Démarrer une machine"
    echo -e "  pmx off <id/nom>  : Éteindre une machine"
    echo -e "  pmx <id/nom>      : Démarre ou entre dans la console"
    echo -e "  pmx -help         : Afficher cette aide"
    exit 0
}

# --- Parsing des arguments ---
ACTION_CMD=""
TARGET_QUERY=""
SHOW_PERF=false

case $1 in
    help|h|-h|--help|-help) show_help ;;
    on)  ACTION_CMD="start"; TARGET_QUERY="$2" ;;
    off) ACTION_CMD="stop";  TARGET_QUERY="$2" ;;
    perf) SHOW_PERF=true;    TARGET_QUERY="$2" ;;
    [0-9]*|*) 
        if [[ -n "$1" ]]; then
            # Si c'est juste un ID/Nom sans commande devant
            TARGET_QUERY="$1"
        fi
        ;;
esac

# --- Logique d'exécution directe ---
if [[ -n "$TARGET_QUERY" && "$SHOW_PERF" == "false" ]]; then
    RESULT=$(find_target "$TARGET_QUERY")
    if [[ -n "$RESULT" ]]; then
        IFS='|' read -r vid vtype vstat <<< "$RESULT"
        if [[ -n "$ACTION_CMD" ]]; then
            do_action "$ACTION_CMD" "$vid" "$vtype"
        else
            # Si pas de commande (ex: pmx 105), on décide selon le statut
            if [[ "$vstat" == "stopped" ]]; then
                echo -e "${CLR_G}Démarrage de $TARGET_QUERY ($vid)...${CLR_RESET}"
                do_action "start" "$vid" "$vtype"
            else
                do_action "term" "$vid" "$vtype"
            fi
        fi
        exit 0
    elif [[ -n "$ACTION_CMD" || "$TARGET_QUERY" =~ ^[0-9]+$ ]]; then
        echo -e "${CLR_R}Erreur : Machine '$TARGET_QUERY' introuvable.${CLR_RESET}"
        exit 1
    fi
fi

# --- (Reste du script : Boucle LIVE MONITORING si pas d'action directe) ---
# ... (Insère ici la boucle while true de monitoring que nous avons faite avant)
