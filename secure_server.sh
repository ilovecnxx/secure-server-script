#!/bin/bash

# 服务器安全配置脚本 - 新手友好版
# 功能：禁止ROOT登录、禁止密码登录、修改SSH端口、配置密钥登录
# 特点：交互式操作、详细解释、自动备份、错误处理

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认配置
DEFAULT_SSH_PORT=2222
BACKUP_DIR="/etc/ssh/backup_$(date +%Y%m%d_%H%M%S)"
SSH_CONFIG="/etc/ssh/sshd_config"

# 检测是否为交互式环境
is_interactive() {
    [[ $- == *i* ]]
}

# 检测是否通过管道执行（非交互式）
is_pipe() {
    [[ -p /dev/stdin ]]
}

# 检查是否为非交互式环境
is_non_interactive() {
    ! is_interactive || is_pipe
}

# 交互式选择SSH端口
select_ssh_port() {
    local USER_PORT=""
    local CONFIRM=""
    
    # 检查是否为非交互式环境
    if is_non_interactive; then
        echo -e "${BLUE}\n======================================${NC}"
        echo -e "${BLUE}步骤3：选择SSH端口${NC}"
        echo -e "${BLUE}======================================${NC}"
        echo -e "${YELLOW}非交互式环境下，使用默认端口。${NC}"
        SSH_PORT=$DEFAULT_SSH_PORT
        echo -e "${GREEN}使用默认端口：${SSH_PORT}${NC}"
        return
    fi
    
    # 初始化SSH_PORT变量
    SSH_PORT=""
    
    while [ -z "$SSH_PORT" ]; do
        echo -e "${BLUE}\n======================================${NC}"
        echo -e "${BLUE}步骤3：选择SSH端口${NC}"
        echo -e "${BLUE}======================================${NC}"
        echo -e "${YELLOW}SSH端口是远程连接服务器的入口，默认端口22容易受到攻击。${NC}"
        echo -e "${YELLOW}建议选择1024-65535之间的端口，避免使用常用端口。${NC}"
        echo -e "${YELLOW}默认推荐端口：${DEFAULT_SSH_PORT}${NC}"
        
        # 简单的read命令，不添加超时，确保等待用户输入
        read -p "请输入您要使用的SSH端口（直接回车使用默认值 ${DEFAULT_SSH_PORT}）： " USER_PORT
        
        # 检查输入是否为空，使用默认值
        if [ -z "$USER_PORT" ]; then
            SSH_PORT=$DEFAULT_SSH_PORT
            echo -e "${GREEN}使用默认端口：${SSH_PORT}${NC}"
        else
            # 检查输入是否为数字
            if ! [[ "$USER_PORT" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}错误：端口号必须是数字！${NC}"
                continue
            fi
            
            # 检查端口范围
            if [ "$USER_PORT" -lt 1024 ] || [ "$USER_PORT" -gt 65535 ]; then
                echo -e "${RED}错误：端口号必须在1024-65535之间！${NC}"
                continue
            fi
            
            SSH_PORT=$USER_PORT
            echo -e "${GREEN}已选择端口：${SSH_PORT}${NC}"
        fi
        
        # 确认端口选择，不添加超时
        read -p "确认使用端口 ${SSH_PORT} 吗？(y/n)： " CONFIRM
        if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
            SSH_PORT=""  # 重置端口，重新开始循环
            echo -e "${YELLOW}已取消选择，重新开始...${NC}"
        fi
    done
}

# 检查是否以root用户运行
check_root() {
    echo -e "${BLUE}\n======================================${NC}"
    echo -e "${BLUE}步骤1：检查权限${NC}"
    echo -e "${BLUE}======================================${NC}"
    echo -e "${YELLOW}正在检查当前用户权限...${NC}"
    echo -e "${YELLOW}修改SSH配置需要root权限，这是系统最高权限。${NC}"
    
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误：请以root用户运行此脚本！${NC}"
        echo -e "${RED}您可以使用 'sudo ./secure_server.sh' 命令来运行。${NC}"
        exit 1
    else
        echo -e "${GREEN}✓ 已获得root权限，可以继续操作。${NC}"
    fi
}

# 创建新用户
create_new_user() {
    echo -e "${BLUE}\n======================================${NC}"
    echo -e "${BLUE}步骤2.1：创建新用户${NC}"
    echo -e "${BLUE}======================================${NC}"
    
    local NEW_USER=""
    local NEW_PASSWORD=""
    local CONFIRM_PASSWORD=""
    
    # 输入用户名
    while [ -z "$NEW_USER" ]; do
        read -p "请输入要创建的用户名： " NEW_USER
        if [ -z "$NEW_USER" ]; then
            echo -e "${RED}错误：用户名不能为空！${NC}"
        elif id "$NEW_USER" &>/dev/null; then
            echo -e "${RED}错误：用户 $NEW_USER 已存在！${NC}"
            NEW_USER=""
        fi
    done
    
    # 输入密码
    while [ -z "$NEW_PASSWORD" ]; do
        read -s -p "请输入密码： " NEW_PASSWORD
        echo
        if [ -z "$NEW_PASSWORD" ]; then
            echo -e "${RED}错误：密码不能为空！${NC}"
            continue
        fi
        
        # 密码强度检查
        if [ ${#NEW_PASSWORD} -lt 8 ]; then
            echo -e "${YELLOW}警告：密码长度小于8位，建议使用强密码！${NC}"
        fi
        
        read -s -p "请再次输入密码： " CONFIRM_PASSWORD
        echo
        
        if [ "$NEW_PASSWORD" != "$CONFIRM_PASSWORD" ]; then
            echo -e "${RED}错误：两次输入的密码不一致！${NC}"
            NEW_PASSWORD=""
            CONFIRM_PASSWORD=""
        fi
    done
    
    # 创建用户
    echo -e "${YELLOW}正在创建用户 $NEW_USER...${NC}"
    useradd -m -s /bin/bash "$NEW_USER"
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误：创建用户失败！${NC}"
        return 1
    fi
    
    # 设置密码
    echo -e "${YELLOW}正在设置用户密码...${NC}"
    echo "$NEW_USER:$NEW_PASSWORD" | chpasswd
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误：设置密码失败！${NC}"
        return 1
    fi
    
    # 授予sudo权限
    echo -e "${YELLOW}正在授予sudo权限...${NC}"
    if command -v sudo > /dev/null; then
        usermod -aG sudo "$NEW_USER"
        if [ $? -ne 0 ]; then
            echo -e "${YELLOW}警告：授予sudo权限失败，您可以手动执行 'usermod -aG sudo $NEW_USER'${NC}"
        else
            echo -e "${GREEN}✓ 已授予sudo权限${NC}"
        fi
    else
        echo -e "${YELLOW}警告：系统未安装sudo，跳过sudo权限配置${NC}"
    fi
    
    # 为新用户生成SSH密钥
    echo -e "${YELLOW}正在为新用户生成SSH密钥...${NC}"
    # 使用-f选项强制生成，避免交互式提示
    su - "$NEW_USER" -c "mkdir -p ~/.ssh && chmod 700 ~/.ssh && ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N '' -q -f"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ 已为用户 $NEW_USER 生成SSH密钥${NC}"
        echo -e "${GREEN}私钥位置：/home/$NEW_USER/.ssh/id_rsa${NC}"
    else
        echo -e "${YELLOW}警告：为用户生成SSH密钥失败，您可以手动执行${NC}"
        echo -e "${YELLOW}su - $NEW_USER -c 'ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N '''${NC}"
    fi
    
    echo -e "${GREEN}✓ 用户 $NEW_USER 创建成功！${NC}"
    return 0
}

# 检查并提示创建普通用户
check_user() {
    echo -e "${BLUE}\n======================================${NC}"
    echo -e "${BLUE}步骤2：检查用户配置${NC}"
    echo -e "${BLUE}======================================${NC}"
    echo -e "${YELLOW}正在检查系统用户...${NC}"
    echo -e "${YELLOW}由于将禁止root直接登录，需要确保存在其他普通用户。${NC}"
    
    # 检查是否存在非root用户（UID >= 1000）
    NON_ROOT_USERS=$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd)
    
    if [ -z "$NON_ROOT_USERS" ]; then
        echo -e "${RED}⚠️  警告：系统中没有找到普通用户！${NC}"
        echo -e "${RED}禁止root登录后，您将无法登录服务器！${NC}"
        echo -e "${YELLOW}\n请手动创建普通用户，然后再次运行脚本。${NC}"
        echo -e "${YELLOW}手动创建步骤：${NC}"
        echo -e "${GREEN}1. 创建用户：useradd 用户名${NC}"
        echo -e "${GREEN}2. 设置密码：passwd 用户名${NC}"
        echo -e "${GREEN}3. 授予sudo权限：usermod -aG sudo 用户名${NC}"
        echo -e "${GREEN}4. 为新用户生成密钥：su - 用户名 -c 'ssh-keygen -t rsa -b 4096'${NC}"
        echo -e "${RED}\n脚本已终止，请创建普通用户后再运行。${NC}"
        exit 0
    else
        echo -e "${GREEN}✓ 检测到以下普通用户：${NC}"
        echo -e "${GREEN}$NON_ROOT_USERS${NC}"
        echo -e "${YELLOW}您可以使用这些用户登录服务器。${NC}"
    fi
}

# 备份原始配置
backup_config() {
    echo -e "${BLUE}\n======================================${NC}"
    echo -e "${BLUE}步骤4：备份配置${NC}"
    echo -e "${BLUE}======================================${NC}"
    echo -e "${YELLOW}正在备份原始SSH配置...${NC}"
    echo -e "${YELLOW}备份可以在配置出错时恢复，确保系统安全。${NC}"
    
    mkdir -p "$BACKUP_DIR"
    cp "$SSH_CONFIG" "$BACKUP_DIR/"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ 配置备份成功！${NC}"
        echo -e "${GREEN}备份文件位置：$BACKUP_DIR/sshd_config${NC}"
        echo -e "${YELLOW}如果配置出错，可以使用此备份文件恢复。${NC}"
    else
        echo -e "${RED}错误：配置备份失败！${NC}"
        echo -e "${RED}请检查目录权限后重试。${NC}"
        exit 1
    fi
}

# 生成SSH密钥对
generate_ssh_keys() {
    echo -e "${BLUE}\n======================================${NC}"
    echo -e "${BLUE}步骤5：生成SSH密钥对${NC}"
    echo -e "${BLUE}======================================${NC}"
    echo -e "${YELLOW}正在生成SSH密钥对...${NC}"
    echo -e "${YELLOW}SSH密钥对用于无密码登录，比密码更安全。${NC}"
    echo -e "${YELLOW}密钥对包含：${NC}"
    echo -e "${YELLOW}  - 私钥：保存在本地电脑，用于登录服务器${NC}"
    echo -e "${YELLOW}  - 公钥：保存在服务器，用于验证私钥${NC}"
    
    # 检查当前用户
    CURRENT_USER=$(who am i | awk '{print $1}')
    if [ -z "$CURRENT_USER" ]; then
        CURRENT_USER=$(logname 2>/dev/null || echo "root")
    fi
    
    echo -e "${GREEN}当前用户：$CURRENT_USER${NC}"
    
    # 设置密钥存储路径
    KEY_DIR="/home/$CURRENT_USER/.ssh"
    if [ "$CURRENT_USER" = "root" ]; then
        KEY_DIR="/root/.ssh"
    fi
    
    # 创建.ssh目录
    mkdir -p "$KEY_DIR" && chmod 700 "$KEY_DIR"
    
    # 检查密钥文件是否已存在
    if [ -f "$KEY_DIR/id_rsa" ]; then
        echo -e "${YELLOW}检测到密钥文件已存在：$KEY_DIR/id_rsa${NC}"
        
        # 检查是否为非交互式环境
        if is_non_interactive; then
            echo -e "${YELLOW}非交互式环境下，使用现有密钥。${NC}"
            # 确保authorized_keys文件存在且权限正确
            if [ ! -f "$KEY_DIR/authorized_keys" ]; then
                echo -e "${YELLOW}正在配置公钥登录...${NC}"
                cat "$KEY_DIR/id_rsa.pub" >> "$KEY_DIR/authorized_keys"
                chmod 600 "$KEY_DIR/authorized_keys"
                chown -R "$CURRENT_USER:$CURRENT_USER" "$KEY_DIR"
            fi
            return 0
        fi
        
        # 交互式环境下，询问用户
        read -p "是否覆盖现有密钥？(y/n)： " OVERWRITE
        if [[ "$OVERWRITE" == "y" || "$OVERWRITE" == "Y" ]]; then
            echo -e "${YELLOW}正在生成4096位RSA密钥对（覆盖现有密钥）...${NC}"
            # 使用-f选项强制覆盖
            ssh-keygen -t rsa -b 4096 -f "$KEY_DIR/id_rsa" -N "" -q -f
        else
            echo -e "${YELLOW}跳过密钥生成，使用现有密钥。${NC}"
            # 确保authorized_keys文件存在且权限正确
            if [ ! -f "$KEY_DIR/authorized_keys" ]; then
                echo -e "${YELLOW}正在配置公钥登录...${NC}"
                cat "$KEY_DIR/id_rsa.pub" >> "$KEY_DIR/authorized_keys"
                chmod 600 "$KEY_DIR/authorized_keys"
                chown -R "$CURRENT_USER:$CURRENT_USER" "$KEY_DIR"
            fi
            return 0
        fi
    else
        # 生成密钥对（无密码）
        echo -e "${YELLOW}正在生成4096位RSA密钥对...${NC}"
        ssh-keygen -t rsa -b 4096 -f "$KEY_DIR/id_rsa" -N "" -q
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ SSH密钥对生成成功！${NC}"
        echo -e "${GREEN}私钥位置：$KEY_DIR/id_rsa${NC}"
        echo -e "${RED}⚠️  重要：请将此私钥下载到本地电脑安全存储！${NC}"
        echo -e "${GREEN}公钥位置：$KEY_DIR/id_rsa.pub${NC}"
        
        # 将公钥添加到authorized_keys
        echo -e "${YELLOW}正在配置公钥登录...${NC}"
        # 先清空authorized_keys，避免重复添加
        > "$KEY_DIR/authorized_keys"
        cat "$KEY_DIR/id_rsa.pub" >> "$KEY_DIR/authorized_keys"
        chmod 600 "$KEY_DIR/authorized_keys"
        chown -R "$CURRENT_USER:$CURRENT_USER" "$KEY_DIR"
        
        echo -e "${GREEN}✓ 公钥已添加到authorized_keys，密钥登录已配置。${NC}"
    else
        echo -e "${RED}错误：SSH密钥对生成失败！${NC}"
        exit 1
    fi
}

# 修改SSH配置
configure_ssh() {
    echo -e "${BLUE}\n======================================${NC}"
    echo -e "${BLUE}步骤6：修改SSH配置${NC}"
    echo -e "${BLUE}======================================${NC}"
    echo -e "${YELLOW}正在配置SSH服务...${NC}"
    echo -e "${YELLOW}将修改以下安全配置：${NC}"
    echo -e "${YELLOW}  1. 端口：$SSH_PORT（原默认22）${NC}"
    echo -e "${YELLOW}  2. 禁止root直接登录${NC}"
    echo -e "${YELLOW}  3. 禁止密码登录${NC}"
    echo -e "${YELLOW}  4. 启用密钥登录${NC}"
    
    # 备份原始配置（再次备份，双重保险）
    cp "$SSH_CONFIG" "$SSH_CONFIG.bak"
    echo -e "${GREEN}✓ 已创建临时备份：$SSH_CONFIG.bak${NC}"
    
    # 配置项数组 - 使用用户选择的端口
    declare -A configs=(
        ["Port"]="$SSH_PORT"
        ["PermitRootLogin"]="no"
        ["PasswordAuthentication"]="no"
        ["PubkeyAuthentication"]="yes"
        ["ChallengeResponseAuthentication"]="no"
        ["UsePAM"]="yes"
        ["X11Forwarding"]="yes"
        ["PrintMotd"]="no"
        ["AcceptEnv"]="LANG LC_*"
        ["Subsystem"]="sftp  /usr/lib/openssh/sftp-server"
    )
    
    # 清空或注释掉现有配置项，然后添加新配置
    echo -e "${YELLOW}正在更新配置文件...${NC}"
    for key in "${!configs[@]}"; do
        # 注释掉现有配置
        sed -i "s/^$key/#$key/g" "$SSH_CONFIG"
        sed -i "s/^#\s*$key/#$key/g" "$SSH_CONFIG"
    done
    
    # 添加新配置
    echo "" >> "$SSH_CONFIG"
    echo "# 安全配置 - 由 secure_server.sh 脚本添加" >> "$SSH_CONFIG"
    for key in "${!configs[@]}"; do
        echo "$key ${configs[$key]}" >> "$SSH_CONFIG"
    done
    
    echo -e "${GREEN}✓ SSH配置修改完成！${NC}"
}

# 重启SSH服务
restart_ssh() {
    echo -e "${BLUE}\n======================================${NC}"
    echo -e "${BLUE}步骤7：重启SSH服务${NC}"
    echo -e "${BLUE}======================================${NC}"
    echo -e "${YELLOW}正在重启SSH服务...${NC}"
    echo -e "${YELLOW}重启服务才能使新配置生效。${NC}"
    echo -e "${YELLOW}重启过程中SSH连接可能会短暂中断。${NC}"
    
    # 检测系统类型并使用相应的命令重启SSH服务
    if command -v systemctl > /dev/null; then
        # Systemd 系统（Ubuntu 16.04+, CentOS 7+, Debian 8+）
        echo -e "${YELLOW}使用 systemctl 重启 sshd 服务...${NC}"
        systemctl restart sshd
    elif command -v service > /dev/null; then
        # SysVinit 系统
        echo -e "${YELLOW}使用 service 重启 ssh 服务...${NC}"
        service ssh restart || service sshd restart
    else
        echo -e "${RED}错误：无法检测到系统服务管理器！${NC}"
        echo -e "${RED}请手动重启SSH服务以应用新配置。${NC}"
        return 1
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ SSH服务重启成功！${NC}"
        return 0
    else
        echo -e "${RED}错误：SSH服务重启失败！${NC}"
        echo -e "${RED}请检查配置文件后手动重启。${NC}"
        return 1
    fi
}

# 显示配置结果
show_result() {
    echo -e "\n${GREEN}======================================${NC}"
    echo -e "${GREEN}🎉 服务器安全配置完成！${NC}"
    echo -e "${GREEN}======================================${NC}"
    
    echo -e "\n${BLUE}📋 配置详情：${NC}"
    echo -e "${GREEN}✓ SSH端口：$SSH_PORT${NC}"
    echo -e "${GREEN}✓ 禁止ROOT直接登录：是${NC}"
    echo -e "${GREEN}✓ 禁止密码登录：是${NC}"
    echo -e "${GREEN}✓ 启用密钥登录：是${NC}"
    
    # 显示连接信息
    CURRENT_USER=$(who am i | awk '{print $1}')
    if [ -z "$CURRENT_USER" ]; then
        CURRENT_USER=$(logname 2>/dev/null || echo "root")
    fi
    
    IP_ADDR=$(hostname -I | awk '{print $1}')
    
    echo -e "\n${BLUE}🔌 连接信息：${NC}"
    echo -e "${YELLOW}使用以下命令连接服务器：${NC}"
    echo -e "${GREEN}ssh -p $SSH_PORT $CURRENT_USER@$IP_ADDR${NC}"
    
    echo -e "\n${BLUE}🔑 私钥信息：${NC}"
    echo -e "${YELLOW}私钥位置：${NC}"
    echo -e "${GREEN}/home/$CURRENT_USER/.ssh/id_rsa${NC}"
    
    echo -e "\n${RED}⚠️  重要提示：${NC}"
    echo -e "${RED}1. 请立即将私钥下载到本地电脑安全存储！${NC}"
    echo -e "${RED}2. 请确保防火墙已开放 $SSH_PORT 端口！${NC}"
    echo -e "${RED}3. 建议在新窗口测试连接成功后，再关闭当前会话！${NC}"
    echo -e "${RED}4. 原始配置备份：$BACKUP_DIR/sshd_config${NC}"
    echo -e "${RED}5. 丢失私钥将无法登录服务器，请妥善保管！${NC}"
    
    echo -e "\n${BLUE}📚 后续操作建议：${NC}"
    echo -e "${YELLOW}1. 配置防火墙开放 $SSH_PORT 端口${NC}"
    echo -e "${YELLOW}2. 测试新连接是否正常${NC}"
    echo -e "${YELLOW}3. 定期更换SSH密钥（建议每3-6个月）${NC}"
    echo -e "${YELLOW}4. 考虑使用Fail2ban防止暴力破解${NC}"
    
    echo -e "\n${GREEN}======================================${NC}"
    echo -e "${GREEN}感谢使用本脚本！服务器安全性已提升。${NC}"
    echo -e "${GREEN}======================================${NC}"
}

# 主函数
main() {
    echo -e "${GREEN}======================================${NC}"
    echo -e "${GREEN}🎉 服务器SSH安全配置脚本 - 新手友好版${NC}"
    echo -e "${GREEN}======================================${NC}"
    echo -e "${YELLOW}本脚本将帮助您一键配置服务器SSH安全设置。${NC}"
    echo -e "${YELLOW}全程将有详细解释，无需担心操作失误。${NC}"
    echo -e "${YELLOW}预计耗时：约1分钟${NC}"
    
    # 检查root权限
    check_root
    
    # 检查并提示创建普通用户
    check_user
    
    # 交互式选择SSH端口
    select_ssh_port
    
    # 备份配置
    backup_config
    
    # 生成SSH密钥对
    generate_ssh_keys
    
    # 修改SSH配置
    configure_ssh
    
    # 重启SSH服务
    restart_ssh
    
    # 显示结果
    show_result
}

# 执行主函数
main