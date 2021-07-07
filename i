#!/usr/bin/env bash
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
# Credit
echo -e "欢迎使用Lee的一键v2-ui + v2ray  WebSocket + TLS脚本"
echo -e "请确保是在全新安装的系统中运行"
echo -e "否则可能会破坏原有的文件和资料"
echo -e "使用教程：https://v.lee.ac/t"+
echo -e "按Ctrl+C退出，按回车开始..."
read
# Check Environment
if cat /etc/issue | grep -Eqi "debian"; then
    release=1
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release=1
elif cat /proc/version | grep -Eqi "debian"; then
    release=1
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release=1
elif [[ -f /etc/redhat-release ]]; then
    release=2
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release=2
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release=2
fi
if [ ! $release ]; then
    echo -e "${red}请在Debian/Ubuntu/CentOS/RHEL系统上运行此脚本！${plain}"
    exit 1
fi
# Check root
if test $(whoami) != "root"; then
    echo -e "${red}请用root用户运行此脚本！${plain}"
    echo -e "提示：运行${yellow}sudo su${plain}再运行本脚本试试?"
    exit 1
fi
# Preparation
echo -e "${yellow}如果输错了请按Ctrl+C退出脚本后重新运行${plain}"
echo '输入解析到这台机器的域名（不含http://）：'
read domain
echo '输入你的邮箱地址（用于接收certbot证书续期信息）：'
read user_mail
cd /root/
if [[ $release == 1 ]]; then
    apt update
    apt install -y wget curl screen vim lrzsz zip unzip nginx snapd tar
elif [[ $release == 2 ]]; then
    yum install -y epel-release
    yum install -y wget curl screen vim lrzsz zip unzip tar htop snapd nginx
    systemctl enable --now snapd.socket
    ln -s /var/lib/snapd/snap /snap
fi
snap install core
snap refresh core
snap install --classic certbot
ln -s /snap/bin/certbot /usr/bin/certbot
# Download Assets
echo '下载配置文件&实用工具中...'
mkdir scripts
cd scripts/
wget https://v.lee.ac/install/assets.zip -O assets.zip
unzip assets.zip
rm -f assets.zip
chmod 755 *.sh besttrace nf speedtest/speedtest
mv v2ray.conf /etc/nginx/conf.d/
mkdir -p /etc/v2-ui/
mv v2-ui.db /etc/v2-ui/
cd /root/
# BBR
if [[ $release == 1 ]]; then
    echo '开启BBR中...'
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    echo "net.core.default_qdisc = fq" >>/etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >>/etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
fi
# Nginx
echo '配置nginx中...'
if [[ $release == 1 ]]; then
    rm -f /etc/nginx/sites-enabled/default
elif [[ $release == 2 ]]; then
    sed -i "38,57d" /etc/nginx/nginx.conf
fi
mkdir /www/
if [ ! -f /www/index.html ]; then
echo '<h1><a href="/v2-ui">v2-ui</a></h1>' >/www/index.html
fi
sed -i "s/your_domain/$domain/g" /etc/nginx/conf.d/v2ray.conf
if [[ $release == 1 ]]; then
    nginx -s reload
elif [[ $release == 2 ]]; then
    systemctl start nginx

    firewall-cmd -V
    if [[ $? == 0 ]]; then
        echo -e "正在添加firewalld规则"
        firewall-cmd --add-service=http
        firewall-cmd --add-service=https
        firewall-cmd --runtime-to-permanent
    else
        iptables -V
        if [[ $? == 0 ]]; then
            echo -e "正在添加iptables规则"
            iptables -I INPUT -p tcp -m tcp --dport 80 -j ACCEPT
            iptables -I INPUT -p tcp -m tcp --dport 443 -j ACCEPT
        fi
    fi
fi
# Certbot
echo '配置certbot中...'
certbot --nginx -n --email $user_mail --agree-tos -d $domain
if [[ $? -ne 0 ]]; then
    certbot_failed=true
else
    sed -i '29,40d' /etc/nginx/conf.d/v2ray.conf
fi
if [[ $release == 1 || $release == 2 ]]; then
    sed -i '21a     listen 80;' /etc/nginx/conf.d/v2ray.conf
fi
# v2-ui
echo '安装v2-ui面板中...'
echo -e "感谢sprov大大的v2-ui面板，项目地址：https://github.com/sprov065/v2-ui"
cd /usr/local/
last_version=`curl -Ls "https://api.github.com/repos/sprov065/v2-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'`
if [[ ! -n "$last_version" ]]; then
    echo -e "${red}检测 v2-ui 版本失败，可能是超出 Github API 限制，请稍后再试，或手动指定 v2-ui 版本安装${plain}"
    exit 1
fi
echo -e "检测到 v2-ui 最新版本：${last_version}，开始安装"
wget -N --no-check-certificate -O /usr/local/v2-ui-linux.tar.gz https://github.com/sprov065/v2-ui/releases/download/${last_version}/v2-ui-linux-amd64.tar.gz
if [[ $? -ne 0 ]]; then
    echo -e "${red}下载 v2-ui 失败，请确保你的服务器能够下载 Github 的文件${plain}"
    exit 1
fi
tar zxf v2-ui-linux.tar.gz
rm -f v2-ui-linux.tar.gz
cd v2-ui/
chmod +x v2-ui bin/xray-v2-ui
cp -f v2-ui.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable v2-ui
systemctl restart v2-ui
curl -o /usr/bin/v2-ui -Ls https://raw.githubusercontent.com/sprov065/v2-ui/master/v2-ui.sh
chmod +x /usr/bin/v2-ui
echo -e "${green}v2-ui安装成功！${plain}"
echo -e "用户名和密码默认都是 ${green}admin${plain}，请在安装后尽快修改"
echo -e "浏览器打开${yellow}https://${domain}/v2-ui${plain}进入管理页面"
echo -e "注：默认nginx监听443端口并转发至v2ray监听的10000端口"
echo -e "请从v2-ui复制链接并导入客户端之后"
echo -e "${yellow}在客户端手动将端口改为443并开启tls选项${plain}"
echo -e "来开启TLS${yellow}确保服务器不会被墙${plain}"
echo -e "输入v2-ui进入v2-ui管理脚本"
if [[ $release == 2 ]]; then
    echo -e "检测到系统为CentOS，请输入v2-ui自行安装BBR"
fi
if [[ $certbot_failed ]]; then
    echo -e "${red}检测到certbot安装失败，请自行设置SSL/TLS证书${plain}"
fi
echo -e "若安装失败/无法使用请联系作者并附上详细信息，邮箱：0@l-ee.cn"
cd /root/
