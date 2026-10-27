#!/bin/bash
# Run after the cluster starts. Both partitions use this shared job limit.
set -euo pipefail

docker compose exec -T slurmctld bash -s <<'SLURM'
set -euo pipefail
if ! /usr/bin/sacctmgr -nP show cluster format=Cluster | grep -Fxq linux; then
    /usr/bin/sacctmgr --immediate add cluster name=linux
fi
if ! /usr/bin/sacctmgr -nP show qos format=Name | grep -Fxq local_serial; then
    /usr/bin/sacctmgr --immediate add qos local_serial
fi
/usr/bin/sacctmgr --immediate modify qos where name=local_serial set GrpJobs=1
SLURM

docker compose restart slurmdbd slurmctld
