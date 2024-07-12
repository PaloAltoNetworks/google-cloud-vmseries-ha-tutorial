#! /bin/bash
echo "while :" >> /network-check.sh
echo "do" >> /network-check.sh
echo "  timeout -k 2 2 ping -c 1  8.8.8.8 >> /dev/null" >> /network-check.sh
echo "  if [ $? -eq 0 ]; then" >> /network-check.sh
echo "    echo \$(date) -- Online -- Source IP = \$(curl https://checkip.amazonaws.com -s --connect-timeout 1)" >> /network-check.sh
echo "  else" >> /network-check.sh
echo "    echo \$(date) -- Offline" >> /network-check.sh
echo "  fi" >> /network-check.sh
echo "  sleep 1" >> /network-check.sh
echo "done" >> /network-check.sh
chmod +x /network-check.sh

while ! ping -q -c 1 -W 1 google.com >/dev/null
do
  echo "waiting for internet connection..."
  sleep 10s
done
echo "internet connection available!"
sudo apt-get install php -y
sudo rm -f /var/www/html/index.html
sudo wget -O /var/www/html/index.php https://raw.githubusercontent.com/PaloAltoNetworks/google-cloud-vmseries-ha-tutorial/main/scripts/showheaders.php
sudo systemctl restart apache2