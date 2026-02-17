#!/bin/bash

if [ -n "$TEST_DEBUG" ]; then
	set -x
fi

pkill kypello
docker rm -f $(docker ps -aq)
rm -rf /tmp/openid{1..4}

export MC_HOST_mykypello="http://kypelloadmin:kypelloadmin@localhost:22000"
# The service account used below is already present in iam configuration getting imported
export MC_HOST_mykypello1="http://dillon-service-2:dillon-service-2@localhost:22000"

# Start Kypello instance
export CI=true

if [ ! -f ./kc ]; then
	go install -ldflags "-s -w" -v github.com/kypello-io/kc@latest &&
		mv "$(go env GOPATH)/bin/kc" ./
fi

./kc -v

# Start openid server
(
	cd ./minio-iam-testing
	make docker-images
	make docker-run
	cd -
)

(kypello server --address :22000 --console-address :10000 http://localhost:22000/tmp/openid{1...4} 2>&1 >/tmp/server.log) &
./kc ready mykypello
./kc mb mykypello/test-bucket
./kc cp /etc/hosts mykypello/test-bucket

./kc idp openid add mykypello \
	config_url="http://localhost:5556/dex/.well-known/openid-configuration" \
	client_id="minio-client-app" \
	client_secret="minio-client-app-secret" \
	scopes="openid,groups,email,profile" \
	redirect_uri="http://127.0.0.1:10000/oauth_callback" \
	display_name="Login via dex1" \
	role_policy="consoleAdmin"

./kc admin service restart mykypello --json
./kc ready mykypello
./kc admin cluster iam import mykypello docs/distributed/samples/mykypello-iam-info-openid.zip

# Verify if buckets / objects accessible using service account
echo "Verifying buckets and objects access for the imported service account"

./kc ls mykypello1/ --json
BKT_COUNT=$(./kc ls mykypello1/ --json | jq '.key' | wc -l)
if [ "${BKT_COUNT}" -ne 1 ]; then
	echo "BUG: Expected no of bucket: 1, Found: ${BKT_COUNT}"
	exit 1
fi

BKT_NAME=$(./kc ls mykypello1/ --json | jq '.key' | sed 's/"//g' | sed 's\/\\g')
if [[ ${BKT_NAME} != "test-bucket" ]]; then
	echo "BUG: Expected bucket: test-bucket, Found: ${BKT_NAME}"
	exit 1
fi

./kc ls mykypello1/test-bucket
OBJ_COUNT=$(./kc ls mykypello1/test-bucket --json | jq '.key' | wc -l)
if [ "${OBJ_COUNT}" -ne 1 ]; then
	echo "BUG: Expected no of objects: 1, Found: ${OBJ_COUNT}"
	exit 1
fi

OBJ_NAME=$(./kc ls mykypello1/test-bucket --json | jq '.key' | sed 's/"//g')
if [[ ${OBJ_NAME} != "hosts" ]]; then
	echo "BUG: Expected object: hosts, Found: ${BKT_NAME}"
	exit 1
fi

# Finally kill running processes
pkill kypello
docker rm -f $(docker ps -aq)
