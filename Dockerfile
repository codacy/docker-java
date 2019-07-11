FROM library/ubuntu:18.04

LABEL maintainer="Rodrigo Fernandes <rodrigo@codacy.com>"

ENV JAVA_HOME /usr/lib/jvm/java-8-openjdk-amd64

RUN \
  apt-get -y update && \
  apt-get -y install software-properties-common && \
  apt-get -y install --reinstall locales && \
  apt-get -y install openjdk-8-jre && \
        rm -rf /root/.cache && \
        apt-get purge -y $(apt-cache search '~c' | awk '{ print $2 }') && \
        apt-get -y autoremove && \
        apt-get -y autoclean && \
        apt-get -y clean all && \
        rm -rf /var/lib/apt/lists/* && \
        rm -rf /var/cache/apt && \
        rm -rf /tmp/*

RUN locale-gen en_US.UTF-8

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8
ENV LC_ALL en_US.UTF-8
