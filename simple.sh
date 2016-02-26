#!/bin/bash

ROWS=100
PARALLEL=10
CHUNKS=$((${PARALLEL}*10))
PREPAREDSTATEMENTS=1 # 0 for off and above 0 for enabled
UPDATEROWS=100

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
mysql ${DB} -e "CREATE TABLE test_transaction (id INTEGER AUTO_INCREMENT PRIMARY KEY, val_integer INTEGER, val_varchar VARCHAR(100));"
mysql ${DB} -e "CREATE TABLE test_update (id INTEGER AUTO_INCREMENT PRIMARY KEY, val_integer INTEGER, val_varchar VARCHAR(100));"
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
	    echo "SET @a = '${TEXT}';"
	    echo "EXECUTE stmt1 USING @a;"
	else
	    echo "INSERT INTO test_varchar (val) VALUES ('${TEXT}');"
	fi
    } >> ${TMPVARCHAR}_$((${I}%${CHUNKS}))

    {
	echo "START TRANSACTION;";
	echo "SET @VAL_INTEGER = (SELECT val FROM test_integer as r1 JOIN (SELECT CEIL(RAND() * (SELECT MAX(id) FROM test_integer)) AS id) AS r2 WHERE r1.id > r2.id ORDER BY r1.id ASC LIMIT 1);"
	echo "SET @VAL_VARCHAR = (SELECT val FROM test_integer as r1 JOIN (SELECT CEIL(RAND() * (SELECT MAX(id) FROM test_integer)) AS id) AS r2 WHERE r1.id > r2.id ORDER BY r1.id ASC LIMIT 1);"
	echo "INSERT INTO test_transaction (val_integer,val_varchar) VALUES (@VAL_INTEGER,@VAL_VARCHAR);"
	echo "COMMIT;"
    } >> ${TMPTRANSACTION}_$((${I}%${CHUNKS}))

    {
	echo "START TRANSACTION;";
	echo "SET @RANDOM = (SELECT r1.id FROM test_update as r1 JOIN (SELECT CEIL(RAND() * (SELECT MAX(id) FROM test_update)) AS id) AS r2 WHERE r1.id > r2.id ORDER BY r1.id ASC LIMIT 1);"
	echo "SET @VAL_INTEGER = (SELECT val FROM test_integer as r1 JOIN (SELECT CEIL(RAND() * (SELECT MAX(id) FROM test_integer)) AS id) AS r2 WHERE r1.id > r2.id ORDER BY r1.id ASC LIMIT 1);"
	echo "SET @VAL_VARCHAR = (SELECT val FROM test_integer as r1 JOIN (SELECT CEIL(RAND() * (SELECT MAX(id) FROM test_integer)) AS id) AS r2 WHERE r1.id > r2.id ORDER BY r1.id ASC LIMIT 1);"
	echo "UPDATE test_update SET val_integer=@VAL_INTEGER,val_varchar=@VAL_VARCHAR WHERE id=@RANDOM;"
	echo "COMMIT;"
    } >> ${TMPUPDATE}_$((${I}%${CHUNKS}))
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

echo_ts "Performing transaction inserts..."
TRANSACTIONSTART=$(timestamp)
TRANSACTIONFAILS=$(ls -1 ${TMPTRANSACTION}_* | xargs -n 1 -P ${PARALLEL} ./mysql_file.sh ${DB} 2>&1 | wc -l)
TRANSACTIONEND=$(timestamp)
echo "done"

# manual copy of data to run updates against
mysql simple -e "INSERT INTO test_update SELECT * FROM test_transaction LIMIT ${UPDATEROWS};"

echo_ts "Performing transaction updates..."
UPDATESTART=$(timestamp)
UPDATEFAILS=$(ls -1 ${TMPUPDATE}_* | xargs -n 1 -P ${PARALLEL} ./mysql_file.sh ${DB} 2>&1 | wc -l)
UPDATEEND=$(timestamp)
echo "done"

echo
echo "Facts:"
echo "Number of rows inserted: ${ROWS}"
echo "Parallel inserts: ${PARALLEL}"
echo "Number of chunks: ${CHUNKS}"
echo "Rows updated: ${UPDATEROWS}"
echo -n "Using prepared statements: "
[[ ${PREPAREDSTATEMENTS} -ne 0 ]] && echo "true" || echo "false"
echo

INTEGERTIME=$(echo ${INTEGEREND}-${INTEGERSTART}|bc -l)
VARCHARTIME=$(echo ${VARCHAREND}-${VARCHARSTART}|bc -l)
TRANSACTIONTIME=$(echo ${TRANSACTIONEND}-${TRANSACTIONSTART}|bc -l)
UPDATETIME=$(echo ${UPDATEEND}-${UPDATESTART}|bc -l)

INTEGERQPS=$(echo ${ROWS}/${INTEGERTIME}+0.5|bc -l|bc)
VARCHARQPS=$(echo ${ROWS}/${VARCHARTIME}+0.5|bc -l|bc)
TRANSACTIONQPS=$(echo ${ROWS}/${TRANSACTIONTIME}+0.5|bc -l|bc)
UPDATEQPS=$(echo ${ROWS}/${UPDATETIME}+0.5|bc -l|bc)

printf "Integer inserts: %2.f sec (%2.f qps)\n" ${INTEGERTIME} ${INTEGERQPS}
printf "Varchar inserts: %2.f sec (%2.f qps)\n" ${VARCHARTIME} ${VARCHARQPS}
printf "Transaction inserts: %2.f sec (%2.f qps | %d failed transactions)\n" ${TRANSACTIONTIME} ${TRANSACTIONQPS} ${TRANSACTIONFAILS}
printf "Transaction updates: %2.f sec (%2.f qps | %d failed transactions)\n" ${UPDATETIME} ${UPDATEQPS} ${UPDATEFAILS}

rm -f ${TMP} ${TMPINTEGER}_* ${TMPVARCHAR}_* ${TMPTRANSACTION}_* ${TMPUPDATE}_* 
