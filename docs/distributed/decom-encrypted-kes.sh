#!/bin/bash

if [ -n "$TEST_DEBUG" ]; then
	set -x
fi

pkill kypello
pkill kes
rm -rf /tmp/xl

if [ ! -f ./mc ]; then
	wget --quiet -O mc https://dl.minio.io/client/mc/release/linux-amd64/mc &&
		chmod +x mc
fi

if [ ! -f ./kes ]; then
	wget --quiet -O kes https://github.com/minio/kes/releases/latest/download/kes-linux-amd64 &&
		chmod +x kes
fi

if ! openssl version &>/dev/null; then
	apt install openssl || sudo apt install opensssl
fi

# Start KES Server
(./kes server --dev 2>&1 >kes-server.log) &
kes_pid=$!
sleep 5s
API_KEY=$(grep "API Key" <kes-server.log | awk -F" " '{print $3}')
(openssl s_client -connect 127.0.0.1:7373 2>/dev/null 1>public.crt)

export CI=true
export MINIO_KMS_KES_ENDPOINT=https://127.0.0.1:7373
export MINIO_KMS_KES_API_KEY="${API_KEY}"
export MINIO_KMS_KES_KEY_NAME=kypello-default-key
export MINIO_KMS_KES_CAPATH=public.crt
export MC_HOST_mykypello="http://kypelloadmin:kypelloadmin@localhost:9000/"

(kypello server http://localhost:9000/tmp/xl/{1...10}/disk{0...1} 2>&1 >/dev/null) &
pid=$!

./mc ready mykypello

./mc admin user add mykypello/ kypello123 kypello123
./mc admin user add mykypello/ kypello12345 kypello12345

./mc admin policy create mykypello/ rw ./docs/distributed/rw.json
./mc admin policy create mykypello/ lake ./docs/distributed/rw.json

./mc admin policy attach mykypello/ rw --user=kypello123
./mc admin policy attach mykypello/ lake --user=kypello12345

./mc mb -l mykypello/versioned
./mc mb -l mykypello/versioned-1

./mc encrypt set sse-s3 mykypello/versioned
./mc encrypt set sse-kms kypello-default-key mykypello/versioned-1

./mc mirror internal mykypello/versioned/ --quiet >/dev/null
./mc mirror internal mykypello/versioned-1/ --quiet >/dev/null

## Soft delete (creates delete markers)
./mc rm -r --force mykypello/versioned >/dev/null
./mc rm -r --force mykypello/versioned-1 >/dev/null

## mirror again to create another set of version on top
./mc mirror internal mykypello/versioned/ --quiet >/dev/null
./mc mirror internal mykypello/versioned-1/ --quiet >/dev/null

expected_checksum=$(./mc cat internal/dsync/drwmutex.go | md5sum)

user_count=$(./mc admin user list mykypello/ | wc -l)
policy_count=$(./mc admin policy list mykypello/ | wc -l)

kill $pid

(kypello server http://localhost:9000/tmp/xl/{1...10}/disk{0...1} http://localhost:9001/tmp/xl/{11...30}/disk{0...3} 2>&1 >/tmp/expanded_1.log) &
pid_1=$!

(kypello server --address ":9001" http://localhost:9000/tmp/xl/{1...10}/disk{0...1} http://localhost:9001/tmp/xl/{11...30}/disk{0...3} 2>&1 >/tmp/expanded_2.log) &
pid_2=$!

./mc ready mykypello

expanded_user_count=$(./mc admin user list mykypello/ | wc -l)
expanded_policy_count=$(./mc admin policy list mykypello/ | wc -l)

if [ "$user_count" -ne "$expanded_user_count" ]; then
	echo "BUG: original user count differs from expanded setup"
	exit 1
fi

if [ "$policy_count" -ne "$expanded_policy_count" ]; then
	echo "BUG: original policy count  differs from expanded setup"
	exit 1
fi

./mc version info mykypello/versioned | grep -q "versioning is enabled"
ret=$?
if [ $ret -ne 0 ]; then
	echo "expected versioning enabled after expansion"
	exit 1
fi

./mc encrypt info mykypello/versioned | grep -q "Auto encryption 'sse-s3' is enabled"
ret=$?
if [ $ret -ne 0 ]; then
	echo "expected encryption enabled after expansion"
	exit 1
fi

./mc version info mykypello/versioned-1 | grep -q "versioning is enabled"
ret=$?
if [ $ret -ne 0 ]; then
	echo "expected versioning enabled after expansion"
	exit 1
fi

./mc encrypt info mykypello/versioned-1 | grep -q "Auto encryption 'sse-kms' is enabled"
ret=$?
if [ $ret -ne 0 ]; then
	echo "expected encryption enabled after expansion"
	exit 1
fi

./mc mirror cmd mykypello/versioned/ --quiet >/dev/null
./mc mirror cmd mykypello/versioned-1/ --quiet >/dev/null

./mc ls -r mykypello/versioned/ >expanded_ns.txt
./mc ls -r --versions mykypello/versioned/ >expanded_ns_versions.txt
./mc ls -r mykypello/versioned-1/ >expanded_ns_1.txt
./mc ls -r --versions mykypello/versioned-1/ >expanded_ns_versions_1.txt

./mc admin decom start mykypello/ http://localhost:9000/tmp/xl/{1...10}/disk{0...1}

until $(./mc admin decom status mykypello/ | grep -q Complete); do
	echo "waiting for decom to finish..."
	sleep 1s
done

kill $pid_1
kill $pid_2

sleep 5s

(kypello server --address ":9001" http://localhost:9001/tmp/xl/{11...30}/disk{0...3} 2>&1 >/tmp/removed.log) &
pid=$!

sleep 30s

export MC_HOST_mykypello="http://kypelloadmin:kypelloadmin@localhost:9001/"

./mc ready mykypello

decom_user_count=$(./mc admin user list mykypello/ | wc -l)
decom_policy_count=$(./mc admin policy list mykypello/ | wc -l)

if [ "$user_count" -ne "$decom_user_count" ]; then
	echo "BUG: original user count differs after decommission"
	exit 1
fi

if [ "$policy_count" -ne "$decom_policy_count" ]; then
	echo "BUG: original policy count differs after decommission"
	exit 1
fi

./mc version info mykypello/versioned | grep -q "versioning is enabled"
ret=$?
if [ $ret -ne 0 ]; then
	echo "BUG: expected versioning enabled after decommission"
	exit 1
fi

./mc encrypt info mykypello/versioned | grep -q "Auto encryption 'sse-s3' is enabled"
ret=$?
if [ $ret -ne 0 ]; then
	echo "BUG: expected encryption enabled after expansion"
	exit 1
fi

./mc version info mykypello/versioned-1 | grep -q "versioning is enabled"
ret=$?
if [ $ret -ne 0 ]; then
	echo "BUG: expected versioning enabled after decommission"
	exit 1
fi

./mc encrypt info mykypello/versioned-1 | grep -q "Auto encryption 'sse-kms' is enabled"
ret=$?
if [ $ret -ne 0 ]; then
	echo "BUG: expected encryption enabled after expansion"
	exit 1
fi

got_checksum=$(./mc cat mykypello/versioned/dsync/drwmutex.go | md5sum)
if [ "${expected_checksum}" != "${got_checksum}" ]; then
	echo "BUG: decommission failed on encrypted objects: expected ${expected_checksum} got ${got_checksum}"
	exit 1
fi

got_checksum_1=$(./mc cat mykypello/versioned-1/dsync/drwmutex.go | md5sum)
if [ "${expected_checksum}" != "${got_checksum_1}" ]; then
	echo "BUG: decommission failed on encrypted objects: expected ${expected_checksum} got ${got_checksum_1}"
	exit 1
fi

./mc ls -r mykypello/versioned >decommissioned_ns.txt
./mc ls -r --versions mykypello/versioned >decommissioned_ns_versions.txt
./mc ls -r mykypello/versioned-1 >decommissioned_ns_1.txt
./mc ls -r --versions mykypello/versioned-1 >decommissioned_ns_versions_1.txt

out=$(diff -qpruN expanded_ns.txt decommissioned_ns.txt)
ret=$?
if [ $ret -ne 0 ]; then
	echo "BUG: expected no missing entries after decommission: $out"
	exit 1
fi

out=$(diff -qpruN expanded_ns_versions.txt decommissioned_ns_versions.txt)
ret=$?
if [ $ret -ne 0 ]; then
	echo "BUG: expected no missing entries after decommission: $out"
	exit 1
fi

out1=$(diff -qpruN expanded_ns_1.txt decommissioned_ns_1.txt)
ret=$?
if [ $ret -ne 0 ]; then
	echo "BUG: expected no missing entries after decommission: $out1"
	exit 1
fi

out1=$(diff -qpruN expanded_ns_versions_1.txt decommissioned_ns_versions_1.txt)
ret=$?
if [ $ret -ne 0 ]; then
	echo "BUG: expected no missing entries after decommission: $out1"
	exit 1
fi

./s3-check-md5 -versions -access-key kypelloadmin -secret-key kypelloadmin -endpoint http://127.0.0.1:9001/ -bucket versioned
./s3-check-md5 -versions -access-key kypelloadmin -secret-key kypelloadmin -endpoint http://127.0.0.1:9001/ -bucket versioned-1

kill $pid
kill $kes_pid
