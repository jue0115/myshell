#!/bin/bash

#========================================================
#open ssh
#========================================================
sed 's/#PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config -i
sed 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config -i
sed 's/#PasswordAuthentication yes/PasswordAuthentication yes/g' /etc/ssh/sshd_config -i
sed 's/#PermitEmptyPasswords no/PermitRootLogin yes/g' /etc/ssh/sshd_config -i
sed 's/PermitRootLogin no/PermitRootLogin yes/g' /etc/ssh/sshd_config -i
sudo systemctl restart sshd
