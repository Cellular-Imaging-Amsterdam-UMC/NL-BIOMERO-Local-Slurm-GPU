# Local Slurm cluster with GPU support (for BIOMERO)

This is a multi-container Slurm cluster using docker-compose with **NVIDIA GPU passthrough**.
Designed for **Docker Desktop with WSL2** (Windows). One worker node (c1) has GPU access; one (c2) is CPU-only.
The compose file creates named volumes for persistent storage of MySQL data files as well as
Slurm state and log directories.

## Prerequisites

- Docker Engine with [Docker Compose v2](https://docs.docker.com/compose/install/)
- NVIDIA GPU driver installed on the host
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) installed on the host

Verify your GPU is visible to Docker:

    docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi

## Quickstart

Clone this repository locally

    git clone https://github.com/Cellular-Imaging-Amsterdam-UMC/NL-BIOMERO-Local-Slurm-GPU

Change into the new directory

    cd NL-BIOMERO-Local-Slurm-GPU

Copy your public SSH key into this directory, to allow SSH access

    cp ~/.ssh/id_rsa.pub .

Build and run the GPU-enabled Slurm cluster containers

    docker compose up -d --build

Verify the GPU is visible inside the worker nodes:

    docker compose exec c1 nvidia-smi

Now you can access Slurm through SSH (from inside a Docker container):

    ssh -i ~/.ssh/id_rsa -p 2222 -o StrictHostKeyChecking=no slurm@host.docker.internal

Or (from your host Windows machine):

    ssh -i ~/.ssh/id_rsa -p 2222 -o StrictHostKeyChecking=no slurm@localhost

Done.

If the SSH is not working, it might be permission related since SSH is quite specific about that. 
Try forcing ownership and access: 

    docker compose exec slurmctld bash -c "chown -R slurm:slurm /home/slurm/.ssh && chmod 700 /home/slurm/.ssh && chmod 600 /home/slurm/.ssh/authorized_keys"

Submit a first test job — the classic lolcow:

    cd /data && sbatch -n 1 --wrap "hostname > lolcow.log && singularity run docker://godlovedc/lolcow >> lolcow.log" && tail --retry -f lolcow.log

First we see the Slurm node that ran the job, then the cow:

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

Exit logs with `CTRL+C`. Now test GPU access. First a quick device check:

    cd /data && sbatch -n 1 --gres=gpu:1 --wrap "nvidia-smi > gpu_test.log" && tail --retry -f gpu_test.log

Exit logs with `CTRL+C`. Then a real GPU compute test using PyTorch — this proves CUDA actually works, not just device
visibility. Note: the first run downloads the PyTorch container (~3 GB), subsequent runs use
the cache and start immediately.

    cd /data && sbatch -p gpu --gres=gpu:1 -o /data/gpu-test.log --wrap 'singularity exec --nv docker://pytorch/pytorch:2.3.0-cuda12.1-cudnn8-runtime python3 -c "import torch; x=torch.randn(8000,8000).cuda(); y=torch.randn(8000,8000).cuda(); [torch.mm(x,y) for _ in range(100)]; torch.cuda.synchronize(); print(torch.cuda.get_device_name(0), round(torch.cuda.memory_allocated()/1e9,2), \"GB - Done\")"'

    tail --retry -f /data/gpu-test.log

Exit logs with `CTRL+C`, and the container with `exit`. Enjoy your local Slurm cluster.

## Features

- SSH on the SlurmCTLD at `host.docker.internal:2222`
- Singularity/Apptainer for running any container image as a Slurm job
- GPU passthrough via NVIDIA Container Toolkit (`--nv` flag)
- Persistent image cache at `/data/.apptainer_cache` — images survive cluster restarts

> **Note:** Run Slurm commands from `/data` (the shared volume) so job output files are
> accessible from all nodes and the controller.

### GPU Jobs

Request a GPU with `--gres=gpu:1`. Use `-p gpu` to target the dedicated GPU partition (c1 only):

    sbatch -p gpu --gres=gpu:1 --wrap "nvidia-smi > gpu_test.log"

Verify GPU scheduling:

    sinfo -o "%N %G"        # shows GRES per node
    squeue -o "%i %j %b"    # shows GRES allocated per running job

#### GPU assignment

This cluster mirrors a typical HPC setup: **c1 is the GPU node, c2 is CPU-only**.

| Node | GPU | Partitions |
|------|-----|-----------|
| c1   | ✅ 1× GPU (`gpu:1`) | `normal`, `gpu` |
| c2   | ❌ CPU only | `normal` |

GPU jobs land exclusively on c1. CPU jobs run on either node via the default `normal` partition.
This reflects reality on a single-GPU host — Slurm will never schedule two concurrent GPU jobs.

### WSL2 GPU Support (Docker Desktop on Windows)

This cluster works on Docker Desktop with WSL2 backend. The following adaptations are applied
automatically at worker startup — no manual steps needed:

- **`/dev/dxg`**: WSL2 exposes the GPU via `/dev/dxg` instead of `/dev/nvidia0`. Configured in `gres.conf`.
- **WSL2 `libcuda.so` override**: `docker-entrypoint.sh` dynamically finds the WSL2-compatible
  `libcuda.so.1` under `/usr/lib/wsl/drivers/` (folder name changes with each driver update) and
  binds it into all Singularity containers via `apptainer.conf`.

## Docker specifics 

To stop the cluster:

    docker compose down

N.B. Data is stored on Docker volumes, which are not automatically deleted when you down the setup. Convenient.

To remove volumes as well:

    docker compose down --volumes

To rebuild a single container (while running your cluster):

    docker compose up -d --build <name>

To attach to a running container:

    docker compose exec <name> /bin/bash

Where `<name>` is e.g. `slurmctld` or `c1`

Exit back to your commandline by typing `exit`.

Or check the logs

    docker compose logs -f 

Exit with CTRL+C (only exits the logs, does not shut down the container)

## Containers and Volumes

The compose file will run the following containers:

* mysql
* slurmdbd
* slurmctld
* c1 (slurmd)
* c2 (slurmd)

The compose file will create the following named volumes (prefixed with `gpu_` to avoid
clashing with the CPU-only cluster's volumes):

* gpu_etc_munge         ( -> /etc/munge     )
* gpu_etc_slurm         ( -> /etc/slurm     )
* gpu_slurm_jobdir      ( -> /data          )
* gpu_var_lib_mysql     ( -> /var/lib/mysql )
* gpu_var_log_slurm     ( -> /var/log/slurm )
* gpu_home_cache        ( -> /home/slurm    )

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
normal*      up   infinite      2   idle c[1-2]
gpu          up   infinite      1   idle c1
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

## Running on Native Linux

This repo is configured for **WSL2 by default** due to `gres.conf` using `/dev/dxg` (the WSL2 GPU device).
To run on a native Linux host with a standard NVIDIA driver, at least two things need to change:

1. **`gres.conf`** — replace the WSL2 device with the standard NVIDIA device:

   ```diff
   - NodeName=c1 Name=gpu File=/dev/dxg Count=1
   + NodeName=c1 Name=gpu File=/dev/nvidia0 Count=1
   ```

   If you have multiple GPUs, list them as `File=/dev/nvidia0,/dev/nvidia1,...` and update `Count` accordingly.

2. **`docker-compose.yml`** — verify the worker nodes have GPU access. The `deploy.resources.reservations.devices` block (NVIDIA Container Toolkit) should already work on native Linux without changes.

No equivalent entrypoint changes are needed on Linux. The WSL2 block in `docker-entrypoint.sh` exists because WSL2 has no `/dev/nvidia0`, which causes `nvidia-container-cli` to fail silently — so it gets disabled and libcuda is injected manually. On native Linux, `/dev/nvidia0` exists, `nvidia-container-cli` works, and Apptainer handles CUDA library injection automatically via the standard path. The WSL2 block is conditional (only fires when `/usr/lib/wsl/drivers/` exists) and will not run on Linux.
