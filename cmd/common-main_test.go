// Copyright (c) 2015-2021 MinIO, Inc.
//
// This file is part of MinIO Object Storage stack
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

package cmd

import (
	"errors"
	"os"
	"reflect"
	"testing"
)

func Test_readFromSecret(t *testing.T) {
	testCases := []struct {
		content       string
		expectedErr   bool
		expectedValue string
	}{
		{
			"value\n",
			false,
			"value",
		},
		{
			" \t\n Hello, Gophers \n\t\r\n",
			false,
			"Hello, Gophers",
		},
	}

	for _, testCase := range testCases {
		t.Run("", func(t *testing.T) {
			tmpfile, err := os.CreateTemp(t.TempDir(), "testfile")
			if err != nil {
				t.Error(err)
			}
			tmpfile.WriteString(testCase.content)
			tmpfile.Sync()
			tmpfile.Close()

			value, err := readFromSecret(tmpfile.Name())
			if err != nil && !testCase.expectedErr {
				t.Error(err)
			}
			if err == nil && testCase.expectedErr {
				t.Error(errors.New("expected error, found success"))
			}
			if value != testCase.expectedValue {
				t.Errorf("Expected %s, got %s", testCase.expectedValue, value)
			}
		})
	}
}

func Test_minioEnvironFromFile(t *testing.T) {
	testCases := []struct {
		content      string
		expectedErr  bool
		expectedEkvs []envKV
	}{
		{
			`
export MINIO_ROOT_USER=kypello
export MINIO_ROOT_PASSWORD=kypello123`,
			false,
			[]envKV{
				{
					Key:   "MINIO_ROOT_USER",
					Value: "kypello",
				},
				{
					Key:   "MINIO_ROOT_PASSWORD",
					Value: "kypello123",
				},
			},
		},
		// Value with double quotes
		{
			`export MINIO_ROOT_USER="kypello"`,
			false,
			[]envKV{
				{
					Key:   "MINIO_ROOT_USER",
					Value: "kypello",
				},
			},
		},
		// Value with single quotes
		{
			`export MINIO_ROOT_USER='kypello'`,
			false,
			[]envKV{
				{
					Key:   "MINIO_ROOT_USER",
					Value: "kypello",
				},
			},
		},
		{
			`
MINIO_ROOT_USER=kypello
MINIO_ROOT_PASSWORD=kypello123`,
			false,
			[]envKV{
				{
					Key:   "MINIO_ROOT_USER",
					Value: "kypello",
				},
				{
					Key:   "MINIO_ROOT_PASSWORD",
					Value: "kypello123",
				},
			},
		},
		{
			`
export MINIO_ROOT_USERkypello
export MINIO_ROOT_PASSWORD=kypello123`,
			true,
			nil,
		},
		{
			`
# simple comment
# MINIO_ROOT_USER=kypelloadmin
# MINIO_ROOT_PASSWORD=kypelloadmin
MINIO_ROOT_USER=kypello
MINIO_ROOT_PASSWORD=kypello123`,
			false,
			[]envKV{
				{
					Key:   "MINIO_ROOT_USER",
					Value: "kypello",
				},
				{
					Key:   "MINIO_ROOT_PASSWORD",
					Value: "kypello123",
				},
			},
		},
	}
	for _, testCase := range testCases {
		t.Run("", func(t *testing.T) {
			tmpfile, err := os.CreateTemp(t.TempDir(), "testfile")
			if err != nil {
				t.Error(err)
			}
			tmpfile.WriteString(testCase.content)
			tmpfile.Sync()
			tmpfile.Close()

			ekvs, err := minioEnvironFromFile(tmpfile.Name())
			if err != nil && !testCase.expectedErr {
				t.Error(err)
			}
			if err == nil && testCase.expectedErr {
				t.Error(errors.New("expected error, found success"))
			}

			if len(ekvs) != len(testCase.expectedEkvs) {
				t.Errorf("expected %v keys, got %v keys", len(testCase.expectedEkvs), len(ekvs))
			}

			if !reflect.DeepEqual(ekvs, testCase.expectedEkvs) {
				t.Errorf("expected %v, got %v", testCase.expectedEkvs, ekvs)
			}
		})
	}
}
