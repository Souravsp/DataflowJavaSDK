#!/bin/bash

# This script runs WordCount example locally in a few different ways.
# Specifically, all combinations of:
#  a) using mvn exec, or java -cp with a bundled jar file;
#  b) input filename with no directory component, with a relative directory, or
#     with an absolute directory; AND
#  c) input filename containing wildcards or not.
#
# The one optional parameter is a path from the directory containing the script
# to the directory containing the top-level (parent) pom.xml.  If no parameter
# is provided, the script assumes that directory is equal to the directory
# containing the script itself.
#
# The exit-code of the script indicates success or a failure.

set -e
set -o pipefail

MYDIR=$(dirname $0) || exit 2
cd $MYDIR

TOPDIR="."
if [[ $# -gt 0 ]]
then
  TOPDIR="$1"
fi

PASS=1
JAR_FILE=$TOPDIR/examples/target/google-cloud-dataflow-java-examples-all-bundled-manual_build.jar

function check_result_hash {
  local name=$1
  local outfile_prefix=$2
  local expected=$3

  local actual=$(md5sum $outfile_prefix-* | awk '{print $1}' || \
    md5 -q $outfile_prefix-*) || exit 2  # OSX
  if [[ "$actual" != "$expected" ]]
  then
    echo "FAIL $name: Output hash mismatch.  Got $actual, expected $expected."
    PASS=""
  else
    echo "pass $name"
    # Output files are left behind in /tmp
  fi
}

function get_outfile_prefix {
  local name=$1
  # NOTE: mktemp on OSX doesn't support --tmpdir
  mktemp -u "/tmp/$name.out.XXXXXXXXXX"
}

function run_via_mvn {
  local name=$1
  local input=$2
  local expected_hash=$3

  local outfile_prefix="$(get_outfile_prefix "$name")" || exit 2
  local cmd='mvn exec:java -f '"$TOPDIR"'/pom.xml -pl examples \
    -Dexec.mainClass=com.google.cloud.dataflow.examples.WordCount \
    -Dexec.args="--runner=DirectPipelineRunner --input='"$input"' --output='"$outfile_prefix"'"'
  echo "$name: Running $cmd" >&2
  sh -c "$cmd"
  check_result_hash "$name" "$outfile_prefix" "$expected_hash"
}

function run_bundled {
  local name=$1
  local input=$2
  local expected_hash=$3

  local outfile_prefix="$(get_outfile_prefix "$name")" || exit 2
  local cmd='java -cp '"$JAR_FILE"' \
    com.google.cloud.dataflow.examples.WordCount \
    --runner=DirectPipelineRunner \
    --input='"$input"' \
    --output='"$outfile_prefix"
  echo "$name: Running $cmd" >&2
  sh -c "$cmd"
  check_result_hash "$name" "$outfile_prefix" "$expected_hash"
}

function run_all_ways {
  local name=$1
  local input=$2
  local expected_hash=$3

  run_via_mvn ${name}a $input $expected_hash
  check_for_jar_file
  run_bundled ${name}b $input $expected_hash
}

function check_for_jar_file {
  if [[ ! -f $JAR_FILE ]]
  then
    echo "Jar file $JAR_FILE not created" >&2
    exit 2
  fi
}

# NOTE: We could still test via mvn exec if this fails for some reason.  Perhaps
# we ought to do that.
echo "Generating bundled JAR file" >&2
# NOTE: If this fails, run "mvn clean install" and try again.
mvn bundle:bundle -f $TOPDIR/pom.xml -pl examples
check_for_jar_file

run_all_ways wordcount1 "LICENSE" f4af56cd6f6f127536d586a6adcefba1
run_all_ways wordcount2 "./LICENSE" f4af56cd6f6f127536d586a6adcefba1
run_all_ways wordcount3 "$PWD/LICENSE" f4af56cd6f6f127536d586a6adcefba1
run_all_ways wordcount4 "L*N?E*" f4af56cd6f6f127536d586a6adcefba1
run_all_ways wordcount5 "./LICE*N?E" f4af56cd6f6f127536d586a6adcefba1
run_all_ways wordcount6 "$PWD/*LIC?NSE" f4af56cd6f6f127536d586a6adcefba1

if [[ ! "$PASS" ]]
then
  echo "One or more tests FAILED."
  exit 1
fi
echo "All tests PASS"