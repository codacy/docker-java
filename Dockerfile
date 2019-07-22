FROM debian:buster-slim

LABEL maintainer="Rodrigo Fernandes <rodrigo@codacy.com>"

RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		# Utilities for keeping Debian and OpenJDK CA certificates in sync
		ca-certificates p11-kit \
	; \
	rm -rf /var/lib/apt/lists/*

# Default to UTF-8 file.encoding
ENV LANG US.UTF-8

ENV JAVA_HOME /usr/local/graalvm-19-jre-8u222
ENV PATH $JAVA_HOME/bin:$PATH

# backwards compatibility shim
RUN { echo '#/bin/sh'; echo 'echo "$JAVA_HOME"'; } > /usr/local/bin/docker-java-home && chmod +x /usr/local/bin/docker-java-home && [ "$JAVA_HOME" = "$(docker-java-home)" ]

# https://github.com/oracle/graal/releases
ENV JAVA_VERSION 1.8.0_212
ENV GRAALVM_VERSION 19.1.0
ENV GRAALVM_JAVA_URL https://github.com/oracle/graal/releases/download/vm-${GRAALVM_VERSION}/graalvm-ce-linux-amd64-${GRAALVM_VERSION}.tar.gz

RUN set -eux; \
	\
	dpkgArch="$(dpkg --print-architecture)"; \
	case "$dpkgArch" in \
		amd64) upstreamArch='x64' ;; \
		arm64) upstreamArch='aarch64' ;; \
		*) echo >&2 "error: unsupported architecture: $dpkgArch" ;; \
	esac; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		dirmngr \
		gnupg \
		wget \
	; \
	rm -rf /var/lib/apt/lists/*; \
	\
	wget -O graalvm.tgz "${GRAALVM_JAVA_URL}" --progress=dot:giga; \
	\
	mkdir -p "$(dirname $JAVA_HOME)"; \
	export GRAAL_TMP="$(mktemp -d)"; \
	tar --extract \
		--file graalvm.tgz \
		--directory "$GRAAL_TMP" \
		--strip-components 1 \
		--no-same-owner \
	; \
	rm graalvm.tgz*; \
	find "$GRAAL_TMP" -name "*src.zip"  -printf "Deleting %p\n" -exec rm {} +; \
	\
	# Clean the JRE folder only since we are removing the rest
	rm -r "$GRAAL_TMP/jre/bin/polyglot"; \
	rm -r "$GRAAL_TMP/jre/languages"; \
	rm -r "$GRAAL_TMP/jre/lib/polyglot"; \
	rm "$GRAAL_TMP/jre/bin/jjs"; \
	rm "$GRAAL_TMP/jre/bin/keytool"; \
	rm "$GRAAL_TMP/jre/bin/orbd"; \
	rm "$GRAAL_TMP/jre/bin/pack200"; \
	rm "$GRAAL_TMP/jre/bin/policytool"; \
	rm "$GRAAL_TMP/jre/bin/rmid"; \
	rm "$GRAAL_TMP/jre/bin/rmiregistry"; \
	rm "$GRAAL_TMP/jre/bin/servertool"; \
	rm "$GRAAL_TMP/jre/bin/tnameserv"; \
	rm "$GRAAL_TMP/jre/bin/unpack200"; \
	rm "$GRAAL_TMP/jre/lib/ext/nashorn.jar"; \
	\
	# Moving the JRE to JAVA_HOME
	mv "${GRAAL_TMP}/jre" "$JAVA_HOME"; \
	rm -r "$GRAAL_TMP"; \
	\
	apt-mark auto '.*' > /dev/null; \
	[ -z "$savedAptMark" ] || apt-mark manual $savedAptMark > /dev/null; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	\
	# Update "cacerts" bundle to use Debian's CA certificates (and make sure it stays up-to-date with changes to Debian's store)
	# See https://github.com/docker-library/openjdk/issues/327
	#     http://rabexc.org/posts/certificates-not-working-java#comment-4099504075
	#     https://salsa.debian.org/java-team/ca-certificates-java/blob/3e51a84e9104823319abeb31f880580e46f45a98/debian/jks-keystore.hook.in
	#     https://git.alpinelinux.org/aports/tree/community/java-cacerts/APKBUILD?id=761af65f38b4570093461e6546dcf6b179d2b624#n29
	{ \
		echo '#!/usr/bin/env bash'; \
		echo 'set -Eeuo pipefail'; \
		echo 'if ! [ -d "$JAVA_HOME" ]; then echo >&2 "error: missing JAVA_HOME environment variable"; exit 1; fi'; \
		# 8-jdk uses "$JAVA_HOME/jre/lib/security/cacerts" and 8-jre and 11+ uses "$JAVA_HOME/lib/security/cacerts" directly (no "jre" directory)
		echo 'cacertsFile=; for f in "$JAVA_HOME/lib/security/cacerts" "$JAVA_HOME/jre/lib/security/cacerts"; do if [ -e "$f" ]; then cacertsFile="$f"; break; fi; done'; \
		echo 'if [ -z "$cacertsFile" ] || ! [ -f "$cacertsFile" ]; then echo >&2 "error: failed to find cacerts file in $JAVA_HOME"; exit 1; fi'; \
		echo 'trust extract --overwrite --format=java-cacerts --filter=ca-anchors --purpose=server-auth "$cacertsFile"'; \
	} > /etc/ca-certificates/update.d/docker-openjdk; \
	chmod +x /etc/ca-certificates/update.d/docker-openjdk; \
	/etc/ca-certificates/update.d/docker-openjdk; \
	\
	# basic smoke test
	java -version
