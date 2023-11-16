FROM registry.opensuse.org/devel/openqa/containers15.5/openqa_worker

# Install custom openQA worker code
RUN git clone https://github.com/ssssam/openqa --branch sam/debug-missing-asset && \
    cd ./openqa && \
    cp -a ./lib /usr/share/openqa && \
    rm -rf ./openqa

ENTRYPOINT /bin/bash
