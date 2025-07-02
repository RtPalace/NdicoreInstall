#!/bin/bash
#Ndicore auto install script.

# 配置参数
OEM="kiloview"
VERSION=
UPDATEED_APT="NO"
BACKUP_DATA="NO"
CONTAINER_NAME="Ndicore"
INSTALL_FILE=
DATA_PATH="/root/cp_data_hardware"
BACKUP_DATA_PATH="/root/ndicore/backup"
BACKUP_DATA_TIME_PATH="$BACKUP_DATA_PATH/cp_data_hardware_$(date +%Y%m%d_%H%M%S)"
DOWNLOAD_FILE_PATH="/tmp/kiloview_packages"
URL="https://download.kiloview.com/NDICORE/"

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


usage() {
    echo "Usage:"
    echo "    $1 [image-package] [-h|--help]"
    echo
    echo ""
    return 0
}

while [ $# -gt 0 ]; do
    if [ "$1" = "-h" -o "$1" = "--help" ]; then
        usage $0
        exit 0
    fi
    shift
done


start_logo() {
    kiloview_log='
            __   _ __           _             
           / /__(_) /___ _   __(_)__ _      __
          / //_/ / / __ \ | / / / _ \ | /| / /
         / .< / / / /_/ / |/ / /  __/ |/ |/ / 
        /_/|_/_/_/\____/|___/_/\___/|__/|__/ 

'
    echo -e "${BOLD}${GREEN}$kiloview_log${NC}"
    echo -e "${BOLD}${BG_BLUE}🚀 Kiloview NDI CORE Installer Starting...${NC}"
}

end_logo() {
    success_log='
           _______  _______________  __________
          / ___/ / / / ___/ ___/ _ \/ ___/ ___/
         (__  ) /_/ / /__/ /__/  __(__  |__  ) 
        /____/\__ _/\___/\___/\___/____/____/  
'   
    echo -e "${BOLD}${GREEN}🎉 Install Ndicore end${NC}"
    echo -e "${BOLD}${BLUE}$success_log${NC}"
}


prepare_for_installation() {
    echo -e "${GREEN}⭐ ++++++++++++++++Preparation for installation Start++++++++++++++++${NC}"
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
    echo -e "${GREEN}⭐ ++++++++++++++++Preparation for installation End++++++++++++++++++\n${NC}"
}

check_dependencys() {
    echo -e "${GREEN}⌛ Check dependencys...${NC}"
    # avahi
    apt_install "avahi-daemon avahi-utils"

    # docker
    apt_install docker.io

    # curl
    apt_install curl
}

update_apt() {
    if [ "$UPDATEED_APT" = "NO" ]; then
        local temp_log=$(mktemp)
        # 静默执行apt-get update但捕获错误
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
    local pk="$1"
    if command -v $pk &>/dev/null; then
        echo -e "${YELLOW}$pk has been installed${NC}"
        return 0
    fi
    echo -e "${YELLOW}$pk not installed, needs to be installed... ${NC}"
    update_apt
    local temp_log=$(mktemp)
    if apt install $pk -qq -y >/dev/null 2>"$temp_log"; then
        echo -e "${GREEN}✅ Successfully install $pk ${NC}"
        rm -f "$temp_log"
    else
        echo -e "${RED}❌ Failed to install $pk ${NC}"
        echo -e "\n${RED}ERROR DETAILS:${NC}"
        cat "$temp_log"
        rm -f "$temp_log"
        exit 1
    fi
}

install() {
    start_logo

    prepare_for_installation

    download_install_package

    clean_old_containers

    install_new_container

    end_logo
}

download_install_package() {
    echo -e "${GREEN}⭐ ++++++++++++++++++Download install package Start++++++++++++++++++${NC}"
    # 查询有哪些版本可以安装
    mkdir -p "$DOWNLOAD_FILE_PATH"  # 确保目录存在
    # 获取并处理安装包列表
    echo -e "${YELLOW}🔍 Getting installation package list...${NC}"
    PACKAGES=($(curl -s "$URL" | grep -o 'install-kiloview-ndicore-[^"<>]*\.tar\.gz'))
    if [ ${#PACKAGES[@]} -eq 0 ]; then
        echo -e "${RED}❌ Error: No installation package found${NC}"
        exit 1
    fi
    UNIQUE_PACKAGES=($(printf "%s\n" "${PACKAGES[@]}" | sort -V -r -u))  # 按版本号降序排序

    # 显示可用的安装包
    echo -e "${GREEN}Found ${#UNIQUE_PACKAGES[@]} available installation packages:${NC}"
    for i in "${!UNIQUE_PACKAGES[@]}"; do
        version=$(echo "${UNIQUE_PACKAGES[$i]}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
        printf "${YELLOW} %2d) VERSION:%-10s FILE:%-60s SIZE:%s${NC}\n" \
            $((i+1)) \
            "$version" \
            "${UNIQUE_PACKAGES[$i]}" \
            "$(curl -sI "${URL}${UNIQUE_PACKAGES[$i]}" | grep -i 'content-length' | awk '{print $2/1024/1024"MB"}')"
    done
    # 选择下载特定版本的安装包
    read -p "💡 Please enter the number to download (1-${#UNIQUE_PACKAGES[@]}), or q exits:" choice

    # 处理用户输入
    if [[ "$choice" =~ [qQ] ]]; then
        echo -e "${YELLOW}Download cancelled${NC}"
        exit 0
    elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#UNIQUE_PACKAGES[@]} )); then
        selected_pkg="${UNIQUE_PACKAGES[$((choice-1))]}"
        download_url="${URL}${selected_pkg}"
        INSTALL_FILE="${DOWNLOAD_FILE_PATH}/${selected_pkg}"

        # 检查文件是否已存在
        if [ -f "${INSTALL_FILE}" ]; then
            echo -e "${YELLOW}⌛ Detected an existing file with the same name, deleting it...${NC}"
            if rm -f "${INSTALL_FILE}"; then
                echo -e "${GREEN}✅ Successfully delete the old file${NC}"
            else
                echo -e "${RED}❌ Error: Unable to delete old files, please check permissions${NC}"
                exit 1
            fi
        fi

        # 打印用户选择的版本和文件
        VERSION=$(echo "$selected_pkg" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
        echo -e "${GREEN}Download information:${NC}"
        echo -e "${NC}Version: $VERSION${NC}"
        echo -e "${NC}File: $selected_pkg${NC}"
        echo -e "${NC}Save to: $INSTALL_FILE${NC}"
        
        # 下载文件
        donwload_file "$download_url" "$INSTALL_FILE"
    else
        echo -e "${RED}❌ Invalid input!${NC}"
        exit 1
    fi
    echo -e "${GREEN}⭐ ++++++++++++++++++Download install package End++++++++++++++++++++\n${NC}"
}

donwload_file() {
    local url="$1"
    local output="$2"
    echo -e "${YELLOW}⌛ Start downloading...${NC}"

    if curl -# -fSL -C - -o "$output" "$url"; then
        echo -e "${GREEN}✅ Download successful！${NC}"
        echo -e "${GREEN}The file has been saved to：$output${NC}"
        echo -e "${GREEN}File size：$(du -h "$output" | cut -f1)${NC}"
        
        # 可选：自动验证文件完整性
        echo -e "${YELLOW}⌛ Verifying file integrity...${NC}"
        remote_size=$(curl -sIL "$url" | grep -i 'content-length' | awk '{print $2}' | tr -d '\r' | grep -E '^[0-9]+$')
        remote_size=${remote_size:-0}

        # 获取本地文件大小
        local_size=$(stat -c%s "$INSTALL_FILE" 2>/dev/null || echo 0)

        # 比较大小
        if [ "$remote_size" -gt 0 ] && [ "$local_size" -eq "$remote_size" ]; then
            echo -e "${GREEN}✅ File size verification passed ($(numfmt --to=iec $local_size))${NC}"
        else
            echo -e "${RED}❌ File size mismatch (local: $(numfmt --to=iec $local_size) / remote: $(numfmt --to=iec $remote_size))${NC}"
            exit 1
        fi
    else
        echo -e "${RED}❌ Download failed！${NC}"
        exit 1
    fi
}

clean_old_containers() {
    # 清理旧版版本容器，选择是否保留旧数据
    # 获取容器列表（优化版）
    local containers=$(docker ps -a --format '{{.ID}}\t{{.Image}}' | awk -F'\t' '
        $2 ~ /^oem\/ndicore:[0-9]+\.[0-9]+\.[0-9]+$/ || 
        $2 ~ /^kiloview\/kv_ndicore.+$/ || 
        $2 ~ /^nicolargo\/glances+$/ || 
        $2 ~ /^kiloview\/ndicore:[0-9]+\.[0-9]+\.[0-9]+$/ {print $1}
    ')

    if [ -z "$containers" ]; then
        echo -e "${GREEN}No Ndicore container found for cleaning${NC}"
        return 0
    fi

    # 显示找到的容器
    echo -e "${YELLOW}Found the following old Ndicore container that needs to be cleaned:${NC}"
    docker ps -a --filter "id=$(echo "$containers" | cut -d'|' -f1 | tr '\n' ' ')" \
        --format "table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}" | column -t -s $'\t'

    # 备份数据
    backup_data

    echo -e "${GREEN}⭐ +++++++++++++++++++Clean old containers Start+++++++++++++++++++${NC}"
    # 删除旧容器
    local ids=$(echo "$containers" | cut -d'|' -f1 | tr '\n' ' ')
    
    # 优雅停止运行中的容器
    docker stop $ids 2>/dev/null || true
    
    # 强制删除所有指定容器
    if ! docker rm -f $ids 2>/dev/null; then
        echo -e "${RED}❌ Error: Partial container deletion failed${NC}" >&2
        return 1
    fi
    
    # 验证删除结果并打印详细报告
    local remaining=$(docker ps -aq --filter "id=$ids")
    if [ -z "$remaining" ]; then
        echo -e "${GREEN}✅ All containers have been successfully deleted${NC}"
        echo -e "${GREEN}✅ The container ID has been deleted: ${NC}${ids// /, }"
        echo -e "${GREEN}⭐ +++++++++++++++++++Clean old containers End+++++++++++++++++++++\n${NC}"
        return 0
    else
        echo -e "${RED}❌ Container deletion incomplete${NC}"
        echo -e "${GREEN}✅ The container ID has been deleted: ${ids//$remaining/}${NC}" | tr ' ' '\n' | grep -v "^$"
        echo -e "${RED}Residual container ID: ${remaining}${NC}"
        return 1
    fi
}

backup_data () {
    read -p "Do you want to back up the data❓ [Y/n] (default Y):" backup_choice
    backup_choice=${backup_choice:-Y}  # 设置默认值为Y
    case "$backup_choice" in
        [yY])
            echo -e "${GREEN}⭐ ++++++++++++++++++++++++Backup Data Start+++++++++++++++++++++++${NC}"
            echo -e "${GREEN}⌛ Backing up old data ...${NC}"
            if rsync -a --info=progress2 "$DATA_PATH/" "$BACKUP_DATA_TIME_PATH/"; then
                BACKUP_DATA="YES"
                echo -e "${GREEN}✅ Backup successful${NC}"
                echo -e "Source directory: $(du -sh "$DATA_PATH" | cut -f1) ---> Backup location: $(du -sh "$BACKUP_DATA_TIME_PATH" | cut -f1)"
                echo -e "${GREEN}⭐ +++++++++++++++++++++++++Backup Data End+++++++++++++++++++++++++\n${NC}"
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
        echo -e "${GREEN}⭐ ++++++++++++++++++++++++Restore data Start+++++++++++++++++++++++${NC}"
        cp -rf "$BACKUP_DATA_TIME_PATH/*" $DATA_PATH
        echo -e "${GREEN}⭐ +++++++++++++++++++++++++Restore data End++++++++++++++++++++++++\n${NC}"
    fi
}

install_new_container() {
    echo -e "${GREEN}⭐ ++++++++++++++++++Install new container Start+++++++++++++++++++${NC}"
    # 安装新版本
    if [ ! -f "$INSTALL_FILE" ]; then
        echo -e "${RED}❌ Error: Installation file does not exist${NC}"
        echo -e "Expected path: ${INSTALL_FILE}"
        exit 1
    fi

    # 解压安装包
    # 解压到目标目录（带进度显示）
    echo -e "${YELLOW}⌛ Decompressing to $DOWNLOAD_FILE_PATH ...${NC}"
    echo -e "⌛ Under decompression ..."
    if ! tar -xzf "$INSTALL_FILE" -C "$DOWNLOAD_FILE_PATH"; then
        echo -e "${RED}❌ Error during decompression process${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Successfully decompressed${NC}"

    full_image="$$OEM/ndicore:$VERSION"
    # 检查镜像是否存在
    if docker inspect "$full_image" &> /dev/null; then
        echo -e "${YELLOW}⌛ Docker image $full_image exists and is being deleted...${NC}"
        if docker rmi "$full_image"; then
            echo  -e "${GREEN}✅ Successfully delete docker image $full_image${NC}"
        else
            echo -e "${RED}❌ Failed to delete docker image $full_image${NC}"
            exit 1
        fi
    fi

    image_filename="image-$OEM-ndicore-$VERSION.tar"
    image_file="$DOWNLOAD_FILE_PATH/$OEM-ndicore-$VERSION-software/$image_filename"
    # 加载镜像并检查结果
    echo -e "${YELLOW}⌛ Loading Docker image ...${NC}"
    if ! output=$(docker load -i "$image_file" 2>&1); then
        echo -e "${RED}❌ Failed to load image:${NC}" >&2
        echo "$output" >&2
        exit 1
    fi
    echo "$output" | grep "Loaded image"
    echo -e "${GREEN}✅ Image loading successful!${NC}"

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
            $OEM/ndicore:$VERSION \
            /usr/local/bin/ndicore_start.sh
    if [ $? -ne 0 ]; then
        >&2 echo -e "${RED}❌ Error: Failed to create container $CONTAINER_NAME ${NC}"
        exit 0
    fi
    echo -e "${GREEN}✅ Successfully created container Ndicore${NC}"

    # 删除备份数据
    rm -rf $BACKUP_DATA_PATH
    # 删除安装包
    rm -rf $DOWNLOAD_FILE_PATH
    echo -e "${GREEN}⭐ +++++++++++++++++++Install new container End+++++++++++++++++++++\n${NC}"
}

install
