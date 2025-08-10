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