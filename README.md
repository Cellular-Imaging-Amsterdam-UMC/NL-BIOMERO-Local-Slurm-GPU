# Local Slurm cluster with GPU support (for BIOMERO)

This is a multi-container Slurm cluster using docker-compose with **NVIDIA GPU passthrough**.
All worker nodes (c1, c2) share the host GPU(s) via the NVIDIA Container Toolkit.
The compose file creates named volumes for persistent storage of MySQL data files as well as
Slurm state and log directories.

## Prerequisites

- Docker Engine with [Docker Compose v2](https://docs.docker.com/compose/install/)
- NVIDIA GPU driver installed on the host
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) installed on the host

Verify your GPU is visible to Docker:

    docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi

## Quickstart

> **Upgrading from the CPU-only cluster?**  
> Run `docker-compose down --volumes` first so the new GPU config files
> take effect in the shared `etc_slurm` volume.

Clone this repository locally

    git clone https://github.com/Cellular-Imaging-Amsterdam-UMC/NL-BIOMERO-Local-Slurm-GPU

Change into the new directory

    cd NL-BIOMERO-Local-Slurm-GPU

Copy your public SSH key into this directory, to allow SSH access

    cp ~/.ssh/id_rsa.pub .

Build and run the GPU-enabled Slurm cluster containers

    docker-compose up -d --build

Verify the GPU is visible inside the worker nodes:

    docker exec c1 nvidia-smi

Now you can access Slurm through SSH (from inside a Docker container):

    ssh -i ~/.ssh/id_rsa -p 2222 -o StrictHostKeyChecking=no slurm@host.docker.internal

Or (from your host Windows machine):

    ssh -i ~/.ssh/id_rsa -p 2222 -o StrictHostKeyChecking=no slurm@localhost

Done.

If the SSH is not working, it might be permission related since SSH is quite specific about that. 
Try forcing ownership and access: 

    docker exec -it slurmctld bash -c "chown -R slurm:slurm /home/slurm/.ssh && chmod 700 /home/slurm/.ssh && chmod 600 /home/slurm/.ssh/authorized_keys" 

Submit a test GPU job from the `/data` directory:

    sbatch -n 1 --gres=gpu:1 --wrap "nvidia-smi > gpu_test.log"

Or a Singularity job:

    sbatch -n 1 --wrap "hostname > lolcow.log && singularity run docker://godlovedc/lolcow >> lolcow.log"

This should say "Submitted batch job 1"
Then let's tail the logfile:

    tail -f lolcow.log

First we see the slurm node that is computing, and later we will see the funny cow.

```bash
[slurm@slurmctld data]$ tail -f lolcow.log
c1
 _______________________________________
/ Must I hold a candle to my shames?    \
|                                       |
| -- William Shakespeare, "The Merchant |
\ of Venice"                            /
 ---------------------------------------
        \   ^__^
         \  (oo)\_______
            (__)\       )\/\
                ||----w |
                ||     ||
```

Exit logs with `CTRL+C`, and the container with `exit`, and enjoy your local Slurm cluster.

## New Features

We added the following features to this (forked) cluster:
- Running SSH on the SlurmCTLD, you can connect to it at `host.docker.internal:2222`
- Running Singularity, you can fire off any singularity container now, e.g.:

    `sbatch -n 1 --wrap "hostname > lolcow.log && singularity run docker://godlovedc/lolcow >> lolcow.log"`

This should give a funny cow in lolcow.log and the host farm on which the cow was grazing.

Note: Like always be sure to run Slurm commands from `/data`, the shared folder/volume. Otherwise it won't be able to share the created logfile.

### Submitting GPU Jobs

Request a GPU using `--gres=gpu:1`:

    sbatch -n 1 --gres=gpu:1 --wrap "nvidia-smi > gpu_test.log"

Or target the `gpu` partition explicitly:

    sbatch -p gpu --gres=gpu:1 --wrap "nvidia-smi > gpu_test.log"

Verify GPU allocation:

    sinfo -o "%N %G"   # shows GRES per node
    squeue -o "%i %j %b" # shows GRES allocated per job


We have not added:
- Multi-GPU-per-node support (edit `gres.conf` and `slurm.conf` if your host has multiple GPUs)

## Docker specifics 

To stop the cluster:

    docker-compose down

N.B. Data is stored on Docker volumes, which are not automatically deleted when you down the setup. Convenient.

To remove volumes as well:

    docker-compose down --volumes

To rebuild a single container (while running your cluster):

    docker-compose up -d --build <name>

To attach to a running container:

    docker-compose exec <name> /bin/bash

Where `<name>` is e.g. `slurmctld` or `c1`

Exit back to your commandline by typing `exit`.

Or check the logs

    docker-compose logs -f 

Exit with CTRL+C (only exits the logs, does not shut down the container)

## Containers and Volumes

The compose file will run the following containers:

* mysql
* slurmdbd
* slurmctld
* c1 (slurmd)
* c2 (slurmd)

The compose file will create the following named volumes:

* etc_munge         ( -> /etc/munge     )
* etc_slurm         ( -> /etc/slurm     )
* slurm_jobdir      ( -> /data          )
* var_lib_mysql     ( -> /var/lib/mysql )
* var_log_slurm     ( -> /var/log/slurm )

## Slurm specifics

### Register the Cluster with SlurmDBD

To register the cluster to the slurmdbd daemon, run the `register_cluster.sh`
script:

```console
./register_cluster.sh
```

> Note: You may have to wait a few seconds for the cluster daemons to become
> ready before registering the cluster.  Otherwise, you may get an error such
> as **sacctmgr: error: Problem talking to the database: Connection refused**.
>
> You can check the status of the cluster by viewing the logs: `docker-compose
> logs -f`

### Accessing the Cluster

Use `docker exec` to run a bash shell on the controller container:

```console
docker exec -it slurmctld bash
```

From the shell, execute slurm commands, for example:

```console
[root@slurmctld /]# sinfo
PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
normal*      up 5-00:00:00      2   idle c[1-2]
```

### Submitting Jobs

The `slurm_jobdir` named volume is mounted on each Slurm container as `/data`.
Therefore, in order to see job output files while on the controller, change to
the `/data` directory when on the **slurmctld** container and then submit a job:

```console
[root@slurmctld /]# cd /data/
[root@slurmctld data]# sbatch --wrap="uptime"
Submitted batch job 2
[root@slurmctld data]# ls
slurm-2.out
```
