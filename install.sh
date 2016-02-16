#!/bin/sh

DIST=$(lsb_release -i -s)

case "${DIST}" in
    Ubuntu)
	;;
    *)
	echo "Unsupported dist: ${DIST}"
	exit
	;;
esac

apt-get update
apt-get install -y git automake autoconf r-base sysstat make gcc cmake ghostscript

cat <<EOF> /etc/cron.d/dht3-sysstat
PATH=/usr/lib/sysstat:/usr/sbin:/usr/sbin:/usr/bin:/sbin:/bin
* * * * * root command -v debian-sa1 > /dev/null && debian-sa1 1 1 && sleep 20 && debian-sa1 1 1 && sleep 20 && debian-sa1 1 1
EOF

sed 's/^ENABLED=.*/ENABLED="true"/g' -i /etc/default/sysstat

git clone git://git.code.sf.net/p/osdldbt/dbt3 /opt/osdldbt-dbt3
cd /opt/osdldbt-dbt3
./autogen.sh
./configure --with-mysql
make
make install

git clone https://github.com/mw2q/dbttools.git /opt/dbttools
cmake CMakeLists.txt
make install DESTDIR=/usr/local
