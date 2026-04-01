#!/bin/bash
set -e

if [ "$1" = "slurmdbd" ]
then
    echo "---> Starting the MUNGE Authentication service (munged) ..."
    gosu munge /usr/sbin/munged

    echo "---> Starting the Slurm Database Daemon (slurmdbd) ..."

    {
        . /etc/slurm/slurmdbd.conf
        until echo "SELECT 1" | mysql -h $StorageHost -u$StorageUser -p$StoragePass 2>&1 > /dev/null
        do
            echo "-- Waiting for database to become active ..."
            sleep 2
        done
    }
    echo "-- Database is now active ..."

    exec gosu slurm /usr/sbin/slurmdbd -Dvvv
fi

if [ "$1" = "slurmctld" ]
then
    echo "---> Starting the MUNGE Authentication service (munged) ..."
    gosu munge /usr/sbin/munged

    echo "---> Starting SSH Daemon (sshd) ..."
    # exec /usr/bin/ssh-keygen -A
    exec /usr/sbin/sshd -D &
    exec rm /run/nologin &
    exec chmod 777 /data &

    echo "---> Waiting for slurmdbd to become active before starting slurmctld ..."

    until 2>/dev/null >/dev/tcp/slurmdbd/6819
    do
        echo "-- slurmdbd is not available.  Sleeping ..."
        sleep 2
    done
    echo "-- slurmdbd is now active ..."

    echo "---> Starting the Slurm Controller Daemon (slurmctld) ..."
    if /usr/sbin/slurmctld -V | grep -q '17.02' ; then
        exec gosu slurm /usr/sbin/slurmctld -Dvvv
    else
        exec gosu slurm /usr/sbin/slurmctld -i -Dvvv
    fi
fi

if [ "$1" = "slurmd" ]
then
    echo "---> Starting the MUNGE Authentication service (munged) ..."
    gosu munge /usr/sbin/munged

    # Configure Apptainer for WSL2 GPU support:
    # On WSL2, the standard libcuda.so from the CUDA base image does not work
    # (it needs /dev/nvidia0 which doesn't exist). Override it with the WSL2-
    # compatible libcuda.so that uses /dev/dxg instead.
    # We add a bind path in apptainer.conf so it applies to ALL Singularity
    # runs, even when BIOMERO regenerates job scripts.
    WSL2_LIBCUDA="/usr/lib/wsl/drivers/nvwuwi.inf_amd64_5769f438b1032043/libcuda.so.1"
    APPTAINER_CONF="/etc/apptainer/apptainer.conf"
    BIND_ENTRY="bind path = ${WSL2_LIBCUDA}:/usr/lib/x86_64-linux-gnu/libcuda.so.1"
    if [ -f "$WSL2_LIBCUDA" ] && [ -f "$APPTAINER_CONF" ] && ! grep -q "$WSL2_LIBCUDA" "$APPTAINER_CONF"; then
        echo "---> WSL2 detected, adding libcuda bind path to apptainer.conf ..."
        sed -i "/^bind path = \/etc\/hosts/a $BIND_ENTRY" "$APPTAINER_CONF"
    fi

    echo "---> Waiting for slurmctld to become active before starting slurmd..."

    until 2>/dev/null >/dev/tcp/slurmctld/6817
    do
        echo "-- slurmctld is not available.  Sleeping ..."
        sleep 2
    done
    echo "-- slurmctld is now active ..."

    echo "---> Starting the Slurm Node Daemon (slurmd) ..."
    exec /usr/sbin/slurmd -Dvvv
fi

exec "$@"
