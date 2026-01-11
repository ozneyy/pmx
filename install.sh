#!/bin/bash

# --- Couleurs ---
CLR_B="\e[34m"; CLR_G="\e[32m"; CLR_Y="\e[33m"; CLR_R="\e[31m"; CLR_RESET="\e[0m"

echo -e "${CLR_B}########################################${CLR_RESET}"
echo -e "${CLR_B}#      PMX - Proxmox Monitoring X       #${CLR_RESET}"
echo -e "${CLR_B}########################################${CLR_RESET}"

# 1. Check Root
if [[ $EUID -ne 0 ]]; then
   echo -e "${CLR_R}Erreur : Lancez ce script en root.${CLR_RESET}"
   exit 1
fi

echo -e "\n${CLR_Y}[1/3] Dépendances (jq, bc)...${CLR_RESET}"
apt update && apt install -y jq bc > /dev/null 2>&1

# 2. Choix Style
echo -e "\n${CLR_Y}[2/3] Configuration graphique...${CLR_RESET}"
echo -ne "${CLR_B}Utiliser NerdFont (icones) ? [y/N] : ${CLR_RESET}"
read -r font_choice < /dev/tty

TEMP_PMX=$(mktemp)

# --- DEBUT DU SCRIPT PMX ---
cat << 'EOF' > "$TEMP_PMX"
#!/bin/bash
# PMX - Proxmox Monitoring X
CLR_G="\e[32m"; CLR_R="\e[31m"; CLR_B="\e[34m"; CLR_Y="\e[33m"; CLR_RESET="\e[0m"; CLR_GR="\e[90m"

# --- Fonctions ---
show_help() {
    echo -e "${CLR_B}Usage:${CLR_RESET}"
    echo -e "  pmx               : Tout afficher"
    echo -e "  pmx on            : Afficher uniquement les VMs allumées"
    echo -e "  pmx off           : Afficher uniquement les VMs éteintes"
    echo -e "  pmx on <id/nom>   : Démarrer une machine spécifique"
    echo -e "  pmx off <id/nom>  : Éteindre une machine spécifique"
    echo -e "  pmx perf [id]     : Mode Dashboard Live"
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
    pvesh get /cluster/resources --output-format json 2>/dev/null | jq -r ".[] | select((.vmid|tostring) == \"$query\" or .name == \"$query\") | \"\(.vmid)|\(.type)|\(.status)\"" | head -n 1
}

do_action() {
    local action=$1; local vid=$2; local vtype=$3
    local cmd=""; local msg=""

    case $action in
        start) 
            [[ "$vtype" == "qemu" ]] && cmd="qm start $vid" || cmd="pct start $vid"
            msg="Démarrage de $vid..." ;;
        stop)  
            [[ "$vtype" == "qemu" ]] && cmd="qm stop $vid"  || cmd="pct stop $vid"
            msg="Arrêt de $vid..." ;;
        term)  
            [[ "$vtype" == "qemu" ]] && cmd="qm terminal $vid" || cmd="pct enter $vid" ;;
    esac

    if [[ -n "$cmd" ]]; then
        if [[ "$action" != "term" ]]; then
            echo -ne "${CLR_Y}$msg ${CLR_RESET}"
            if $cmd >/dev/null 2>&1; then echo -e "${CLR_G}[SUCCÈS]${CLR_RESET}"; else echo -e "${CLR_R}[ERREUR]${CLR_RESET}"; exit 1; fi
        else
            $cmd
        fi
    fi
}
EOF

# --- STYLE ---
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

# --- LOGIQUE PRINCIPALE (Le correctif est ici) ---
cat << 'EOF' >> "$TEMP_PMX"
FILTER_TYPE="all"; FILTER_STATUS="all"; SHOW_PERF=false; TARGET_QUERY=""
ACTION_CMD=""

case $1 in
    help|h|-h|--help|-help) show_help ;;
    on)  
        if [[ -n "$2" ]]; then ACTION_CMD="start"; TARGET_QUERY="$2"; # pmx on 100
        else FILTER_STATUS="running"; fi                              # pmx on (filtre)
        ;;
    off) 
        if [[ -n "$2" ]]; then ACTION_CMD="stop"; TARGET_QUERY="$2";  # pmx off 100
        else FILTER_STATUS="stopped"; fi                              # pmx off (filtre)
        ;;
    perf) SHOW_PERF=true; TARGET_QUERY="$2" ;;
    vm) FILTER_TYPE="qemu";; lxc) FILTER_TYPE="lxc";;
    [0-9]*|*) [[ -z "$ACTION_CMD" ]] && TARGET_QUERY="$1" ;;
esac

# 1. Action Immédiate (Si on a défini ACTION_CMD)
if [[ -n "$ACTION_CMD" && -n "$TARGET_QUERY" ]]; then
    RESULT=$(find_target "$TARGET_QUERY")
    if [[ -n "$RESULT" ]]; then
        IFS='|' read -r vid vtype vstat <<< "$RESULT"
        do_action "$ACTION_CMD" "$vid" "$vtype"
        exit 0
    else
        echo -e "${CLR_R}Erreur : Cible '$TARGET_QUERY' introuvable.${CLR_RESET}"
        exit 1
    fi
fi

# 2. Gestion Action Implicite (pmx 100)
if [[ -n "$TARGET_QUERY" && "$SHOW_PERF" == "false" && -z "$ACTION_CMD" ]]; then
    RESULT=$(find_target "$TARGET_QUERY")
    if [[ -n "$RESULT" ]]; then
        IFS='|' read -r vid vtype vstat <<< "$RESULT"
        [[ "$vstat" == "stopped" ]] && do_action "start" "$vid" "$vtype" || do_action "term" "$vid" "$vtype"
        exit 0
    fi
    # Si pas trouvé, on continue (cas rare ou erreur user)
fi

# 3. Boucle Monitoring (Mode Filtre ou Perf)
PREVIOUS_LINES=0
trap 'tput cnorm; exit' SIGINT SIGTERM
while true; do
    ALL_DATA=$(pvesh get /cluster/resources --output-format json 2>/dev/null)
    if [ $PREVIOUS_LINES -gt 0 ]; then echo -ne "\e[${PREVIOUS_LINES}A"; fi
    
    DISPLAY_BUFFER=$(
        if [[ -n "$TARGET_QUERY" && "$SHOW_PERF" == "true" ]]; then
            # --- VUE PERF FOCUS ---
            raw=$(echo "$ALL_DATA" | jq -r ".[] | select((.vmid|tostring) == \"$TARGET_QUERY\" or .name == \"$TARGET_QUERY\")")
            vid=$(echo "$raw" | jq -r '.vmid')
            if [[ -z "$vid" || "$vid" == "null" ]]; then echo -e "${CLR_R}Cible '$TARGET_QUERY' introuvable.${CLR_RESET}"; exit 1; fi
            
            cpu=$(echo "$raw" | jq -r '.cpu // 0' | awk '{printf "%.2f", $1 * 100}')
            mem_u=$(echo "$raw" | jq -r '.mem // 0'); mem_m=$(echo "$raw" | jq -r '.maxmem // 1')
            disk_u=$(echo "$raw" | jq -r '.disk // 0'); disk_m=$(echo "$raw" | jq -r '.maxdisk // 1')
            
            echo -e "\n${CLR_B}╭─ MONITORING LIVE : $TARGET_QUERY ($vid) ──────────────────╮${CLR_RESET}"
            printf " │ CPU  [%b] %-6s%%  │ RAM  [%b] %-3s%%   │\n" "$(draw_bar $cpu)" "$cpu" "$(draw_bar $((mem_u*100/mem_m)))" "$((mem_u*100/mem_m))"
            printf " │ DSK  [%b] %-3s%%   │ Net  %-18s │\n" "$(draw_bar $((disk_u*100/disk_m)))" "$((disk_u*100/disk_m))" "$(human_size $(echo "$raw" | jq -r '.netin // 0'))"
            echo -e "${CLR_B}╰──────────────────────────────────────────────────────────╯${CLR_RESET}"
            echo -ne "${CLR_Y}Se connecter ($vid) [q:quitter] : ${CLR_RESET}"
        else
            # --- VUE LISTE (Filtrée ou non) ---
            echo ""
            [ "$SHOW_PERF" = true ] && printf "${CLR_B}%-5s %-4s %-7s %-4s %-18s %-18s %-18s %-18s${CLR_RESET}\n" "ID" "TYP" "VMID" "ST" "NOM" "CPU %" "RAM" "DISK" || printf "${CLR_B}%-5s %-4s %-7s %-4s %-20s${CLR_RESET}\n" "ID" "TYP" "VMID" "ST" "NOM"
            echo -e "${CLR_GR}----------------------------------------------------------------------------------------------------${CLR_RESET}"
            
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
            
            if [[ "$FILTER_STATUS" == "stopped" ]]; then
                echo -ne "\n${CLR_Y}Démarrer (ID/N°) [q:quitter] : ${CLR_RESET}"
            else
                echo -ne "\n${CLR_Y}Se connecter (ID/N°) [q:quitter] : ${CLR_RESET}"
            fi
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
            
            # Comportement selon le filtre actif
            if [[ "$FILTER_STATUS" == "stopped" ]]; then
                 # Si on est dans pmx off, on démarre
                 do_action "start" "$vid" "$vt"
                 exit 0
            else
                 # Sinon comportement standard (auto start ou console)
                 [[ "$vs" == "stopped" ]] && do_action "start" "$vid" "$vt" || do_action "term" "$vid" "$vt"
                 exit 0
            fi
        fi
    fi
done
EOF

mv "$TEMP_PMX" /usr/local/bin/pmx && chmod +x /usr/local/bin/pmx
echo -e "\n${CLR_G}[3/3] Installation terminée !${CLR_RESET}"
