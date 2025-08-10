# EDK II Docker Build Environment for tomitamoeko’s VfioIgdPkg

This setup creates a clean, reproducible environment for building tomitamoeko’s VfioIgdPkg IGD rom files.
It uses Docker and a Dockerfile to clone both the standard edk2 repo and tomitamoeko’s
VfioIgdPkg repo inside the container, so everything is ready to build right away.

**NOTE:** On run the container will produce a igd.rom file with _NO GOP display output_, i.e. without the IntelGopDriver.
This is only useful for UPT mode, NOT legacy mode, when used as vBIOS for IGD passtrough in QEMU.
For details see: https://github.com/tomitamoeko/VfioIgdPkg
and: https://github.com/qemu/qemu/blob/master/docs/igd-assign.txt

## Host Directory Structure

```
igd-rom/
├── README.md # This file
├── Dockerfile # Docker build instructions
└── build-output/ # Directory for persistant storage
```

## Build the Docker image

From the host

```bash
docker build -t edk2-igd .
```

## Run the Docker container

From the host igd-rom directory

```bash
docker run --rm \
    -v $(pwd)/build-output:/edk2/build-output \
    edk2-igd
```

The container will self-destroy on exit.
This is why we map in the build-output directory for persistant storage of the igd.rom file on the host

## ROM file build

This is automated in the Docker file and executes automatically on container run.

The output file is called igd.rom and is copied to the mapped folder so it is accessible from the host build-output directory

See the CMD section in the Dockerfile for details on teh buidl and copy commands.

## Container Directory Structure

```
edk2/ # edk2 build tools
└── VfioIgdPkg/ # tomitamoeko’s VfioIgdPkg code
└── build-output/ # Directory mapped to host persistant storage
```

## Dockerfile explanation

```dockerfile
# Start from Tianocore's Ubuntu 22 build image
FROM ghcr.io/tianocore/containers/ubuntu-22-build:latest

# Set working directory to edk2 repo root
WORKDIR /edk2

# Clone and initiate the edk2 repo
RUN git clone https://github.com/tianocore/edk2.git . && \
    git submodule update --init && \
    make -C BaseTools

# Clone VfioIgdPkg into /edk2/VfioIgdPkg
RUN git clone https://github.com/tomitamoeko/VfioIgdPkg.git /edk2/VfioIgdPkg

# Always source edksetup.sh when starting a shell
RUN echo "source /edk2/edksetup.sh" >> /root/.bashrc

# Ensure build output directory exists
RUN mkdir -p /edk2/build-output

# Run build automatically, copy output file to mapped directory, and fail if not found
CMD ["bash", "-c", "\
    source /edk2/edksetup.sh && \
    cd /edk2/VfioIgdPkg && \
    ./build.sh igd.rom && \
    if [ ! -f /edk2/VfioIgdPkg/igd.rom ]; then \
    echo 'ERROR: igd.rom not found!' >&2; \
    exit 1; \
    fi && \
    cp /edk2/VfioIgdPkg/igd.rom /edk2/build-output/ \
    "]
```
