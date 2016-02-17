#!/bin/bash

ROWS=100
PARALLEL=10
CHUNKS=$((${PARALLEL}*10))
PREPAREDSTATEMENTS=1 # 0 for off and above 0 for enabled

DB=simple

RANDOM=$$ # Seed random generator with current PID
TMP=$(mktemp)
TMPINTEGER="${TMP}_INTEGER"
TMPVARCHAR="${TMP}_VARCHAR"

function echo_ts () {
    echo -n "[$(date)] ${*}"
}

echo_ts "Removing old database..."
mysql -e "DROP DATABASE IF EXISTS ${DB}"
echo "done"

echo_ts "Creating new database"
mysql -e "CREATE DATABASE ${DB}"
echo "done"

echo_ts "Creating tables..."
mysql ${DB} -e "CREATE TABLE test_integer (id INTEGER AUTO_INCREMENT PRIMARY KEY, val INTEGER);"
mysql ${DB} -e "CREATE TABLE test_varchar (id INTEGER AUTO_INCREMENT PRIMARY KEY, val VARCHAR(100));"
echo "done"

if [ ${PREPAREDSTATEMENTS} -ne 0 ]; then
    echo_ts "Generating prepared statements..."
    for I in $(seq 0 $((${CHUNKS}-1))); do
	echo "PREPARE stmt1 FROM 'INSERT INTO test_integer (val) VALUES (?);';" > ${TMPINTEGER}_${I}
	echo "PREPARE stmt1 FROM 'INSERT INTO test_varchar (val) VALUES (?);';" > ${TMPVARCHAR}_${I}
    done
    echo "done"
fi

echo_ts "Generating test data..."
for I in $(seq 1 ${ROWS}); do
    TEXT=$(pwgen -n $((${RANDOM}%100)) -c 1)
    {
	if [ ${PREPAREDSTATEMENTS} -ne 0 ]; then
	    echo "SET @a = ${RANDOM};"
	    echo "EXECUTE stmt1 USING @a;"
	else
	    echo "INSERT INTO test_integer (val) VALUES ('${RANDOM}');"
	fi
    } >> ${TMPINTEGER}_$((${I}%${CHUNKS}))
    
    {
	if [ ${PREPAREDSTATEMENTS} -ne 0 ]; then
	    echo "SET @a = ${TEXT};"
	    echo "EXECUTE stmt1 USING '@a';"
	else
	    echo "INSERT INTO test_varchar (val) VALUES ('${TEXT}');"
	fi
    } >> ${TMPVARCHAR}_$((${I}%${CHUNKS}))
done
echo "done"

function timestamp () {
    date +%s.%N
}

echo_ts "Performing integer inserts..."
INTEGERSTART=$(timestamp)
ls -1 ${TMPINTEGER}_* | xargs -n 1 -P ${PARALLEL} ./mysql_file.sh ${DB}
INTEGEREND=$(timestamp)
echo "done"

echo_ts "Performing varchar inserts..."
VARCHARSTART=$(timestamp)
ls -1 ${TMPVARCHAR}_* | xargs -n 1 -P ${PARALLEL} ./mysql_file.sh ${DB}
VARCHAREND=$(timestamp)
echo "done"

echo
echo "Facts:"
echo "Number of rows inserted: ${ROWS}"
echo "Parallel inserts: ${PARALLEL}"
echo "Number of chunks: ${CHUNKS}"
echo
INTEGERTIME=$(echo ${INTEGEREND}-${INTEGERSTART}|bc -l)
VARCHARTIME=$(echo ${VARCHAREND}-${VARCHARSTART}|bc -l)

INTEGERQPS=$(echo ${ROWS}/${INTEGERTIME}+0.5|bc -l|bc)
VARCHARQPS=$(echo ${ROWS}/${VARCHARTIME}+0.5|bc -l|bc)

printf "Integer inserts: %2.f sec (%2.f qps)\n" ${INTEGERTIME} ${INTEGERQPS}
printf "Varchar inserts: %2.f sec (%2.f qps)\n" ${VARCHARTIME} ${VARCHARQPS}

rm -f ${TMP} ${TMPINTEGER}_* ${TMPVARCHAR}_*
