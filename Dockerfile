FROM erlang:18.3.4.4
MAINTAINER Heinz N. Gies <heinz@project-fifo.net>

## Set up postgres

# explicitly set user/group IDs
RUN groupadd -r postgres --gid=999 && useradd -r -g postgres --uid=999 postgres

# grab gosu for easy step-down from root
ENV GOSU_VERSION 1.7
RUN set -x \
	&& apt-get update && apt-get install -y --no-install-recommends ca-certificates wget && rm -rf /var/lib/apt/lists/* \
	&& wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture)" \
	&& wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture).asc" \
	&& export GNUPGHOME="$(mktemp -d)" \
	&& gpg --keyserver ha.pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 \
	&& gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu \
	&& rm -r "$GNUPGHOME" /usr/local/bin/gosu.asc \
	&& chmod +x /usr/local/bin/gosu \
	&& gosu nobody true \
	&& apt-get purge -y --auto-remove ca-certificates wget

# make the "en_US.UTF-8" locale so postgres will be utf-8 enabled by default
RUN apt-get update && apt-get install -y locales && rm -rf /var/lib/apt/lists/* \
	&& localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
ENV LANG en_US.utf8

RUN mkdir /docker-entrypoint-initdb.d

RUN apt-key adv --keyserver ha.pool.sks-keyservers.net --recv-keys B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8

ENV PG_MAJOR 9.5
ENV PG_VERSION 9.5.5-1.pgdg80+1

RUN echo 'deb http://apt.postgresql.org/pub/repos/apt/ jessie-pgdg main' $PG_MAJOR > /etc/apt/sources.list.d/pgdg.list

RUN apt-get update \
	&& apt-get install -y postgresql-common \
	&& sed -ri 's/#(create_main_cluster) .*$/\1 = false/' /etc/postgresql-common/createcluster.conf \
	&& apt-get install -y \
		postgresql-$PG_MAJOR=$PG_VERSION \
		postgresql-contrib-$PG_MAJOR=$PG_VERSION \
	&& rm -rf /var/lib/apt/lists/*

# make the sample config easier to munge (and "correct by default")
RUN mv -v /usr/share/postgresql/$PG_MAJOR/postgresql.conf.sample /usr/share/postgresql/ \
	&& ln -sv ../postgresql.conf.sample /usr/share/postgresql/$PG_MAJOR/ \
	&& sed -ri "s!^#?(listen_addresses)\s*=\s*\S+.*!\1 = '*'!" /usr/share/postgresql/postgresql.conf.sample

RUN mkdir -p /var/run/postgresql && chown -R postgres /var/run/postgresql

ENV PATH /usr/lib/postgresql/$PG_MAJOR/bin:$PATH
ENV PGDATA /var/lib/postgresql/data

###################
##
## Get DalmatinerDB
##
###################
ENV DDB_VSN=dev
ENV DDB_PATH=/ddb
ENV DDB_REF=e7d5f7e0f74448d61d6164e42a2952614de98279

RUN cd / \
    && env GIT_SSL_NO_VERIFY=true git clone -b $DDB_VSN http://github.com/dalmatinerdb/dalmatinerdb.git dalmatinerdb.git \
    && cd dalmatinerdb.git \
    && env GIT_SSL_NO_VERIFY=true git checkout $DDB_REF \
    && make rel \
    && mv /dalmatinerdb.git/_build/prod/rel/ddb $DDB_PATH \
    && rm -rf /dalmatinerdb.git \
    && rm -rf $DDB_PATH/lib/*/c_src \
    && mkdir -p /data/dalmatinerdb/etc \
    && mkdir -p /data/dalmatinerdb/db \
    && mkdir -p /data/dalmatinerdb/log \
    && cp $DDB_PATH/etc/dalmatinerdb.conf.example /data/dalmatinerdb/etc/dalmatinerdb.conf \
    && sed -i -e '/RUNNER_USER=dalmatiner/d' $DDB_PATH/bin/ddb \
    && sed -i -e '/RUNNER_USER=dalmatiner/d' $DDB_PATH/bin/ddb-admin


###################
##
## Get DalmatinerFE
##
###################

ENV DFE_VSN=dev
ENV DFE_PATH=/dalmatinerfe
ENV DFE_REF=d18730b07ae3c9ed344465d9824bcd2331524aad

RUN cd / \
    && env GIT_SSL_NO_VERIFY=true git clone -b $DFE_VSN http://github.com/dalmatinerdb/dalmatiner-frontend.git dalmatiner-frontend.git \
    && cd dalmatiner-frontend.git \
    && env GIT_SSL_NO_VERIFY=true git checkout $DFE_REF \
    && make rel \
    && cp /dalmatiner-frontend.git/_build/prod/lib/dqe_idx_pg/priv/schema.sql /docker-entrypoint-initdb.d/ \
    && mv /dalmatiner-frontend.git/_build/prod/rel/dalmatinerfe $DFE_PATH \
    && rm -rf /dalmatiner-frontend.git \
    && rm -rf $DFE_PATH/lib/*/c_src \
    && cd / \
    && mkdir -p /data/dalmatinerfe/etc \
    && mkdir -p /data/dalmatinerfe/db \
    && mkdir -p /data/dalmatinerfe/log \
    && cp $DFE_PATH/etc/dalmatinerfe.conf.example /data/dalmatinerfe/etc/dalmatinerfe.conf \
    && sed -i -e '/RUNNER_USER=dalmatiner/d' $DFE_PATH/bin/dalmatinerfe \
    && sed -i -e 's/idx.backend = dqe_idx_ddb/idx.backend = dqe_idx_pg/' /data/dalmatinerfe/etc/dalmatinerfe.conf 

###################
##
## Get DDB Proxy
##
###################

ENV DP_VSN=dev
ENV DP_PATH=/ddb_proxy
ENV DP_REF=b86b77a0d5f0aa4cb1e470ca15daba03b475edb7

RUN cd / \
    && env GIT_SSL_NO_VERIFY=true git clone -b $DP_VSN http://github.com/dalmatinerdb/ddb_proxy.git ddb_proxy.git \
    && cd ddb_proxy.git \
    && env GIT_SSL_NO_VERIFY=true git checkout $DP_REF \
    && make rel \
    && mv /ddb_proxy.git/_build/prod/rel/ddb_proxy $DP_PATH \
    && rm -rf $DP_PATH/lib/*/c_src \
    && cd / \
    && rm -rf /ddb_proxy.git \
    && mkdir -p /data/ddb_proxy/db \
    && mkdir -p /data/ddb_proxy/etc \
    && mkdir -p /data/ddb_proxy/log \
    && cp $DP_PATH/etc/ddb_proxy.conf.example /data/ddb_proxy/etc/ddb_proxy.conf \
    && sed -i -e 's/idx.backend = dqe_idx_ddb/idx.backend = dqe_idx_pg/' /data/ddb_proxy/etc/ddb_proxy.conf \
    && echo "listeners.dp_graphite.bucket = graphite" >> /data/ddb_proxy/etc/ddb_proxy.conf \
    && echo "listeners.dp_graphite.port = 2003" >> /data/ddb_proxy/etc/ddb_proxy.conf \
    && echo "listeners.dp_graphite.protocol = tcp" >> /data/ddb_proxy/etc/ddb_proxy.conf \
    && echo "listeners.dp_otsdb.bucket = otsdb" >> /data/ddb_proxy/etc/ddb_proxy.conf \
    && echo "listeners.dp_otsdb.port = 4242" >> /data/ddb_proxy/etc/ddb_proxy.conf \
    && echo "listeners.dp_otsdb.protocol = tcp" >> /data/ddb_proxy/etc/ddb_proxy.conf \
    && echo "listeners.dp_bsdsyslog.bucket = syslog" >> /data/ddb_proxy/etc/ddb_proxy.conf \
    && echo "listeners.dp_bsdsyslog.port = 9999" >> /data/ddb_proxy/etc/ddb_proxy.conf \
    && echo "listeners.dp_bsdsyslog.protocol = udp" >> /data/ddb_proxy/etc/ddb_proxy.conf \
    && echo "listeners.dp_prom_writer.bucket = promwriter" >> /data/ddb_proxy/etc/ddb_proxy.conf \
    && echo "listeners.dp_prom_writer.port = 1234" >> /data/ddb_proxy/etc/ddb_proxy.conf \
    && echo "listeners.dp_prom_writer.protocol = http" >> /data/ddb_proxy/etc/ddb_proxy.conf \
    && sed -i -e '/RUNNER_USER=dalmatiner/d' $DP_PATH/bin/ddb_proxy


VOLUME /data
VOLUME /var/lib/postgresql/data
COPY docker-entrypoint.sh /

EXPOSE 8080
EXPOSE 8087
EXPOSE 2003
EXPOSE 4242
EXPOSE 9999
EXPOSE 1234

ENTRYPOINT ["/docker-entrypoint.sh"]
