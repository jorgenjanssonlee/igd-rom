# EDK II Docker Build Environment for tomitamoeko’s VfioIgdPkg

This setup creates a clean, reproducible environment for building tomitamoeko’s VfioIgdPkg IGD rom files.
For details see: https://github.com/tomitamoeko/VfioIgdPkg

It uses Docker and a Dockerfile to clone both tomitamoeko’s patched edk2 repo and the
VfioIgdPkg repo inside the container, so everything is ready to build right away.

## Host Directory Structure

```
igd-rom/
├── Dockerfile # Docker build instructions
├── README.md # This file
└── build-output/ # Directory mapped to host persistant storage
```

## Docker build command

From the host

```
docker run -it --rm \
  -v /path/to/host/build-output:/edk2/build-output \
  edk2-vfioigd-build
```

The container will self-destroy on exit, which is why we map in the build-output directory for persistant storage on the host

## Container Directory Structure

```
edk2/
└── VfioIgdPkg/ # tomitamoeko’s VfioIgdPkg code
    └── build-output/ # Directory mapped to host persistant storage
```

## ROM file build

From wihtin the running container

Build the igd.rom file and copy it into the mapped build-output folder:

Inside the container, when you run the build script, specify the output path or copy the resulting file to /edk2/build-output. For example:

```
cd /edk2/VfioIgdPkg
./build.sh igd.rom
```

Copy igd.rom to mapped folder so it appears on host

```
cp Build/.../FV/igd.rom /edk2/build-output/
```

Replace Build/.../FV/igd.rom with the actual path printed after build (usually something like Build/IgdAssignmentDxe/DEBUG_GCC5/FV/igd.rom).

## Alternative ROM file build directly to output directory

```
cd /edk2/VfioIgdPkg
./build.sh /edk2/build-output/igd.rom
```

## Dockerfile explanation

```dockerfile
# Start from Tianocore's Ubuntu 22 build image
FROM ghcr.io/tianocore/containers/ubuntu-22-build:latest

# Set working directory to edk2 repo root
WORKDIR /edk2

# Clone tomitamoeko's patched edk2 repo
RUN git clone https://github.com/tomitamoeko/edk2.git . && \
    git submodule update --init && \
    make -C BaseTools

# Clone VfioIgdPkg into /edk2/VfioIgdPkg
RUN git clone https://github.com/tomitamoeko/VfioIgdPkg.git /edk2/VfioIgdPkg

# Always source edksetup.sh when starting a shell
RUN echo "source /edk2/edksetup.sh" >> /root/.bashrc

# Default to interactive bash
CMD ["/bin/bash"]
```
