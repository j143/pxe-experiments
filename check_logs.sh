ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa alpine@192.168.100.2 "ls -l /usr/bin/sudo /usr/sbin/sudo /bin/sudo /sbin/sudo; echo PATH=\$PATH; apk info sudo"
