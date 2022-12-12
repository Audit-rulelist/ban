#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

arch=$(arch)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
  arch="amd64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
  arch="arm64"
else
  arch="amd64"
  echo -e "${red}检测架构失败，使用默认架构: ${arch}${plain}"
fi

echo "架构: ${arch}"

if [ $(getconf WORD_BIT) != '32' ] && [ $(getconf LONG_BIT) != '64' ] ; then
    echo "本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)，如果检测有误，请联系作者"
    exit 1
fi

os_version=""

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
    fi
fi

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install wget curl tar -y
    else
        apt install wget curl tar -y
    fi
}

install_pass_server() {
    name="pass-server"
    is_new=0
    license=""
    domain=""
    port=""
    autoTls="true"

    tar_file="${name}-linux-${arch}.tar.gz"
    if [[ ! -f ${tar_file} ]]
    then
        echo -e "本目录下安装文件 ${red}${tar_file}${plain} 不存在"
        exit 1
    fi

    if [[ ! -f /etc/pass-server/pass-server.db ]]
    then
        is_new=1
        echo && echo -n -e "全新安装，请先准备好一个面板使用的域名，输入回车开始填写相关信息: " && read ready

        echo && echo -n -e "输入面板域名(例如: aaa.domain.com): " && read domain
        if [[ -z "${domain}" ]]; then
            echo -e "${yellow}已取消${plain}"
            exit 0
        fi
        echo ""
        echo -e "若开启，需注意以下事项:"
        echo -e "1. 面板将监听 443 端口，需${yellow}确保 443 端口没有其他程序使用${plain}，并${yellow}确保防火墙已放行 443 端口${plain}"
        echo -e "2. 将自动申请并自动续期 https 证书，确保域名 ${green}${domain}${plain} 已解析到此服务器的 ip（若刚解析，则等待十分钟使其完全生效），${red}申请证书时不能开启 cdn${plain}"
        echo -e "3. 正常启动后会自动申请证书，如果数分钟后仍无法访问面板，请检查上述事项是否正常"
        echo && echo -n -e "是否开启面板自动 https [y/n，默认y]: " && read autoTls
        if [[ -z "${autoTls}" ]]; then
            autoTls="true"
        elif [[ "${autoTls}" == "y" || "${autoTls}" == "Y" ]]; then
            autoTls="true"
        else
            autoTls="false"
        fi

        if [[ "${autoTls}" == "true" ]]; then
            port="443"
            address="https://${domain}/"
            echo && echo -e "${red}注意：若当前已经绑定对接地址了，请确保以下地址为绑定的对接地址，否则会无法启动面板，第一次绑定请忽略这条${plain}"
            echo && echo -n -e "授权码绑定的面板地址为 ${green}https://${domain}/${plain}，按回车确认: " && read temp
        else
            echo && echo -n -e "输入面板监听端口: " && read port
            if [[ -z "${port}" ]]; then
                echo -e "${yellow}已取消${plain}"
                exit 0
            fi
            echo && echo -e "注意事项:"
            echo -e "1. 如果不配置 https，则直接绑定默认的地址: ${green}http://${domain}:${port}/${plain}"
            echo -e "2. 如果你自己配置 https 访问，则输入 ${green}https://${domain}:${port}/${plain}，稍后你需要进入面板设置 https 证书才可正常对接客户端"
            echo -e "3. 最重要的一点: ${red}你必须要保证这个对接地址能正常访问面板，否则将无法正常对接客户端${plain}"
            echo -e "4. ${red}重要${plain}：若当前已经绑定对接地址了，则必须输入当前绑定的地址，否则无法启动，第一次绑定请忽略这条"
            echo && echo -n -e "输入绑定的对接地址(默认 http://${domain}:${port}/): " && read address
            if [[ -z "${address}" ]]; then
                address="http://${domain}:${port}/"
            elif [[ ${address} != http://* && ${address} != https://* ]]; then
                echo -e "对接地址是一个完整的 url 地址，需要以 http:// 或 https:// 开头"
                exit 1
            fi
        fi

        echo && echo -n -e "输入授权码: " && read license
        if [[ -z "${license}" ]]; then
            echo -e "${yellow}已取消${plain}"
            exit 0
        fi
    fi

    systemctl stop ${name}

    mv ${tar_file} /usr/local/
    cd /usr/local/

    rm -rf ${name}

    tar zxvf ${tar_file}
    rm -f ${tar_file}

    cd ${name}

    if [[ "${is_new}" == "1" ]]
    then
        ./pass-server setting -license ${license} -autoTls ${autoTls} -panelDomain ${domain} -domain ${address} -port ${port}
    fi

    cp -f ${name}.service /etc/systemd/system/

    rm -f /usr/bin/${name}
    mv ${name}.sh /usr/bin/${name}
    chmod +x /usr/bin/${name}

    systemctl daemon-reload
    systemctl enable ${name}
    systemctl restart ${name}

    version=$(./pass-server -v)

    echo -e ""
    echo -e "pass-server v${version} ${green}安装完成${plain}"
    if [[ "${is_new}" == "1" ]]
    then
        if [[ "${autoTls}" == "true" ]]; then
            echo -e "面板访问地址: ${green}https://${domain}/${plain}"
        else
            echo -e "面板访问地址: ${green}http://${domain}:${port}/${plain}"
        fi
        echo -e "面板用户名: admin"
        echo -e "面板密码: admin"
    fi
    echo -e ""
    echo "pass-server 命令使用方法"
    echo "------------------------------------------"
    echo "pass-server              - 显示管理菜单 (功能更多)"
    echo "pass-server start        - 启动 pass-server 面板"
    echo "pass-server stop         - 停止 pass-server 面板"
    echo "pass-server restart      - 重启 pass-server 面板"
    echo "pass-server version      - 查看 pass-server 版本"
    echo "pass-server status       - 查看 pass-server 状态"
    echo "pass-server enable       - 设置 pass-server 开机自启"
    echo "pass-server disable      - 取消 pass-server 开机自启"
    echo "pass-server log          - 查看 pass-server 日志"
    echo "pass-server uninstall    - 卸载 pass-server 面板"
    echo "------------------------------------------"
}

echo -e "${green}开始安装${plain}"
install_base
install_pass_server
