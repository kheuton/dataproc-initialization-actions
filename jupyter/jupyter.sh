#!/usr/bin/env bash
set -e

ROLE=$(curl -f -s -H Metadata-Flavor:Google http://metadata/computeMetadata/v1/instance/attributes/dataproc-role)
INIT_ACTIONS_REPO=$(curl -f -s -H Metadata-Flavor:Google http://metadata/computeMetadata/v1/instance/attributes/INIT_ACTIONS_REPO || true)
INIT_ACTIONS_REPO="${INIT_ACTIONS_REPO:-https://github.com/GoogleCloudPlatform/dataproc-initialization-actions.git}"
INIT_ACTIONS_BRANCH=$(curl -f -s -H Metadata-Flavor:Google http://metadata/computeMetadata/v1/instance/attributes/INIT_ACTIONS_BRANCH || true)
INIT_ACTIONS_BRANCH="${INIT_ACTIONS_BRANCH:-master}"
DATAPROC_BUCKET=$(curl -f -s -H Metadata-Flavor:Google http://metadata/computeMetadata/v1/instance/attributes/dataproc-bucket)

# Colon-separated list of conda packages to install, for example 'numpy:pandas'
JUPYTER_CONDA_PACKAGES=$(curl -f -s -H Metadata-Flavor:Google http://metadata/computeMetadata/v1/instance/attributes/JUPYTER_CONDA_PACKAGES || true)
# Colon-separated list of conda packages to install, for example '????'
JUPYTER_PIP_PACKAGES=$(curl -f -s -H Metadata-Flavor:Google http://metadata/computeMetadata/v1/instance/attributes/JUPYTER_PIP_PACKAGES || true)


echo "Cloning fresh dataproc-initialization-actions from repo $INIT_ACTIONS_REPO and branch $INIT_ACTIONS_BRANCH..."
git clone -b "$INIT_ACTIONS_BRANCH" --single-branch $INIT_ACTIONS_REPO
# Ensure we have conda installed.
./dataproc-initialization-actions/conda/bootstrap-conda.sh
# This is commented out in the default. We don't need to mess with environments,
# we can just use a root installation
#./dataproc-initialization-actions/conda/install-conda-env.sh

# Make sure we're set up to use the conda just installed
source /etc/profile.d/conda_config.sh

# Alright now we need to modify the channels we look for packages in
# r is for r stuff, naturally, krheuton is for logstash, conda-forge is for pyarrow
cat >> ~/.condarc <<'_EOF'

channels:
  - r
  - defaults
  - conda-forge
  - krheuton

_EOF
# Make sure the relevant spark libraries are accessible to Python
echo "You're running dataproc, heres SPARK_HOME: $SPARK_HOME <- you're in trouble if that's blank"
export PYTHONPATH=$SPARK_HOME/python/:$PYTHONPATH
# This limits you to using Spark 2.1 Adjust the py4j version for older Spark versions
export PYTHONPATH=$SPARK_HOME/python/lib/py4j-0.10.4-src.zip:$PYTHONPATH
echo "Prepended $SPARK_HOME/python and $SPARK_HOME/python/lib/py4j-0.10.4-src.zip to the PYTHONPATH"

# These are the packages we always want there
DEFAULT_CONDA_PACKAGES='accelerate pandas pymysql scipy seaborn sqlalchemy sympy rpy2 notebook jupyter ipython statsmodels mysql-python mysql networkx pytables matplotlib jinja2 dill pyyaml click pyarrow parquet-cpp logstash'
DEFAULT_PIP_PACKAGES=

if [ -n "${DEFAULT_CONDA_PACKAGES}" ]; then
  echo "Installing hard-coded conda packages '$(echo ${DEFAULT_CONDA_PACKAGES} | tr ':' ' ')'"
  conda install $(echo ${DEFAULT_CONDA_PACKAGES})
fi

if [ -n "${DEFAULT_PIP_PACKAGES}" ]; then
  echo "Installing hard-coded pip packages '$(echo ${DEFAULT_PIP_PACKAGES} | tr ':' ' ')'"
  pip install $(echo ${DEFAULT_PIP_PACKAGES})
fi

if [ -n "${JUPYTER_CONDA_PACKAGES}" ]; then
  echo "Installing custom conda packages '$(echo ${JUPYTER_CONDA_PACKAGES} | tr ':' ' ')'"
  conda install $(echo ${JUPYTER_CONDA_PACKAGES} | tr ':' ' ')
fi

if [ -n "${JUPYTER_PIP_PACKAGES}" ]; then
  echo "Installing custom pip packages '$(echo ${JUPYTER_PIP_PACKAGES} | tr ':' ' ')'"
  pip install $(echo ${JUPYTER_PIP_PACKAGES} | tr ':' ' ')
fi

if [[ "${ROLE}" == 'Master' ]]; then
    conda install jupyter
    if gsutil -q stat "gs://$DATAPROC_BUCKET/notebooks/**"; then
        echo "Pulling notebooks directory to cluster master node..."
        gsutil -m cp -r gs://$DATAPROC_BUCKET/notebooks /root/
    fi
    ./dataproc-initialization-actions/jupyter/internal/setup-jupyter-kernel.sh
    ./dataproc-initialization-actions/jupyter/internal/launch-jupyter-kernel.sh
fi
echo "Completed installing Jupyter!"

# Install Jupyter extensions (if desired)
# TODO: document this in readme
if [[ ! -v $INSTALL_JUPYTER_EXT ]]
    then
    INSTALL_JUPYTER_EXT=false
fi
if [[ "$INSTALL_JUPYTER_EXT" = true ]]
then
    echo "Installing Jupyter Notebook extensions..."
    ./dataproc-initialization-actions/jupyter/internal/bootstrap-jupyter-ext.sh
    echo "Jupyter Notebook extensions installed!"
fi
