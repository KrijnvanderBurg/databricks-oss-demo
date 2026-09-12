ARG PYTHON_VERSION=3.10
FROM python:${PYTHON_VERSION}-bookworm

# Arguments for Spark setup
ARG SPARK_VERSION=4.1.3
ARG HADOOP_VERSION=3

# Install Java and other dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    openjdk-17-jdk \
    wget \
    curl \
    jq \
    procps \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set environment variables
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

# Set Spark environment variables
ENV SPARK_VERSION=${SPARK_VERSION}
ENV HADOOP_VERSION=${HADOOP_VERSION}
ENV SPARK_HOME=/opt/spark
ENV PATH=$PATH:$SPARK_HOME/bin

# Download and install Spark
RUN wget https://downloads.apache.org/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz && \
    tar -xzf spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz && \
    mv spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION} /opt/spark && \
    rm spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz

# Install Python dependencies including Jupyter
RUN pip install --no-cache-dir \
    pyspark==${SPARK_VERSION} \
    jupyter \
    jupyterlab \
    ipykernel

# Set up a Jupyter kernel with auto Spark initialization
RUN python -m ipykernel install --name pyspark --display-name "PySpark" && \
    mkdir -p /root/.ipython/profile_default/startup/
COPY 00-notebook-spark-init.py /root/.ipython/profile_default/startup/00-spark-init.py
RUN ipython kernel install --user --name=pyspark --display-name='PySpark'

WORKDIR /workspace

CMD ["sleep", "infinity"]
