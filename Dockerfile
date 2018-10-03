#######################################################
# Dockerfile for Intel MPI+IB/RDMA workloads 
#######################################################

########## Docker Commands ##########
# Build Image:           docker build -t mpidockerimage .
# Login Registry:        docker login REMOVED.azurecr.io --username REMOVED --password REMOVED
# Tag:                   docker tag mpidockerimage:latest REMOVED.azurecr.io/mpidockerimage:latest 
# Push:                  docker push REMOVED.azurecr.io/mpidockerimage:latest
# Clean Up Docker:       docker stop $(docker ps -aq) | docker rm $(docker ps -aq)
# Clenn Up Docker sudo:  sudo docker stop $(sudo docker ps -aq) | sudo docker rm $(sudo docker ps -aq)
# Totally Clean Docker:  docker system prune -a

########## Shipyard Commands ##########
# Monitoring (one time thing)
# TO CREATE: docker run --rm -it -v '/Users/adam/mpiAzurePOC/configs':/configs -e SHIPYARD_CONFIGDIR=/configs alfpark/batch-shipyard:develop-cli monitor create
# TO REMOVE: docker run --rm -it -v '/Users/adam/mpiAzurePOC/configs':/configs -e SHIPYARD_CONFIGDIR=/configs alfpark/batch-shipyard:develop-cli monitor destroy

# Create a pool of computers
# docker run --rm -it -v '/Users/adam/mpiAzurePOC/configs':/configs -e SHIPYARD_CONFIGDIR=/configs alfpark/batch-shipyard:develop-cli pool add

# Add monitoring to the pool
# docker run --rm -it -v '/Users/adam/mpiAzurePOC/configs':/configs -e SHIPYARD_CONFIGDIR=/configs alfpark/batch-shipyard:develop-cli monitor add --poolid monitoringmpi00

# Remove all old jobs (if you have more than 5 jobs that are incomplete your next job will just wait endless for them to complete)
# docker run --rm -it -v '/Users/adam/mpiAzurePOC/configs':/configs -e SHIPYARD_CONFIGDIR=/configs alfpark/batch-shipyard:develop-cli jobs del --all-jobs -y

# Run your job
# docker run --rm -it -v '/Users/adam/mpiAzurePOC/configs':/configs -e SHIPYARD_CONFIGDIR=/configs alfpark/batch-shipyard:develop-cli jobs add --tail stdout.txt

# Now if you have issues with your code during development, you need to correct your code, rebuild your docker image, upload to your container registry,
# and get this new image to your batch nodes.  This command will re-pull your image.
# docker run --rm -it -v '/Users/adam/mpiAzurePOC/configs':/configs -e SHIPYARD_CONFIGDIR=/configs alfpark/batch-shipyard:develop-cli pool images update

# Turn off monitoring
# docker run --rm -it -v '/Users/adam/mpiAzurePOC/configs':/configs -e SHIPYARD_CONFIGDIR=/configs alfpark/batch-shipyard:develop-cli monitor remove --poolid monitoringmpi00

# Tear down your pool
# docker run --rm -it -v '/Users/adam/mpiAzurePOC/configs':/configs -e SHIPYARD_CONFIGDIR=/configs alfpark/batch-shipyard:develop-cli pool del -y

# To ssh into a node to debug issues:
# docker run --rm -it -v '/Users/adam/mpiAzurePOC/configs':/configs -e SHIPYARD_CONFIGDIR=/configs alfpark/batch-shipyard:develop-cli pool nodes list
# docker run --rm -it -v '/Users/adam/mpiAzurePOC/configs':/configs -e SHIPYARD_CONFIGDIR=/configs alfpark/batch-shipyard:develop-cli pool ssh --nodeid <<REPLACE ME>>


########## Generate SSH Pair (leave password blank), this is for your Monitor and Pool YAML ##########
# ssh-keygen -t rsa -b 4096 -C "shipyardssh"
# '/Users/adam/mpiAzurePOC/configssh/id_rsa'

# This Dockerfile is based upon
# Based upon:              https://github.com/Azure/batch-shipyard/blob/master/recipes/CNTK-CPU-Infiniband-IntelMPI/docker/Dockerfile
# You need a custom image: https://raw.githubusercontent.com/Azure/batch-shipyard/master/contrib/packer/ubuntu-16.04-IB 


############################################
# NOTE: You will see <<REMOVED>> below.  You should upload your items to Azure Blob storage and then
# create a Shared Access Signature so the docker build process can download your artifacts.
############################################


############################################
# Stage 1
############################################
FROM ubuntu:16.04
  
# set up base
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        autotools-dev \
        build-essential \
        curl \
        cmake \
        # Infiniband/RDMA
        cpio \
        libmlx4-1 \
        libmlx5-1 \
        librdmacm1 \
        libibverbs1 \
        libmthca1 \
        libdapl2 \
        dapl2-utils \
        # batch-shipyard deps
        openssh-server \
        openssh-client && \
    rm -rf /var/lib/apt/lists/*  && \
    apt-get clean
 
# add intel mpi library (using float license) and build
ENV MANPATH=/usr/share/man:/usr/local/man \
    COMPILERVARS_ARCHITECTURE=intel64 \
    COMPILERVARS_PLATFORM=linux \
    INTEL_MPI_PATH=/opt/intel/compilers_and_libraries/linux/mpi

# Download MPI and License file
RUN curl -k -o /tmp/l_mpi_2017.2.174.tgz '<<REMOVED>>' && \
    tar -xvf /tmp/l_mpi_2017.2.174.tgz -C /tmp && \
    rm /tmp/l_mpi_2017.2.174.tgz && \
    curl -k -o /tmp/l_mpi_2017.2.174/USE_SERVER.lic '<<REMOVED>>'

RUN sed -i -e 's/^ACCEPT_EULA=decline/ACCEPT_EULA=accept/g' /tmp/l_mpi_2017.2.174/silent.cfg && \
    sed -i -e 's|^#ACTIVATION_LICENSE_FILE=|ACTIVATION_LICENSE_FILE=/tmp/l_mpi_2017.2.174/USE_SERVER.lic|g' /tmp/l_mpi_2017.2.174/silent.cfg && \
    sed -i -e 's/^ACTIVATION_TYPE=exist_lic/ACTIVATION_TYPE=serial_number/g' /tmp/l_mpi_2017.2.174/silent.cfg && \
    sed -i -e 's/^#ACTIVATION_SERIAL_NUMBER=snpat/ACTIVATION_SERIAL_NUMBER=CGFH-B3STSKXV/g' /tmp/l_mpi_2017.2.174/silent.cfg && \
    cd /tmp/l_mpi_2017.2.174 && \
    ./install.sh -s silent.cfg && \
    cd .. && \
    rm -rf l_mpi_2017.2.174 && \
    . /opt/intel/bin/compilervars.sh && \
    . /opt/intel/compilers_and_libraries/linux/mpi/bin64/mpivars.sh && \
    # symlink mpicxx as mpic++ for non-standard calls
    ln -s ${INTEL_MPI_PATH}/${COMPILERVARS_ARCHITECTURE}/bin/mpicxx ${INTEL_MPI_PATH}/${COMPILERVARS_ARCHITECTURE}/bin/mpic++
    
# Libraries (your C++ necessary libraries)
RUN curl -k -o /tmp/boost_1_60_0.tar.gz '<<REMOVED>>' && \
    tar -xvf /tmp/boost_1_60_0.tar.gz -C /tmp && \
    rm /tmp/boost_1_60_0.tar.gz  

#source files
COPY mpiAzurePOC/* /tmp/ 

# build software
# source intel mpi vars
RUN . /opt/intel/bin/compilervars.sh && \
    . /opt/intel/compilers_and_libraries/linux/mpi/bin64/mpivars.sh && \
    cd tmp && \
    make -f Makefile_Intel && \
    # remove intel components (runtime will be mounted from the host)
    rm -rf /opt/intel

#### END MODIFY - INTEL MPI ###



############################################
# Stage 2
############################################
FROM ubuntu:16.04
  
# set up base
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    autotools-dev \
    build-essential \
    curl && \
    apt-get clean

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    # Infiniband/RDMA
    cpio \
    libmlx4-1 \
    libmlx5-1 \
    librdmacm1 \
    libibverbs1 \
    libmthca1 \
    libdapl2 \
    dapl2-utils && \
    apt-get clean

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    # batch-shipyard deps
    openssh-server \
    openssh-client && \
    rm -rf /var/lib/apt/lists/*  && \
    apt-get clean


# configure ssh server and keys
# set up SSH options for root
# COPY common/ssh_config /root/.ssh/config
# create SSH keypair for passwordless auth for MPI   
# note that instead of permanently building in an RSA keypair
# you can mount a pair into /root/.ssh from the host instead (which must be prepared separately)
 RUN mkdir /var/run/sshd && \
     ssh-keygen -A && \
     sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
     sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd && \
     mkdir /root/.ssh/ && \
     curl -k -o /root/.ssh/config '<<REMOVED>>'  && \
     chmod 600 /root/.ssh/config  && \
     chmod 700 /root/.ssh  && \
     ssh-keygen -f /root/.ssh/id_rsa -t rsa -N ''  && \
     cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
EXPOSE 23
CMD ["/usr/sbin/sshd", "-D", "-p", "23"]


# Just copy over the "Bin" directires for Boost, Zlib, Cll
COPY --from=0 /tmp/run_mpijob.sh /tmp/run_mpijob.sh
COPY --from=0 /tmp/mpiAzurePOC   /tmp/mpiAzurePOC
RUN  chmod +x /tmp/run_mpijob.sh
