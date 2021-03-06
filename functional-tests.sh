#!/bin/bash
#
# Minio Client (C) 2017 Minio, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

################################################################################
#
# This script is usable by mc functional tests, mint tests and minio verfication
# tests.
#
# * As mc functional tests, just run this script.  It uses mc executable binary
#   in current working directory or in the path.  The tests uses play.minio.io
#   as minio server.
#
# * For other, call this script with environment variables MINT_MODE,
#   MINT_DATA_DIR, SERVER_ENDPOINT, ACCESS_KEY, SECRET_KEY and ENABLE_HTTPS. It
#   uses mc executable binary in current working directory and uses given minio
#   server to run tests. MINT_MODE is set by mint to specify what category of
#   tests to run.
#
################################################################################

if [ -n "$MINT_MODE" ]; then
    if [ -z "${MINT_DATA_DIR+x}" ]; then
        echo "MINT_DATA_DIR not defined"
        exit 1
    fi
    if [ -z "${SERVER_ENDPOINT+x}" ]; then
        echo "SERVER_ENDPOINT not defined"
        exit 1
    fi
    if [ -z "${ACCESS_KEY+x}" ]; then
        echo "ACCESS_KEY not defined"
        exit 1
    fi
    if [ -z "${SECRET_KEY+x}" ]; then
        echo "SECRET_KEY not defined"
        exit 1
    fi
fi

if [ -z "${SERVER_ENDPOINT+x}" ]; then
    SERVER_ENDPOINT="play.minio.io:9000"
    ACCESS_KEY="Q3AM3UQ867SPQQA43P2F"
    SECRET_KEY="zuf+tfteSlswRu7BJ86wekitnifILbZam1KYY3TG"
    ENABLE_HTTPS=1
    SERVER_REGION="us-east-1"
fi

WORK_DIR="$PWD"
DATA_DIR="$MINT_DATA_DIR"
if [ -z "$MINT_MODE" ]; then
    WORK_DIR="$PWD/.run-$RANDOM"
    DATA_DIR="$WORK_DIR/data"
fi

FILE_1_MB="$DATA_DIR/datafile-1-MB"
FILE_65_MB="$DATA_DIR/datafile-65-MB"
declare FILE_1_MB_MD5SUM
declare FILE_65_MB_MD5SUM

ENDPOINT="https://$SERVER_ENDPOINT"
if [ "$ENABLE_HTTPS" != "1" ]; then
    ENDPOINT="http://$SERVER_ENDPOINT"
fi

SERVER_ALIAS="myminio"
BUCKET_NAME="mc-test-bucket-$RANDOM"
WATCH_OUT_FILE="$WORK_DIR/watch.out-$RANDOM"

MC_CONFIG_DIR="/tmp/.mc-$RANDOM"
MC="$PWD/mc"
declare -a MC_CMD

function get_md5sum()
{
    filename="$FILE_1_MB"
    out=$(md5sum "$filename" 2>/dev/null)
    rv=$?
    if [ "$rv" -eq 0 ]; then
        echo $(awk '{ print $1 }' <<< "$out")
    fi

    return "$rv"
}

function get_time()
{
    date +%s%N
}

function get_duration()
{
    start_time=$1
    end_time=$(get_time)

    echo $(( (end_time - start_time) / 1000000 ))
}

function log_success()
{
    if [ -n "$MINT_MODE" ]; then
        printf '{"name": "mc", "duration": "%d", "function": "%s", "status": "PASS"}\n' "$(get_duration "$1")" "$2"
    fi
}

function show()
{
    if [ -z "$MINT_MODE" ]; then
        func_name="$1"
        echo "Running $func_name()"
    fi
}

function fail()
{
    rv="$1"
    shift

    if [ "$rv" -ne 0 ]; then
        echo "$@"
    fi

    return "$rv"
}

function assert()
{
    expected_rv="$1"
    shift
    start_time="$1"
    shift
    func_name="$1"
    shift

    err=$("$@")
    rv=$?
    if [ "$rv" -ne "$expected_rv" ]; then
        if [ -n "$MINT_MODE" ]; then
            err=$(python -c 'import sys,json; print(json.dumps(sys.stdin.read()))' <<<"$err")
            printf '{"name": "mc", "duration": "%d", "function": "%s", "status": "FAIL", "error": "%s"}\n' "$(get_duration "$start_time")" "$func_name" "$err"
        else
            echo "mc: $func_name: $err"
        fi

        exit "$rv"
    fi

    return 0
}

function assert_success() {
    assert 0 "$@"
}

function assert_failure() {
    assert 1 "$@"
}

function mc_cmd()
{
    cmd=( "${MC_CMD[@]}" "$@" )
    err_file="$WORK_DIR/cmd.out.$RANDOM"

    "${cmd[@]}" >"$err_file" 2>&1
    rv=$?
    if [ "$rv" -ne 0 ]; then
        printf '%q ' "${cmd[@]}"
        echo " >>> "
        cat "$err_file"
    fi

    rm -f "$err_file"
    return "$rv"
}

function check_md5sum()
{
    expected_checksum="$1"
    shift
    filename="$@"

    checksum="$(get_md5sum "$filename")"
    rv=$?
    if [ "$rv" -ne 0 ]; then
        echo "unable to get md5sum for $filename"
        return "$rv"
    fi

    if [ "$checksum" != "$expected_checksum" ]; then
        echo "$filename: md5sum mismatch"
        return 1
    fi

    return 0
}

function test_make_bucket()
{
    show "${FUNCNAME[0]}"

    start_time=$(get_time)
    bucket_name="mc-test-bucket-$RANDOM"
    assert_success "$start_time" "${FUNCNAME[0]}" mc_cmd mb "${SERVER_ALIAS}/${bucket_name}"
    assert_success "$start_time" "${FUNCNAME[0]}" mc_cmd rm "${SERVER_ALIAS}/${bucket_name}"

    log_success "$start_time" "${FUNCNAME[0]}"
}

function test_make_bucket_error() {
    show "${FUNCNAME[0]}"

    start_time=$(get_time)
    bucket_name="MC-test%bucket%$RANDOM"
    assert_failure "$start_time" "${FUNCNAME[0]}" mc_cmd mb "${SERVER_ALIAS}/${bucket_name}"

    log_success "$start_time" "${FUNCNAME[0]}"
}

function setup()
{
    start_time=$(get_time)
    assert_success "$start_time" "${FUNCNAME[0]}" mc_cmd mb "${SERVER_ALIAS}/${BUCKET_NAME}"
}

function teardown()
{
    start_time=$(get_time)
    assert_success "$start_time" "${FUNCNAME[0]}" mc_cmd rm --force --recursive "${SERVER_ALIAS}/${BUCKET_NAME}"
}

function test_put_object()
{
    show "${FUNCNAME[0]}"

    start_time=$(get_time)
    object_name="mc-test-object-$RANDOM"
    assert_success "$start_time" "${FUNCNAME[0]}" mc_cmd cp "${FILE_1_MB}" "${SERVER_ALIAS}/${BUCKET_NAME}/${object_name}"
    assert_success "$start_time" "${FUNCNAME[0]}" mc_cmd rm "${SERVER_ALIAS}/${BUCKET_NAME}/${object_name}"

    log_success "$start_time" "${FUNCNAME[0]}"
}

function test_put_object_error()
{
    show "${FUNCNAME[0]}"
    start_time=$(get_time)

    object_long_name=$(printf "mc-test-object-%01100d" 1)
    assert_failure "$start_time" "${FUNCNAME[0]}" mc_cmd cp "${FILE_1_MB}" "${SERVER_ALIAS}/${BUCKET_NAME}/${object_long_name}"

    log_success "$start_time" "${FUNCNAME[0]}"
}

function test_put_object_multipart()
{
    show "${FUNCNAME[0]}"

    start_time=$(get_time)
    object_name="mc-test-object-$RANDOM"
    assert_success "$start_time" "${FUNCNAME[0]}" mc_cmd cp "${FILE_65_MB}" "${SERVER_ALIAS}/${BUCKET_NAME}/${object_name}"
    assert_success "$start_time" "${FUNCNAME[0]}" mc_cmd rm "${SERVER_ALIAS}/${BUCKET_NAME}/${object_name}"

    log_success "$start_time" "${FUNCNAME[0]}"
}

function test_get_object()
{
    show "${FUNCNAME[0]}"

    start_time=$(get_time)
    object_name="mc-test-object-$RANDOM"
    assert_success "$start_time" "${FUNCNAME[0]}" mc_cmd cp "${FILE_1_MB}" "${SERVER_ALIAS}/${BUCKET_NAME}/${object_name}"
    assert_success "$start_time" "${FUNCNAME[0]}" mc_cmd cp "${SERVER_ALIAS}/${BUCKET_NAME}/${object_name}" "${object_name}.downloaded"
    assert_success "$start_time" "${FUNCNAME[0]}" check_md5sum "$FILE_1_MB_MD5SUM" "${object_name}.downloaded"
    assert_success "$start_time" "${FUNCNAME[0]}" mc_cmd rm "${object_name}.downloaded" "${SERVER_ALIAS}/${BUCKET_NAME}/${object_name}"

    log_success "$start_time" "${FUNCNAME[0]}"
}

function test_get_object_multipart()
{
    show "${FUNCNAME[0]}"

    start_time=$(get_time)
    object_name="mc-test-object-$RANDOM"
    assert_success "$start_time" "${FUNCNAME[0]}" mc_cmd cp "${FILE_65_MB}" "${SERVER_ALIAS}/${BUCKET_NAME}/${object_name}"
    assert_success "$start_time" "${FUNCNAME[0]}" mc_cmd cp "${SERVER_ALIAS}/${BUCKET_NAME}/${object_name}" "${object_name}.downloaded"
    assert_success "$start_time" "${FUNCNAME[0]}" check_md5sum "$FILE_65_MB_MD5SUM" "${object_name}.downloaded"
    assert_success "$start_time" "${FUNCNAME[0]}" mc_cmd rm "${object_name}.downloaded" "${SERVER_ALIAS}/${BUCKET_NAME}/${object_name}"

    log_success "$start_time" "${FUNCNAME[0]}"
}

function test_presigned_put_object()
{
    show "${FUNCNAME[0]}"

    start_time=$(get_time)
    object_name="mc-test-object-$RANDOM"

    out=$("${MC_CMD[@]}" --json share upload "${SERVER_ALIAS}/${BUCKET_NAME}/${object_name}")
    assert_success "$start_time" "${FUNCNAME[0]}" fail $? "unable to get presigned put object url"
    upload=$(echo "$out" | jq -r .share | sed "s|<FILE>|$FILE_1_MB|g" | sed "s|curl|curl -sS|g")
    $upload >/dev/null 2>&1
    assert_success "$start_time" "${FUNCNAME[0]}" fail $? "unable to upload $FILE_1_MB presigned put object url"

    assert_success "$start_time" "${FUNCNAME[0]}" mc_cmd cp "${SERVER_ALIAS}/${BUCKET_NAME}/${object_name}" "${object_name}.downloaded"
    assert_success "$start_time" "${FUNCNAME[0]}" check_md5sum "$FILE_65_MB_MD5SUM" "${object_name}.downloaded"
    assert_success "$start_time" "${FUNCNAME[0]}" mc_cmd rm "${object_name}.downloaded" "${SERVER_ALIAS}/${BUCKET_NAME}/${object_name}"

    log_success "$start_time" "${FUNCNAME[0]}"
}

function test_presigned_get_object()
{
    show "${FUNCNAME[0]}"

    start_time=$(get_time)
    object_name="mc-test-object-$RANDOM"
    assert_success "$start_time" "${FUNCNAME[0]}" mc_cmd cp "${FILE_1_MB}" "${SERVER_ALIAS}/${BUCKET_NAME}/${object_name}"

    out=$("${MC_CMD[@]}" --json share download "${SERVER_ALIAS}/${BUCKET_NAME}/${object_name}")
    assert_success "$start_time" "${FUNCNAME[0]}" fail $? "unable to get presigned get object url"
    download_url=$(echo "$out" | jq -r .share)
    curl --output "${object_name}.downloaded" -sS -X GET "$download_url"
    assert_success "$start_time" "${FUNCNAME[0]}" fail $? "unable to download $download_url"

    assert_success "$start_time" "${FUNCNAME[0]}" check_md5sum "$FILE_1_MB_MD5SUM" "${object_name}.downloaded"
    assert_success "$start_time" "${FUNCNAME[0]}" mc_cmd rm "${object_name}.downloaded" "${SERVER_ALIAS}/${BUCKET_NAME}/${object_name}"

    log_success "$start_time" "${FUNCNAME[0]}"
}

function test_cat_object()
{
    show "${FUNCNAME[0]}"

    start_time=$(get_time)
    object_name="mc-test-object-$RANDOM"
    assert_success "$start_time" "${FUNCNAME[0]}" mc_cmd cp "${FILE_1_MB}" "${SERVER_ALIAS}/${BUCKET_NAME}/${object_name}"
    "${MC_CMD[@]}" cat "${SERVER_ALIAS}/${BUCKET_NAME}/${object_name}" > "${object_name}.downloaded"
    assert_success "$start_time" "${FUNCNAME[0]}" fail $? "unable to download object using 'mc cat'"
    assert_success "$start_time" "${FUNCNAME[0]}" check_md5sum "$FILE_1_MB_MD5SUM" "${object_name}.downloaded"
    assert_success "$start_time" "${FUNCNAME[0]}" mc_cmd rm "${object_name}.downloaded" "${SERVER_ALIAS}/${BUCKET_NAME}/${object_name}"

    log_success "$start_time" "${FUNCNAME[0]}"
}

function test_mirror_list_objects()
{
    show "${FUNCNAME[0]}"

    start_time=$(get_time)
    bucket_name="mc-test-bucket-$RANDOM"
    object_name="mc-test-object-$RANDOM"
    assert_success "$start_time" "${FUNCNAME[0]}" mc_cmd mb "${SERVER_ALIAS}/${bucket_name}"
    assert_success "$start_time" "${FUNCNAME[0]}" mc_cmd mirror "$DATA_DIR" "${SERVER_ALIAS}/${bucket_name}"

    diff -bB <(ls "$DATA_DIR") <("${MC_CMD[@]}" --json ls "${SERVER_ALIAS}/${bucket_name}" | jq -r .key) >/dev/null 2>&1
    assert_success "$start_time" "${FUNCNAME[0]}" fail $? "mirror and list differs"

    assert_success "$start_time" "${FUNCNAME[0]}" mc_cmd rm --force --recursive "${SERVER_ALIAS}/${bucket_name}"

    log_success "$start_time" "${FUNCNAME[0]}"
}

function test_watch_object()
{
    show "${FUNCNAME[0]}"

    start_time=$(get_time)
    bucket_name="mc-test-bucket-$RANDOM"
    object_name="mc-test-object-$RANDOM"
    assert_success "$start_time" "${FUNCNAME[0]}" mc_cmd mb "${SERVER_ALIAS}/${bucket_name}"

    # start a process to watch on bucket
    "${MC_CMD[@]}" --json watch "${SERVER_ALIAS}/${bucket_name}" > "$WATCH_OUT_FILE" &
    watch_cmd_pid=$!
    sleep 1

    ( assert_success "$start_time" "${FUNCNAME[0]}" mc_cmd cp "${FILE_1_MB}" "${SERVER_ALIAS}/${bucket_name}/${object_name}" )
    rv=$?
    if [ "$rv" -ne 0 ]; then
        kill "$watch_cmd_pid"
        exit "$rv"
    fi

    sleep 1
    if ! jq -r .events.type "$WATCH_OUT_FILE" | grep -qi ObjectCreated; then
        kill "$watch_cmd_pid"
        assert_success "$start_time" "${FUNCNAME[0]}" fail 1 "ObjectCreated event not found"
    fi

    ( assert_success "$start_time" "${FUNCNAME[0]}" mc_cmd rm "${SERVER_ALIAS}/${bucket_name}/${object_name}" )
    rv=$?
    if [ "$rv" -ne 0 ]; then
        kill "$watch_cmd_pid"
        exit "$rv"
    fi

    sleep 1
    if ! jq -r .events.type "$WATCH_OUT_FILE" | grep -qi ObjectRemoved; then
        kill "$watch_cmd_pid"
        assert_success "$start_time" "${FUNCNAME[0]}" fail 1 "ObjectRemoved event not found"
    fi

    kill "$watch_cmd_pid"

    log_success "$start_time" "${FUNCNAME[0]}"
}

function run_test()
{
    test_make_bucket
    test_make_bucket_error

    setup

    test_put_object
    test_put_object_error
    test_put_object_multipart
    test_get_object
    test_get_object_multipart
    test_presigned_put_object
    test_presigned_get_object
    test_cat_object
    test_mirror_list_objects
    if [ -z "$MINT_MODE" ]; then
        test_watch_object
    fi

    teardown
}

function __init__()
{
    set -e
    # For Mint, setup is already done.  For others, setup the environment
    if [ -z "$MINT_MODE" ]; then
        mkdir -p "$WORK_DIR"
        mkdir -p "$DATA_DIR"

        # If mc executable binary is not available in current directory, use it in the path.
        if [ ! -x "$MC" ]; then
            if ! MC=$(which mc 2>/dev/null); then
                echo "'mc' executable binary not found in current directory and in path"
                exit 1
            fi
        fi
    fi

    if [ ! -x "$MC" ]; then
        echo "$MC executable binary not found"
        exit 1
    fi

    mkdir -p "$MC_CONFIG_DIR"
    MC_CMD=( "${MC}" --config-folder "$MC_CONFIG_DIR" --quiet --no-color )

    if [ ! -e "$FILE_1_MB" ]; then
        base64 /dev/urandom | head -c 1048576 >"$FILE_1_MB"
    fi

    if [ ! -e "$FILE_65_MB" ]; then
        base64 /dev/urandom | head -c 68157440 >"$FILE_65_MB"
    fi

    set -E
    set -o pipefail

    FILE_1_MB_MD5SUM="$(get_md5sum "$FILE_1_MB")"
    if [ $? -ne 0 ]; then
        echo "unable to get md5sum of $FILE_1_MB"
        exit 1
    fi

    FILE_65_MB_MD5SUM="$(get_md5sum "$FILE_65_MB")"
    if [ $? -ne 0 ]; then
        echo "unable to get md5sum of $FILE_65_MB"
        exit 1
    fi

    assert_success "$start_time" "${FUNCNAME[0]}" mc_cmd config host add "${SERVER_ALIAS}" "$ENDPOINT" "$ACCESS_KEY" "$SECRET_KEY"
    set +e
}

function main()
{
    ( run_test )
    rv=$?

    rm -fr "$MC_CONFIG_DIR" "$WATCH_OUT_FILE"
    if [ -z "$MINT_MODE" ]; then
        rm -fr "$WORK_DIR" "$DATA_DIR"
    fi

    exit "$rv"
}

__init__ "$@" 
main "$@"
