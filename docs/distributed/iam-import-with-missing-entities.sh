#!/bin/bash

if [ -n "$TEST_DEBUG" ]; then
	set -x
fi

pkill kypello
docker rm -f $(docker ps -aq)
rm -rf /tmp/ldap{1..4}
rm -rf /tmp/ldap1{1..4}

go install -ldflags "-s -w" -v github.com/kypello-io/kc@latest
mv "$(go env GOPATH)/bin/kc" ./
./kc -v

# Start LDAP server
echo "Copying docs/distributed/samples/bootstrap-complete.ldif => minio-iam-testing/ldap/50-bootstrap.ldif"
cp docs/distributed/samples/bootstrap-complete.ldif minio-iam-testing/ldap/50-bootstrap.ldif || exit 1
cd ./minio-iam-testing
make docker-images
make docker-run
cd -

export MC_HOST_mykypello="http://kypelloadmin:kypelloadmin@localhost:22000"
export MC_HOST_mykypello1="http://kypelloadmin:kypelloadmin@localhost:24000"

# Start Kypello instance
export CI=true
(kypello server --address :22000 --console-address :10000 http://localhost:22000/tmp/ldap{1...4} 2>&1 >/dev/null) &
sleep 30
./kc ready mykypello

./kc idp ldap add mykypello server_addr=localhost:389 server_insecure=on \
	lookup_bind_dn=cn=admin,dc=min,dc=io lookup_bind_password=admin \
	user_dn_search_base_dn=dc=min,dc=io user_dn_search_filter="(uid=%s)" \
	group_search_base_dn=ou=swengg,dc=min,dc=io group_search_filter="(&(objectclass=groupOfNames)(member=%d))"

./kc admin service restart mykypello --json
./kc ready mykypello
./kc admin cluster iam import mykypello docs/distributed/samples/mykypello-iam-info.zip
sleep 10

# Verify the list of users and service accounts from the import
./kc admin user list mykypello
USER_COUNT=$(./kc admin user list mykypello | wc -l)
if [ "${USER_COUNT}" -ne 2 ]; then
	echo "BUG: Expected no of users: 2 Found: ${USER_COUNT}"
	exit 1
fi
./kc admin user svcacct list mykypello "uid=bobfisher,ou=people,ou=hwengg,dc=min,dc=io" --json
SVCACCT_COUNT_1=$(./kc admin user svcacct list mykypello "uid=bobfisher,ou=people,ou=hwengg,dc=min,dc=io" --json | jq '.accessKey' | wc -l)
if [ "${SVCACCT_COUNT_1}" -ne 2 ]; then
	echo "BUG: Expected svcacct count for 'uid=bobfisher,ou=people,ou=hwengg,dc=min,dc=io': 2. Found: ${SVCACCT_COUNT_1}"
	exit 1
fi
./kc admin user svcacct list mykypello "uid=dillon,ou=people,ou=swengg,dc=min,dc=io" --json
SVCACCT_COUNT_2=$(./kc admin user svcacct list mykypello "uid=dillon,ou=people,ou=swengg,dc=min,dc=io" --json | jq '.accessKey' | wc -l)
if [ "${SVCACCT_COUNT_2}" -ne 2 ]; then
	echo "BUG: Expected svcacct count for 'uid=dillon,ou=people,ou=swengg,dc=min,dc=io': 2. Found: ${SVCACCT_COUNT_2}"
	exit 1
fi

# Kill MinIO and LDAP to start afresh with missing groups/DN
pkill kypello
docker rm -f $(docker ps -aq)
rm -rf /tmp/ldap{1..4}

# Deploy the LDAP config witg missing groups/DN
echo "Copying docs/distributed/samples/bootstrap-partial.ldif => minio-iam-testing/ldap/50-bootstrap.ldif"
cp docs/distributed/samples/bootstrap-partial.ldif minio-iam-testing/ldap/50-bootstrap.ldif || exit 1
cd ./minio-iam-testing
make docker-images
make docker-run
cd -

(kypello server --address ":24000" --console-address :10000 http://localhost:24000/tmp/ldap1{1...4} 2>&1 >/dev/null) &
sleep 30
./kc ready mykypello1

./kc idp ldap add mykypello1 server_addr=localhost:389 server_insecure=on \
	lookup_bind_dn=cn=admin,dc=min,dc=io lookup_bind_password=admin \
	user_dn_search_base_dn=dc=min,dc=io user_dn_search_filter="(uid=%s)" \
	group_search_base_dn=ou=hwengg,dc=min,dc=io group_search_filter="(&(objectclass=groupOfNames)(member=%d))"

./kc admin service restart mykypello1 --json
./kc ready mykypello1
./kc admin cluster iam import mykypello1 docs/distributed/samples/mykypello-iam-info.zip
sleep 10

# Verify the list of users and service accounts from the import
./kc admin user list mykypello1
USER_COUNT=$(./kc admin user list mykypello1 | wc -l)
if [ "${USER_COUNT}" -ne 1 ]; then
	echo "BUG: Expected no of users: 1 Found: ${USER_COUNT}"
	exit 1
fi
./kc admin user svcacct list mykypello1 "uid=bobfisher,ou=people,ou=hwengg,dc=min,dc=io" --json
SVCACCT_COUNT_1=$(./kc admin user svcacct list mykypello1 "uid=bobfisher,ou=people,ou=hwengg,dc=min,dc=io" --json | jq '.accessKey' | wc -l)
if [ "${SVCACCT_COUNT_1}" -ne 2 ]; then
	echo "BUG: Expected svcacct count for 'uid=bobfisher,ou=people,ou=hwengg,dc=min,dc=io': 2. Found: ${SVCACCT_COUNT_1}"
	exit 1
fi
./kc admin user svcacct list mykypello1 "uid=dillon,ou=people,ou=swengg,dc=min,dc=io" --json
SVCACCT_COUNT_2=$(./kc admin user svcacct list mykypello1 "uid=dillon,ou=people,ou=swengg,dc=min,dc=io" --json | jq '.accessKey' | wc -l)
if [ "${SVCACCT_COUNT_2}" -ne 0 ]; then
	echo "BUG: Expected svcacct count for 'uid=dillon,ou=people,ou=swengg,dc=min,dc=io': 0. Found: ${SVCACCT_COUNT_2}"
	exit 1
fi

# Finally kill running processes
pkill kypello
docker rm -f $(docker ps -aq)
