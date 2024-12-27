#!/bin/bash
print_black() {
    echo -e "\033[30m$1\033[0m"
}

print_red() {
    echo -e "\033[31m$1\033[0m"
}

print_green() {
    echo -e "\033[32m$1\033[0m"
}

print_yellow() {
    echo -e "\033[33m$1\033[0m"
}

print_blue() {
    echo -e "\033[34m$1\033[0m"
}

print_magenta() {
    echo -e "\033[35m$1\033[0m"
}

print_cyan() {
    echo -e "\033[36m$1\033[0m"
}

print_grey() {
    echo -e "\033[37m$1\033[0m"
}

print_white() {
    echo "$1"
}

has_cpu_flags() {
    local flag

    local flags=$(cat /proc/cpuinfo | grep flags | head -n 1 | awk -F ':' '{print $2}')
    [ -z "$flags" ] && flags=$(cat /proc/cpuinfo | grep Features | head -n 1 | awk -F ':' '{print $2}') # ARM64

    for flag; do
        case " ${flags} " in
        *" ${flag} "*)
            :
            ;;
        *)
            return 1
            ;;
        esac
    done
}

check_amd64_version() {
    arch="amd64v1"

    ## x86-64-v2
    has_cpu_flags cx16 lahf_lm popcnt sse4_1 sse4_2 ssse3 || return 0
    arch="amd64v2"

    ## x86-64-v3
    has_cpu_flags avx avx2 bmi1 bmi2 f16c fma abm movbe xsave || return 0
    arch="amd64v3"

    ## x86-64-v4
    has_cpu_flags avx512f avx512bw avx512cd avx512dq avx512vl || return 0
    arch="amd64v4"
}

clear
PROGRAM="PortForwardGo"

mirror="https://pkg.zeroteam.top"
service="$PROGRAM"
offline=0

print_cyan "$PROGRAM installation script"

# Read parameters
{
    # Parse parameters
    while [ $# -gt 0 ]; do
        case $1 in
        --api)
            api=$2
            shift
            ;;
        --secret)
            secret=$2
            shift
            ;;
        --license)
            license=$2
            shift
            ;;
        --service)
            service=$2
            shift
            ;;
        --proxy)
            proxy=$2
            shift
            ;;
        --listen)
            listen=$2
            shift
            ;;
        --mirror)
            mirror=$2
            shift
            ;;
        --region)
            region=$2
            shift
            ;;
        --version)
            version=$2
            shift
            ;;
        --offline)
            offline=1
            ;;
        *)
            print_red " Unknown parameter: $1"
            exit 2
            ;;
        esac
        shift
    done

    # Apply region profile
    if [ ! -z "$region" ]; then
        case "$region" in
        CN)
            print_yellow " Current region profile: China Mainland (CN)"

            [ -z "$license" ] && proxy="internal+panel"
            listen="auto"
            ;;
        IR)
            print_yellow " Current region profile: Iran (IR)"

            [ -z "$license" ] && proxy="panel"
            listen="auto"
            ;;
        *)
            print_yellow " Current region profile '$region' not found, using default profile..."
            ;;
        esac
    fi

    # Check parameters validity
    {
        if [ -z "$api" ]; then
            print_red " Parameter 'api' not found"
            exit 2
        fi

        if [ -z "$secret" ]; then
            print_red " Parameter 'secret' not found"
            exit 2
        fi

        if [ -z "$service" ]; then
            print_red " Parameter 'service' not found"
            exit 2
        fi

        if [ -z "$mirror" ]; then
            print_red " Parameter 'mirror' not found"
            exit 2
        fi
    }
}

# Check system
{
    print_yellow " ** Checking system info..."

    # Check architecture
    case $(uname -m) in
    x86)
        arch="386"
        ;;
    i386)
        arch="386"
        ;;
    x86_64)
        check_amd64_version
        ;;
    armv7*)
        arch="armv7"
        ;;
    aarch64)
        arch="arm64"
        ;;
    s390x)
        arch="s390x"
        ;;
    *)
        print_red " Unsupported architecture"
        exit 1
        ;;
    esac

    # Check systemd
    command -V systemctl >/dev/null
    if [ "$?" -ne 0 ]; then
        print_red "Not found systemd"
        exit 1
    fi

    # Check aes hardware acceleration
    has_cpu_flags aes
    if [ "$?" -ne 0 ]; then
        print_magenta " Warning: Host's CPU does not have aes hardware acceleration! Please use the 'SecureX' protocol to improve performance"
    fi

    # Check network config
    if [ "$listen" == "auto" ]; then
        listen=""

        default_out_ip=$(curl -4sL --connect-timeout 5 myip.ipip.net | awk '{print $2}' | awk -F ： '{print $2}')
        default_in_ip="$default_out_ip"

        bind_ips=$(ip address show | grep inet | grep -v inet6 | grep -v host | grep -v docker | grep -v tun | grep -v tap | awk '{print $2}' | awk -F "/" '{print $1}')
        for bind_ip in ${bind_ips[@]}; do
            out_ip=$(curl -4sL --connect-timeout 5 --interface $bind_ip myip.ipip.net | awk '{print $2}' | awk -F ： '{print $2}')
            if [ -z "$out_ip" ]; then
                continue
            fi

            print_cyan " Network card binding IP '$bind_ip' => Public IP '$out_ip'"

            if [ "$out_ip" != "$default_out_ip" ]; then
                default_in_ip="$out_ip"
                listen="$bind_ip"
            fi
        done

        print_white ""

        if [ -z "$listen" ]; then
            print_green " The inbound IP was not obtained. It may be a single ip machine."
            print_green " Public IP '$default_out_ip'"
        else
            print_green " Inbound: Network card binding IP '$listen' => Public IP '$default_in_ip'"
            print_green " Outbound: Public IP '$default_out_ip'"
        fi
    fi

    # Check installed
    while [ -f "/etc/systemd/system/$service.service" ] || [ -d "/opt/$service" ] || [ "$service" == "all" ]; do
        read -ep " Service '$service' exists or invalid, please enter a new service name: " service
    done
}

# Install program
{
    # Prepare program package
    if [ $offline -eq 0 ]; then
        # Get latest release version
        {
            print_yellow " ** Checking release info..."

            if [ -z "$version" ]; then
                if [ -z "$license" ]; then
                    version=$(curl -sL "$mirror/PortForwardGo/latest_version")
                    if [ -z "$version" ]; then
                        print_red "Unable to get releases info"
                        exit 1
                    fi

                    print_white " Detected lastet verion: $version"
                else
                    version="1.2.0"

                    print_white " Detected lastet verion: $version"
                fi
            else
                print_white " Use the specified verion: $version"
            fi
        }

        # Download release
        {
            print_yellow " ** Downloading release..."

            curl -L -o /tmp/$PROGRAM.tar.gz "$mirror/PortForwardGo/$version/${PROGRAM}_${version}_linux_${arch}.tar.gz"
            if [ $? -ne 0 ] || [ ! -f "/tmp/$PROGRAM.tar.gz" ]; then
                print_red "Download failed"
                exit 1
            fi
        }
    else
        print_yellow " ** Offline installation..."

        [ -z "$version" ] && version="1.0.0"

        print_white " Please download backend package, rename it to '$PROGRAM.tar.gz' and upload it to /tmp"
        print_white " If you selected version '$version', please open '$mirror/PortForwardGo/$version/${PROGRAM}_${version}_linux_${arch}.tar.gz' in your browser. Replace the version by yourself!"
        print_white ""

        read -ep " Press [Enter] to continue installation..."
        while [ ! -f "/tmp/$PROGRAM.tar.gz" ]; do
            print_red " File not exists!"
            print_white " Please upload '$PROGRAM.tar.gz' to /tmp"

            read -ep " Press [Enter] to continue installation..."
        done
    fi

    # Decompress package
    {
        TMP_DIR=$(mktemp -d)
        if [ -z "$TMP_DIR" ]; then
            TMP_DIR="/tmp/$PROGRAM"
            mkdir -p $TMP_DIR
        fi

        tar -xzf /tmp/$PROGRAM.tar.gz -C $TMP_DIR
        if [ $? -ne 0 ] || [ ! -f "$TMP_DIR/$PROGRAM" ] || [ ! -f "$TMP_DIR/systemd/$PROGRAM.service" ]; then
            print_red "Decompression failed"

            rm -rf $TMP_DIR
            exit 1
        fi

        mkdir -p /opt/$service

        cp -f $TMP_DIR/$PROGRAM /opt/$service/$PROGRAM
        [ -f "$TMP_DIR/examples/backend.json" ] && cp -f $TMP_DIR/examples/backend.json /opt/$service/config.json
        [ -f "$TMP_DIR/examples/$PROGRAM/template.json" ] && cp -f $TMP_DIR/examples/$PROGRAM/template.json /opt/$service/config.json

        rm -f /tmp/$PROGRAM.tar.gz
        rm -rf $TMP_DIR
    }

    # Configure program
    {
        chmod +x /opt/$service/$PROGRAM

        sed -i "s#{api}#$api#g" /opt/$service/config.json
        sed -i "s#{secret}#$secret#g" /opt/$service/config.json
        sed -i "s#{license}#$license#g" /opt/$service/config.json
        sed -i "s#{proxy}#$proxy#g" /opt/$service/config.json
        sed -i "s#{listen}#$listen#g" /opt/$service/config.json
    }

    # Add system service
    {
        cat >/etc/systemd/system/$service.service <<EOF
[Unit]
Description=PortForwardGo Backend Service For $api
Documentation=https://docs.zeroteam.top/pfgo/backend/
After=network.target

[Service]
Type=simple
User=root
Restart=always
RestartSec=20s
TasksMax=infinity
LimitCPU=infinity
LimitFSIZE=infinity
LimitDATA=infinity
LimitSTACK=infinity
LimitCORE=infinity
LimitRSS=infinity
LimitNOFILE=infinity
LimitAS=infinity
LimitNPROC=infinity
LimitSIGPENDING=infinity
LimitMSGQUEUE=infinity
LimitRTTIME=infinity
WorkingDirectory=/opt/$service
ExecStart=/opt/$service/PortForwardGo --config config.json --log run.log

[Install]
WantedBy=multi-user.target
EOF
    }
}

# Finish installation
{
    print_yellow " ** Starting program..."

    systemctl daemon-reload
    systemctl enable --now $service
}

print_green "$PROGRAM installed successfully"
