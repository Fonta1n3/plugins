#!/bin/bash -x
set -e

CWD=$(pwd)
export SLOW_MACHINE=1
export PATH="$HOME/.local/bin:$PATH"
export PYTEST_PAR=10
export TEST_DEBUG=1
export LIGHTNING_VERSION=${LIGHTNING_VERSION:-master}
export PYTHONPATH=/tmp/lightning/contrib/pyln-client:/tmp/lightning/contrib/pyln-testing:/tmp/lightning/contrib/pylightning:$$PYTHONPATH

mkdir -p dependencies/bin

# Download bitcoind and bitcoin-cli 
echo 'travis_fold:start:script.0'
if [ ! -f dependencies/bin/bitcoind ]; then
    wget https://bitcoin.org/bin/bitcoin-core-0.17.1/bitcoin-0.17.1-x86_64-linux-gnu.tar.gz
    tar -xzf bitcoin-0.17.1-x86_64-linux-gnu.tar.gz
    mv bitcoin-0.17.1/bin/* dependencies/bin
    rm -rf bitcoin-0.17.1-x86_64-linux-gnu.tar.gz bitcoin-0.17.1
fi
echo 'travis_fold:end:script.0'

echo 'travis_fold:start:script.1'
pyenv global 3.7
pip3 install --quiet --upgrade pip
pip3 install --user --quiet \
     pyln-testing \
     mako==1.0.14 \
     psycopg2-binary>=2.8.3 \
     pytest-timeout==1.3.3 \
     pytest-xdist==1.30.0 \
     coverage \
     codecov \
     mrkd==0.1.6

echo 'travis_fold:end:script.1'

# Install the pyln-client and testing library matching c-lightning `master`

PY3=$(which python3)

echo 'travis_fold:start:script.2'
git clone --recursive https://github.com/ElementsProject/lightning.git /tmp/lightning
(cd /tmp/lightning && git checkout "$LIGHTNING_VERSION")
(cd /tmp/lightning/contrib/pyln-client && $PY3 setup.py install)
(cd /tmp/lightning/contrib/pyln-testing && $PY3 setup.py install)

# Compiling lightningd can be noisy and time-consuming, cache the binaries
if [ ! -f "$CWD/dependencies/usr/local/bin/lightningd" ]; then
    (
	cd /tmp/lightning && \
	./configure --disable-valgrind && \
	make -j 8 DESTDIR=dependencies/
    )
fi
echo 'travis_fold:end:script.2'

# Collect libraries that the plugins need and install them
echo 'travis_fold:start:script.3'
find . -name requirements.txt -exec pip3 install --quiet --upgrade --user -r {} \;
echo 'travis_fold:end:script.3'

# Add the local bitcoind bin dir so we can start and control it:
export PATH="$CWD/.travis/bin:$CWD/dependencies/bin:$CWD/dependencies/usr/local/bin/:$PATH"

# Add the directory we put the newly compiled lightningd in
export PATH="/tmp/lightning/lightningd/:$PATH"

# Enable coverage reporting from inside the plugin. This is done by adding a
# wrapper called python3 that internally just calls `coverage run` and stores
# the coverage output in `/tmp/.coverage.*` from where we can pick the details
# up again.
export PATH="$CWD/.travis/bin:$PATH"

# Make sure we use the correct python3 wrapper (the one that calls coverage
# internally).
which python3

pytest -vvv --timeout=550 --timeout_method=thread -p no:logging -n 2

# Print the coverage files
ls -lha /tmp/.coverage.*

# Now collect the results in a single file so coveralls finds them
coverage combine -a /tmp/.coverage.*
