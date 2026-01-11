#!/bin/bash

# --- Couleurs ---
CLR_B="\e[34m"; CLR_G="\e[32m"; CLR_Y="\e[33m"; CLR_R="\e[31m"; CLR_RESET="\e[0m"

echo -e "${CLR_B}########################################${CLR_RESET}"
echo -e "${CLR_B}#      PMX - Proxmox Monitoring X       #${CLR_RESET}"
echo -e "${CLR_B}########################################${CLR_RESET}"

# 1. Check Root & Dépendances
if [[ $EUID -ne 0 ]]; then
   echo -e "${CLR_R}Erreur : Lancez ce script en root (sudo).${CLR_RESET}"
   exit 1
fi

echo -e "\n${CLR_Y}[1/3] Installation des dépendances (jq, bc)...${CLR_RESET}"
apt update && apt install -y jq bc > /dev/null 2>&1

# 2. Choix du style (Fixé pour curl | bash)
echo -e "\n${CLR_Y}[2/3] Configuration graphique...${CLR_RESET}"
echo -ne "${CLR_B}Utiliser NerdFont (icones spéciales) ? [y/N] : ${CLR_RESET}"
read -r font_choice < /dev/tty

TEMP_PMX=$(mktemp)

# --- CONSTRUCTION DU SCRIPT PMX ---
cat << 'EOF' > "$TEMP_PMX"
#!/bin/bash
# PMX - Proxmox Monitoring X
CLR_G="\e[32m"; CLR_R="\e[31m"; CLR_B="\e[34m"; CLR_Y="\e[33m"; CLR_RESET="\e[0m"; CLR_GR="\e[90m"

# --- Fonctions Utilitaires ---
show_help() {
    echo -e "${CLR_B}Usage:${CLR_RESET} pmx [action] [ID/Nom]"
    echo -e "  pmx perf          : Dashboard live de tout le cluster"
    echo -e "  pmx perf ID       : Focus live sur une machine (ex: pmx perf 106)"
    echo -e "  pmx on <id/nom>   : Démarrer une machine"
    echo -e "  pmx off <id/nom>  : Éteindre une machine"
    echo -e "  pmx <id/nom>      : Démarrage (si OFF) ou Console (si ON)"
    echo -e "  pmx -help         : Afficher cette aide"
    exit 0
}

human_size() {
    local b=$(echo "${1:-0}" | cut -d. -f1)
    if (( b < 1073741824 )); then printf "%.0fM" $(echo "$b/1048576" | bc -l)
    else printf "%.1fG" $(echo "$b/1073741824" | bc -l)
    fi
}

find_target() {
    local query=$1
    pvesh get /cluster/resources --output-format json 2>/dev/null | jq -r ".[] | select(.vmid == \"$query\" or .name == \"$query\") | \"\(.vmid)|\(.type)|\(.status)\"" | head -n 1
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
EOF

# --- STYLE GRAPHIQUE (NerdFont vs ASCII) ---
if [[ "$font_choice" =~ ^[yY]$ ]]; then
    cat << 'EOF' >> "$TEMP_PMX"
ICON_VM=" "; ICON_LXC=" "; ICON_ON="󰄬 "; ICON_OFF="󰅖 "
draw_bar() {
    local perc=$1; local width=10
    local p_int=$(echo "$perc" | cut -d. -f1); [[ -z "$p_int" || "$p_int" -lt 0 ]] && p_int=0
    (( p_int > 100 )) && p_int=100
    local filled=$(( (p_int * width) / 100 ))
    local color=$CLR_G; (( p_int > 70 )) && color=$CLR_Y; (( p_int > 90 )) && color=$CLR_R
    local bar=""; for ((i=0; i<filled; i++)); do bar+="${color}■"; done
    for ((i=$filled; i<$width; i++)); do bar+="${CLR_GR}□"; done
    echo -ne "${bar}${CLR_RESET}"
}
EOF
else
    cat << 'EOF' >> "$TEMP_PMX"
ICON_VM="VM"; ICON_LXC="CT"; ICON_ON="RUN"; ICON_OFF="STP"
draw_bar() {
    local perc=$1; local width=10
    local p_int=$(echo "$perc" | cut -d. -f1); [[ -z "$p_int" || "$p_int" -lt 0 ]] && p_int=0
    (( p_int > 100 )) && p_int=100
    local filled=$(( (p_int * width) / 100 ))
    local color=$CLR_G; (( p_int > 70 )) && color=$CLR_Y; (( p_int > 90 )) && color=$CLR_R
    local bar="["; for ((i=0; i<filled; i++)); do bar+="#"; done
    for ((i=$filled; i<$width; i++)); do bar+="-"; done; bar+="]"
    echo -ne "${color}${bar}${CLR_RESET}"
}
EOF
fi

# --- LOGIQUE DE PARSING & BOUCLE ---
cat << 'EOF' >> "$TEMP_PMX"
FILTER_TYPE="all"; FILTER_STATUS="all"; SHOW_PERF=false; TARGET_QUERY=""
ACTION_CMD=""

# Parsing Arguments
case $1 in
    help|h|-h|--help|-help) show_help ;;
    on)  ACTION_CMD="start"; TARGET_QUERY="$2" ;;
    off) ACTION_CMD="stop";  TARGET_QUERY="$2" ;;
    perf) SHOW_PERF=true;    TARGET_QUERY="$2" ;;
    vm) FILTER_TYPE="qemu";; lxc) FILTER_TYPE="lxc";;
    [0-9]*|*) [[ -z "$ACTION_CMD" ]] && TARGET_QUERY="$1" ;;
esac

# Action Directe (si ID ou Nom fourni sans mode perf)
if [[ -n "$TARGET_QUERY" && "$SHOW_PERF" == "false" ]]; then
    RESULT=$(find_target "$TARGET_QUERY")
    if [[ -n "$RESULT" ]]; then
        IFS='|' read -r vid vtype vstat <<< "$RESULT"
        if [[ -n "$ACTION_CMD" ]]; then
            do_action "$ACTION_CMD" "$vid" "$vtype"
        else
            [[ "$vstat" == "stopped" ]] && do_action "start" "$vid" "$vtype" || do_action "term" "$vid" "$vtype"
        fi
        exit 0
    fi
fi

# Boucle Monitoring
PREVIOUS_LINES=0
trap 'tput cnorm; exit' SIGINT SIGTERM
while true; do
    ALL_DATA=$(pvesh get /cluster/resources --output-format json 2>/dev/null)
    if [ $PREVIOUS_LINES -gt 0 ]; then echo -ne "\e[${PREVIOUS_LINES}A"; fi
    
    DISPLAY_BUFFER=$(
        if [[ -n "$TARGET_QUERY" && "$SHOW_PERF" == "true" ]]; then
            # Focus ID
            raw=$(echo "$ALL_DATA" | jq -r ".[] | select(.vmid == \"$TARGET_QUERY\" or .name == \"$TARGET_QUERY\")")
            vid=$(echo "$raw" | jq -r '.vmid')
            cpu=$(echo "$raw" | jq -r '.cpu // 0' | awk '{printf "%.2f", $1 * 100}')
            mem_u=$(echo "$raw" | jq -r '.mem // 0'); mem_m=$(echo "$raw" | jq -r '.maxmem // 1')
            disk_u=$(echo "$raw" | jq -r '.disk // 0'); disk_m=$(echo "$raw" | jq -r '.maxdisk // 1')
            echo -e "\n${CLR_B}╭─ MONITORING LIVE : $TARGET_QUERY ($vid) ──────────────────╮${CLR_RESET}"
            printf " │ CPU  [%b] %-6s%%  │ RAM  [%b] %-3s%%   │\n" "$(draw_bar $cpu)" "$cpu" "$(draw_bar $((mem_u*100/mem_m)))" "$((mem_u*100/mem_m))"
            printf " │ DSK  [%b] %-3s%%   │ Net  %-18s │\n" "$(draw_bar $((disk_u*100/disk_m)))" "$((disk_u*100/disk_m))" "$(human_size $(echo "$raw" | jq -r '.netin // 0'))"
            echo -e "${CLR_B}╰──────────────────────────────────────────────────────────╯${CLR_RESET}"
            echo -ne "${CLR_Y}Se connecter ($vid) [q:quitter] : ${CLR_RESET}"
        else
            # Liste complète
            echo ""
            if [ "$SHOW_PERF" = true ]; then
                printf "${CLR_B}%-5s %-4s %-7s %-4s %-18s %-18s %-18s %-18s${CLR_RESET}\n" "ID" "TYP" "VMID" "ST" "NOM" "CPU %" "RAM" "DISK"
                echo -e "${CLR_GR}----------------------------------------------------------------------------------------------------${CLR_RESET}"
            else
                printf "${CLR_B}%-5s %-4s %-7s %-4s %-20s${CLR_RESET}\n" "ID" "TYP" "VMID" "ST" "NOM"
                echo -e "${CLR_GR}----------------------------------------------------------${CLR_RESET}"
            fi
            count=1; rm -f /tmp/pmx_map
            while read -r line; do
                IFS='|' read -r type vmid name status cpu_raw mem maxmem disk maxdisk <<< "$line"
                [[ "$FILTER_TYPE" != "all" && "$type" != "$FILTER_TYPE" ]] && continue
                [[ "$FILTER_STATUS" != "all" && "$status" != "$FILTER_STATUS" ]] && continue
                t_lbl=$([[ "$type" == "qemu" ]] && echo "$ICON_VM" || echo "$ICON_LXC")
                s_lbl=$([[ "$status" == "running" ]] && echo -e "${CLR_G}${ICON_ON}${CLR_RESET}" || echo -e "${CLR_R}${ICON_OFF}${CLR_RESET}")
                if [ "$SHOW_PERF" = true ]; then
                    cpu_p=$(echo "$cpu_raw" | awk '{printf "%.2f", $1 * 100}'); [[ $maxmem -eq 0 ]] && maxmem=1
                    mem_p=$(( mem * 100 / maxmem )); dsk_p=$(( disk * 100 / (maxdisk > 0 ? maxdisk : 1) ))
                    printf "[%-2d]  %-3b  %-7s %b   %-18s %b %-6s  %b %-6s  %b %-6s\n" \
                           "$count" "$t_lbl" "$vmid" "$s_lbl" "$(echo $name | cut -c 1-17)" \
                           "$(draw_bar $cpu_p)" "$cpu_p%" "$(draw_bar $mem_p)" "$(human_size $mem)" "$(draw_bar $dsk_p)" "$(human_size $disk)"
                else
                    printf "[%-2d]  %-3b  %-7s %b   %-20s\n" "$count" "$t_lbl" "$vmid" "$s_lbl" "$(echo $name | cut -c 1-19)"
                fi
                echo "$count|$vmid|$type|$status" >> /tmp/pmx_map; ((count++))
            done < <(echo "$ALL_DATA" | jq -r '.[] | select(.type=="qemu" or .type=="lxc") | "\(.type)|\(.vmid)|\(.name)|\(.status)|\(.cpu // 0)|\(.mem // 0)|\(.maxmem // 1)|\(.disk // 0)|\(.maxdisk // 1)"')
            [[ "$FILTER_STATUS" == "stopped" ]] && echo -ne "\n${CLR_Y}Démarrer (ID/N°) [q:quitter] : ${CLR_RESET}" || echo -ne "\n${CLR_Y}Se connecter (ID/N°) [q:quitter] : ${CLR_RESET}"
        fi
    )
    echo -e "$DISPLAY_BUFFER"; tput ed; PREVIOUS_LINES=$(echo -e "$DISPLAY_BUFFER" | wc -l)
    read -t 2 -r choice
    if [[ "$choice" == "q" ]]; then rm -f /tmp/pmx_map; echo ""; exit 0; fi
    if [[ -n "$choice" ]]; then
        MAP_ENTRY=$(grep "^$choice|" /tmp/pmx_map 2>/dev/null || grep "|$choice|" /tmp/pmx_map 2>/dev/null)
        rm -f /tmp/pmx_map
        if [[ -n "$MAP_ENTRY" ]]; then
            IFS='|' read -r num vid vt vs <<< "$MAP_ENTRY"
            [[ "$vs" == "stopped" ]] && do_action "start" "$vid" "$vt" || do_action "term" "$vid" "$vt"
            exit 0
        fi
    fi
done
EOF

# 3. Finalisation
mv "$TEMP_PMX" /usr/local/bin/pmx && chmod +x /usr/local/bin/pmx
echo -e "\n${CLR_G}[3/3] Installation réussie !${CLR_RESET}"
echo -e "Utilisez ${CLR_B}pmx -help${CLR_RESET} pour voir les commandes."
