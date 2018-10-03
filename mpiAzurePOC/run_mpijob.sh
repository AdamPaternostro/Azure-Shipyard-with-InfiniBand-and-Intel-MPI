#!/usr/bin/env bash

set -e
set -o pipefail

echo ""
echo "STEP 1 (Print parameters)"
echo "AZ_BATCH_HOST_LIST: $AZ_BATCH_HOST_LIST"
echo "DEBUG parameter 1 (num mpi processes): $1"
echo "DEBUG parameter 2 (C++ code):          $2"
echo "DEBUG parameter 3 (app_control):       $3"

# get number of nodes
echo ""
echo "STEP 2 (Parse the commands in AZ_BATCH_HOST_LIST) "
IFS=',' read -ra HOSTS <<< "$AZ_BATCH_HOST_LIST"

echo ""
echo "STEP 3 (Get the node count)"
nodes=${#HOSTS[@]}
echo "DEBUG nodes: $nodes"

echo ""
echo "STEP 4 (Calculation the number or processes)"
nprocs=$(($nodes * $1))
echo "DEBUG nprocs: $nprocs"

echo ""
echo "STEP 5 (Intel MPI Variables)"
source /opt/intel/compilers_and_libraries/linux/mpi/bin64/mpivars.sh       

echo ""
echo "STEP 6 (Run MPI)"
echo "mpirun -n $nprocs -ppn $1 -hosts $AZ_BATCH_HOST_LIST $2 $3"
mpirun -n $nprocs -ppn $1 -hosts $AZ_BATCH_HOST_LIST $2 $3
