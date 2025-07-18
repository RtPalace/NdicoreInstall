#!/bin/bash
#Ndicore auto install script.

# 配置参数
OEM="kiloview"
IMAGE_NAME=
UPDATEED_APT="NO"
BACKUP_DATA="NO"
DOCKER_LOCATION_CN="YES"
CONTAINER_NAME="Ndicore"
DATA_PATH="/root/cp_data_hardware"
BACKUP_DATA_PATH="/root/ndicore/backup"
BACKUP_DATA_TIME_PATH="$BACKUP_DATA_PATH/cp_data_hardware_$(date +%Y%m%d_%H%M%S)"

# 定义颜色变量
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
NC='\033[0m' # No Color

# 定义背景色变量
BG_BLACK='\033[0;40m'
BG_RED='\033[0;41m'
BG_GREEN='\033[0;42m'
BG_YELLOW='\033[0;43m'
BG_BLUE='\033[0;44m'
BG_PURPLE='\033[0;45m'
BG_CYAN='\033[0;46m'
BG_WHITE='\033[0;47m'

# 定义样式变量
BOLD='\033[1m'
UNDERLINE='\033[4m'
RESET='\033[0m'

prepare_for_installation() {
    echo -e "${GREEN}⭐ Preparation for installation Start...${NC}"
    # 检查是否为 root 用户
    if [[ $EUID -ne 0 ]]; then
    echo -e "${YELLOW}This script must be run as root${NC}" 
    exit 1
    fi

    if [ ! -d "$BACKUP_DATA_PATH" ]; then
        mkdir -p $BACKUP_DATA_PATH
    fi

    if [ ! -d "$DATA_PATH" ]; then
        mkdir -p $DATA_PATH
    fi

    check_dependencys
    echo -e "${GREEN}⭐ Preparation for installation End\n${NC}"
}

check_dependencys() {
    echo -e "${GREEN}⌛ Check dependencys...${NC}"
    # avahi
    apt_install "avahi-daemon" "avahi-daemon avahi-utils"

    # docker
    apt_install "docker" docker.io

    # curl
    apt_install "curl" "curl"
}

update_apt() {
    if [ "$UPDATEED_APT" = "NO" ]; then
        local temp_log=$(mktemp)
        # 静默执行apt-get update但捕获错误
        echo -e "${YELLOW}⌛ Update apt...${NC}"
        if apt-get update -qq >/dev/null 2>"$temp_log"; then
            UPDATEED_APT="YES"
            echo -e "${GREEN}✅ update apt OK${NC}"
            rm -f "$temp_log"
        else
            echo -e "${RED}❌ ERROR DETAILS:${NC}"
            cat "$temp_log"
            
            echo -e "\n${RED}Troubleshooting:${NC}"
            echo "1. Check network connection: ping archive.ubuntu.com"
            echo "2. Verify repository config: cat /etc/apt/sources.list"
            echo "3. Try manual update: sudo apt-get update"
            rm -f "$temp_log"
            exit 1
        fi
    fi
}

apt_install() {
    local check_pk="$1"
    local install_pk="$2"
    if command -v $pk &>/dev/null; then
        echo -e "${YELLOW}$check_pk has been installed${NC}"
        return 0
    fi
    echo -e "${YELLOW}$check_pk not installed, needs to be installed... ${NC}"
    update_apt
    local temp_log=$(mktemp)
    echo -e "${YELLOW}⌛ Apt install $install_pk...${NC}"
    if apt install $install_pk -qq -y >/dev/null 2>"$temp_log"; then
        echo -e "${GREEN}✅ Successfully install $install_pk ${NC}"
        rm -f "$temp_log"
    else
        echo -e "${RED}❌ Failed to install $install_pk ${NC}"
        echo -e "\n${RED}ERROR DETAILS:${NC}"
        cat "$temp_log"
        rm -f "$temp_log"
        exit 1
    fi
}

clean_old_containers() {
    # 清理旧版版本容器，选择是否保留旧数据
    # 获取容器列表（优化版）
    local containers=$(docker ps -a --format '{{.ID}}\t{{.Image}}' | awk -F'\t' '
        $2 ~ /^(oem|kiloview)[\/](ndicore|kv_ndicore.+$)/ || 
        $2 ~ /^nicolargo\/glances+$/ {
            print $1
            next
        }
        # 处理可能是镜像ID的情况
        $2 ~ /^[a-f0-9]{12}$/ || $2 ~ /^sha256:[a-f0-9]{64}$/ {
            # 获取镜像的实际仓库标签
            cmd = "docker inspect --format \"{{index .RepoTags 0}}\" "$2" 2>/dev/null"
            if ((cmd | getline repo) > 0) {
                if (repo ~ /^(oem|kiloview)[\/](ndicore|kv_ndicore.+$)/ ||
                    repo ~ /^nicolargo\/glances+$/) {
                    print $1
                    close(cmd)
                    next
                }
            } else {
                # 如果inspect失败检查容器使用的镜像名
                cmd = "docker inspect --format \"{{.Config.Image}}\" "$1" 2>/dev/null"
                if ((cmd | getline image_name) > 0) {
                    if (image_name ~ /^(oem|kiloview)[\/](ndicore|kv_ndicore.+$)/ ||
                        image_name ~ /^nicolargo\/glances+$/) {
                        print $1
                        close(cmd)
                        next
                    }
                }
            }
            close(cmd)
        }
    ')

    if [ -z "$containers" ]; then
        echo -e "${GREEN}No Ndicore container found for cleaning${NC}"
        return 0
    fi

    # 显示找到的容器
    echo -e "${YELLOW}Found the following old Ndicore container that needs to be cleaned:${NC}"
    docker ps -a | grep -E "$(echo "$containers" | paste -sd "|" -)"

    # 备份数据
    backup_data

    echo -e "${GREEN}⭐ Clean old containers Start...${NC}"
    # 删除旧容器
    local ids=$(echo "$containers" | cut -d'|' -f1 | tr '\n' ' ')
    
    # 优雅停止运行中的容器
    echo "Stop containers..."
    docker stop $ids 2>/dev/null || true
    echo "Stop containers ok"
    
    # 强制删除所有指定容器
    echo "Delete containers..."
    if ! docker rm -f $ids 2>/dev/null; then
        echo -e "${RED}❌ Error: Partial container deletion failed${NC}" >&2
        return 1
    fi
    echo "Delete containers ok"
    
    # 验证删除结果并打印详细报告
    local remaining=$(docker ps -aq --filter "id=$ids")
    if [ -z "$remaining" ]; then
        echo -e "${GREEN}✅ All containers have been successfully deleted${NC}"
        echo -e "${GREEN}✅ The container ID has been deleted: ${NC}${ids// /, }"
        # 清理旧数据
        rm -rf $DATA_PATH/*
        echo -e "${GREEN}⭐ Clean old containers End\n${NC}"
        return 0
    else
        echo -e "${RED}❌ Container deletion incomplete${NC}"
        echo -e "${GREEN}✅ The container ID has been deleted: ${ids//$remaining/}${NC}" | tr ' ' '\n' | grep -v "^$"
        echo -e "${RED}Residual container ID: ${remaining}${NC}"
        return 1
    fi
}

backup_data () {
    read -p "Do you want to backup the data❓ [Y/n] (default Y):" backup_choice
    backup_choice=${backup_choice:-Y}  # 设置默认值为Y
    case "$backup_choice" in
        [yY])
            echo -e "${GREEN}⭐ Backup Data Start...${NC}"
            echo -e "${GREEN}⌛ Backing up old data ...${NC}"
            if rsync -a --info=progress2 "$DATA_PATH/" "$BACKUP_DATA_TIME_PATH/"; then
                BACKUP_DATA="YES"
                echo -e "${GREEN}✅ Backup successful${NC}"
                echo -e "Source directory["$DATA_PATH"]: $(du -sh "$DATA_PATH" | cut -f1) ---> Backup location[$BACKUP_DATA_TIME_PATH]: $(du -sh "$BACKUP_DATA_TIME_PATH" | cut -f1)"
                echo -e "${GREEN}⭐ Backup Data End\n${NC}"
            else
                echo -e "${RED}❌ Backup failed${NC}"
                exit 1
            fi
            ;;
        [nN])
            echo -e "${YELLOW}Skip backup operation${NC}"
            ;;
        *)
            echo -e "${RED}❌ Error: Invalid input, please use Y/y or N/n${NC}"
            exit 1
            ;;
    esac
}

restore_data() {
    if [ ! -d "$DATA_PATH" ]; then
        mkdir -p $DATA_PATH
    fi
    rm -rf "$DATA_PATH/*"
    # 是否恢复数据
    if [ "$BACKUP_DATA" = "YES" ]; then
        echo -e "${GREEN}⭐ Restore data Start...${NC}"
        cp -rf $BACKUP_DATA_TIME_PATH/* $DATA_PATH
        echo -e "${GREEN}⭐ Restore data End\n${NC}"
    fi
}

install_new_container() {
    echo -e "${GREEN}⭐ Install new container Start...${NC}"
    # 恢复数据
    restore_data
    # 开始创建容器
    if [ ! -d "/upgrade" ]; then
        mkdir -p "/upgrade"
    fi
    echo -e "${YELLOW}⌛ create container Ndicore...${NC}"
    docker run --name=$CONTAINER_NAME -idt \
            --log-driver=none \
            --network host \
            --privileged=true \
            --restart=always \
            -v /etc/localtime:/etc/localtime:ro \
            -v /var/run/avahi-daemon:/var/run/avahi-daemon \
            -v /var/run/dbus:/var/run/dbus \
            -v /opt/package:/opt/package \
            -v /upgrade:/upgrade \
            -v /root/cp_data_hardware:/app/data/ndicore \
            $IMAGE_NAME \
            /usr/local/bin/ndicore_start.sh
    if [ $? -ne 0 ]; then
        >&2 echo -e "${RED}❌ Error: Failed to create container $CONTAINER_NAME ${NC}"
        echo "---->$IMAGE_NAME"
        exit 0
    fi
    echo -e "${GREEN}✅ Successfully created container Ndicore${NC}"

    # 删除备份数据
    # rm -rf $BACKUP_DATA_PATH
    echo -e "${GREEN}⭐ Install new container End\n${NC}"
}

# 镜像查询与拉取函数
query_and_pull_image() {
    echo -e "${GREEN}⭐ Query and pull ndiore docker image start...${NC}"
    echo "🔍 Querying ndicore image tags..."

    if [ "$DOCKER_LOCATION_CN" = "YES" ]; then
        local repo="docker.kiloview.com/kiloview/ndicore"
        # 查询标签
        local response=$(curl -s "https://docker.kiloview.com/v2/kiloview/ndicore/tags/list")
        # 提取标签
        local tags=$(echo "$response" | 
                    grep -o '"tags":\[[^]]*\]' | 
                    awk -F'[\\[\\]]' '{print $2}' | 
                    tr -d '"' | tr ',' '\n' |
                    sort -V)
    else
        local repo="kiloview/ndicore"
        # 查询标签
        local response=$(curl -s "https://hub.docker.com/v2/repositories/kiloview/ndicore/tags/")
        # 提取标签
        local tags=$(echo "$response" \
            | grep -o '"name":"[^"]*"' \
            | sed 's/"name":"\(.*\)"/\1/')
    fi

    if [ -z "$tags" ]; then
        echo "⚠️ No available image tags found"
        return 1
    fi

    # 显示标签菜单
    echo "✅ Available ndicore image tags:"
    local i=1
    local tag_list=()
    while read -r tag; do
        echo "  [$i] "kiloview/ndicore":$tag"
        tag_list+=("$tag")
        ((i++))
    done <<< "$tags"

    # 用户选择
    read -p "💡 Please enter the ndicore image to be pulled (1-$((i-1))): " choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice >= i )); then
        echo -e "${RED}❌ Invalid selection${NC}"
        exit 1
    fi

    selected_tag="${tag_list[$((choice-1))]}"

    echo -e "${YELLOW} 🚀 Pulling in $repo:$selected_tag ...${NC}"
    
    if docker pull "$repo:$selected_tag"; then
        echo -e "${GREEN} ✅ Pull successful${NC}"
        IMAGE_NAME="kiloview/ndicore:$selected_tag"
        if [ "$DOCKER_LOCATION_CN" = "YES" ]; then
            docker tag "$repo:$selected_tag" $IMAGE_NAME && docker rmi "$repo:$selected_tag"
        fi
        echo "Docker image information:"
        docker images | grep "kiloview/ndicore" | grep "$selected_tag"
        echo -e "${GREEN}⭐ Query and pull ndiore docker image End\n${NC}"
    else
        echo -e "${RED} ❌ Pull failed${NC}"
        exit 1
    fi
}

install_ndicore() {
    echo -e "${BOLD}${BG_BLUE}🚀 Kiloview Ndicore Installer Starting...${NC}"
    prepare_for_installation
    clean_old_containers
    query_and_pull_image
    install_new_container
    success_log='
           _______  _______________  __________
          / ___/ / / / ___/ ___/ _ \/ ___/ ___/
         (__  ) /_/ / /__/ /__/  __(__  |__  ) 
        /____/\__ _/\___/\___/\___/____/____/  
'   
    echo -e "${BOLD}${GREEN}🎉 Install Ndicore end${NC}"
    echo -e "${BOLD}${BLUE}$success_log${NC}"
}

uninstall_ndicore() {
    echo -e "${BOLD}${BG_BLUE}🚀 Kiloview Ndicore Uninstaller Starting...${NC}"
    prepare_for_installation
    clean_old_containers
    success_log='
           _______  _______________  __________
          / ___/ / / / ___/ ___/ _ \/ ___/ ___/
         (__  ) /_/ / /__/ /__/  __(__  |__  ) 
        /____/\__ _/\___/\___/\___/____/____/  
'   
    echo -e "${BOLD}${GREEN}🎉 Uninstall Ndicore end${NC}"
    echo -e "${BOLD}${BLUE}$success_log${NC}"
}

main() {
    kiloview_log='
            __   _ __           _             
           / /__(_) /___ _   __(_)__ _      __
          / //_/ / / __ \ | / / / _ \ | /| / /
         / .< / / / /_/ / |/ / /  __/ |/ |/ / 
        /_/|_/_/_/\____/|___/_/\___/|__/|__/ 
'
    echo -e "${BOLD}${BLUE}$kiloview_log${NC}"
    echo -e "${GREEN}⭐ ====================================================${NC}"
    echo "       Ndicore Install Management Tool v1.0      "
    echo -e "${GREEN}-------------------------------------------------------${NC}"
    echo -e "${YELLOW}  1. Install Ndicore${NC}"
    echo -e "${YELLOW}  2. Uninstall Ndicore${NC}"
    echo -e "${YELLOW}  3. Exit${NC}"
    echo -e "${GREEN}⭐ ====================================================${NC}"
    read -p "💡 Please enter your selection (1-3): " choice

    case $choice in
        1)
            install_ndicore
            ;;
        2)
            uninstall_ndicore
            ;;
        3)
            echo -e "${GREEN}Thank you for using it, goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Invalid input, please select again${NC}"
            sleep 0.1
            exit 1
            ;;
    esac
}

usage() {
    echo "Usage:"
    echo "    $1 [cn|en] [-h|--help]"
    echo
    echo "Options:"
    echo "    cn          Use domestic docker image sources"
    echo "    en          Use foreign docker image sources"
    echo "    -h, --help  Display help information"
    return 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage "$0"
            exit 0
            ;;
        cn)
            DOCKER_LOCATION_CN="YES"
            shift
            ;;
        en)
            DOCKER_LOCATION_CN="NO"
            shift
            ;;
        *)
            echo "错误：未知参数 '$1'"
            usage "$0"
            exit 1
            ;;
    esac
done

main