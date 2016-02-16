#!/bin/bash

if [[ ${1} =~ ^-?[0-9]+$ ]]; then
	FACTOR=${1}
else
	FACTOR=1
fi

# DYNAMICS
export DSS_RESULTS=/tmp/results-${FACTOR}/
export DSS_PATH=/tmp/dss_path/

# STATICS
export DSS_QUERY=/opt/osdldbt-dbt3/queries/mysql/
export DSS_CONFIG=/opt/osdldbt-dbt3/src/dbgen/
export DBNAME=dbt3
export MYDATA=/var/lib/mysql/

# CLEANUP FROM LAST RUN
rm -rf ${DSS_PATH} ${DSS_RESULTS}

# fixes???
export DBGEN=/usr/local/bin/dbgen
export QGEN=/usr/local/bin/qgen
mkdir ${DSS_PATH} -p

# MAKE SURE THAT WE DON'T RUN mysql_install_db
mkdir -p $MYDATA/mysql
touch $MYDATA/mysql/user.frm

# doc/dbt3-user-guide.txt
echo 0 > /proc/sys/kernel/kptr_restrict
echo -1 > /proc/sys/kernel/perf_event_paranoid

# RUN THE TEST
dbt3-run-workload -a mysql -f ${FACTOR} -o ${DSS_RESULTS}

