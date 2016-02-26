#!/bin/bash

cat ${2} | mysql -f ${1}
