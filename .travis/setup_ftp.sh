#! /bin/bash

sudo apt-get update -qq
sudo apt-get install -yqq bc pure-ftpd

sudo groupadd ftp
sudo useradd -s /bin/false -d /home/ftp -m -c "ftp test user" -g ftp ftp

(echo "123456"; echo "123456") | sudo pure-pw useradd moteus -u ftp -d /home/ftp
sudo pure-pw mkdb

echo "no" | sudo tee /etc/pure-ftpd/conf/AutoRename
cat /etc/pure-ftpd/conf/AutoRename

sudo /etc/init.d/pure-ftpd stop
sudo /usr/sbin/pure-ftpd -jl puredb:/etc/pure-ftpd/pureftpd.pdb &

cd $TRAVIS_BUILD_DIR

