## Azure Shipyard with InfiniBand and Intel MPI
Lightning fast performance in Azure with InfiniBand, Azure Storage and Intel MPI

I recently helped a customer to automate a High Performance Compute (HPC) project on Azure and wanted to share the below learnings 
and architecture.  The goal was to take a process that was running on an on-prem on a cluster and take advantage of the cloud.
We considered using Cycle Computing (https://cyclecomputing.com), but decided on a containerized approach using Docker.


### The Solution
- The solution uses Azure Shipyard http://batch-shipyard.readthedocs.io/en/latest/.  This is an open source project that automates 
  Azure Batch under the covers.  It provides for an easy to use command line interface to create clusters, submit jobs,
  monitor jobs, clean up and tear down.

- Docker Hub  / Azure Container Registry
  Both were tested and tried during the project.  Both ran into performance issues when we pulled 40+ images in high demand.  See learnings below.


### Easy to run
A single developer can provision a 40 node InfiniBand cluster with their code deployed in approximately five minutes.  No IT department required.

1. Create a pool of computers with Docker installed along with InfiniBand installed:
   ```
   docker run --rm -it -v '/mycofigs/configs':/configs -e SHIPYARD_CONFIGDIR=/configs alfpark/batch-shipyard:3.5.2-cli pool add
   ```

2. Easy to submit a job:
   ```
   docker run --rm -it -v '/mycofigs/configs':/configs -e SHIPYARD_CONFIGDIR=/configs alfpark/batch-shipyard:3.5.2-cli jobs add --tail stdout.txt
   ```

3. Easy to clean up resources (to stop the Azure billing)
   ```
   docker run --rm -it -v '/mycofigs/configs':/configs -e SHIPYARD_CONFIGDIR=/configs alfpark/batch-shipyard:3.5.2-cli pool del -y
   ```

### Performance
1. The InfiniBand allows Intel MPI to pass messages between the nodes at 25 Gbps speeds.  Recent Azure announcements will take this to 100 Gbps.
2. Downloading 1TB of data from Azure Blob storage can take less than 20 seconds.

### The sample Dockerfile
1. The Dockerfile in this repository shows you:
    1. How to include the drivers that are needed for InfiniBand (RDMA)
    2. How you include your Intel MPI license
    3. Download your C++ include libraries
    4. Compile your code (Yes, you will compile your code inside the Docker image)
    5. Then use a seperate stage to copy your files over to the final Docker image

2. You can also see my other repository where I show you how to access Azure Storage via C++ on Linux: https://github.com/AdamPaternostro/azure-storage-c-plus-plus


### The Architecture
![alt tag](https://raw.githubusercontent.com/AdamPaternostro/Azure-Shipyard-with-InfiniBand-and-Intel-MPI/master/images/MPI-Architecture.png)


### Monitoring your cluster
![alt tag](https://raw.githubusercontent.com/AdamPaternostro/Azure-Shipyard-with-InfiniBand-and-Intel-MPI/master/images/Monitoring.png)


### Learnings
1. Our pools were failing to be created?  Was this an Azure VM provisioning issues?  Bugs?  Turns out it was the Container Registry not being able to process all the requests when the pool was being created.  The pulling down of the same image 40+ times in a short timeframe caused issues.  Even with retry logic there was still issues.

   Solution: We worked with the Shipyard team to add a configuration to our config.yaml.  The configuration "delay_docker_image_preload: true" causes only 10  docker pulls at a time to reduce the strain on the container registry. You can further configure this value with "concurrent_source_downloads: 10" attribute.

2. Storage was getting too many egress errors.  The HPC process was trying to download almost 1 TB of data within a 20 second window.  
   
   Solution: Work with Azure Support to bump up the limits on the (v2) storage account.  Created 10 storage accounts and ensure they were on storage stamps that could support the egress.  Support can create the accounts on different stamps for you; otherwise, you need to create and then check the IP address of the stamp (using nslookup storageaccountname.blob.core.windows.net).  Doing yourself is a hit or miss operation.
   https://azure.microsoft.com/en-us/blog/announcing-larger-higher-scale-storage-accounts/ 

3. Use a multi-stage Docker build process (https://docs.docker.com/develop/develop-images/multistage-build/).  Our Docker image was about 4GB which put stress on the download of the container registry and just had extra waste in the image.  By using a multi-stage build the image was reduced less than 500MB.

4. More Docker layers is better than less.  Well, Docker says less layers are better since there is an overhead per layer.  But, when downloading the image from the repository, it is better to have more layers that are not too big.  In Azure the Azure Container Registry is backed by Blob storage and blob storage has concurrency limits on a single blob.  So, if you have a really large layer, then your 40+ nodes will have high contention to download this layer and will cause issues.  So, run a docker history command on your image and try to get layers are not too big.  Blob storage likes files around 80 MB to 100 MB.

5. Azure Blob files sizes should not be too small or too big.  A lot of little files (1KB) will cause a lot of reads.  Really large files will 100MB+ will also affect performance.  Based up Azure documentation a single blob can be read at 60MB per second(https://docs.microsoft.com/en-us/azure/azure-subscription-service-limits#storage-limits).
You should always review the service limits page when designing a large scale application to ensure you do not design against scale limits.  We kept our files between 80 MB and 100 MB.

