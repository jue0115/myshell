#!/bin/bash
bit=`uname -m`

function speedtest() {
	if [[ ${bit} == "x86_64" ]]; then
      wget -O speedtest https://raw.githubusercontent.com/jue0115/CFWarp-Pro/main/speedtest_amd64 && chmod +x speedtest && ./speedtest
	elif [[ ${bit} == "aarch64" ]]; then
      wget -O speedtest https://raw.githubusercontent.com/jue0115/CFWarp-Pro/main/speedtest_arm64 && chmod +x speedtest && ./speedtest
	fi
}

speedtest