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
	"fmt"
	"math/rand"
	"testing"
	"time"

	"github.com/dustin/go-humanize"
	xhttp "github.com/kypello-io/kypello/internal/http"
)

func TestIsXLMetaErasureInfoValid(t *testing.T) {
	tests := []struct {
		name   int
		data   int
		parity int
		want   bool
	}{
		{1, 5, 6, false},
		{2, 5, 5, true},
		{3, 0, 5, false},
		{3, -1, 5, false},
		{4, 5, -1, false},
		{5, 5, 0, true},
		{6, 5, 0, true},
		{7, 5, 4, true},
	}
	for _, tt := range tests {
		if got := isXLMetaErasureInfoValid(tt.data, tt.parity); got != tt.want {
			t.Errorf("Test %d: Expected %v but received %v -> %#v", tt.name, got, tt.want, tt)
		}
	}
}

// Test the predicted part size from the part index
func TestGetPartSizeFromIdx(t *testing.T) {
	// Create test cases
	testCases := []struct {
		totalSize    int64
		partSize     int64
		partIndex    int
		expectedSize int64
	}{
		// Total size is zero
		{0, 10, 1, 0},
		// part size 2MiB, total size 4MiB
		{4 * humanize.MiByte, 2 * humanize.MiByte, 1, 2 * humanize.MiByte},
		{4 * humanize.MiByte, 2 * humanize.MiByte, 2, 2 * humanize.MiByte},
		{4 * humanize.MiByte, 2 * humanize.MiByte, 3, 0},
		// part size 2MiB, total size 5MiB
		{5 * humanize.MiByte, 2 * humanize.MiByte, 1, 2 * humanize.MiByte},
		{5 * humanize.MiByte, 2 * humanize.MiByte, 2, 2 * humanize.MiByte},
		{5 * humanize.MiByte, 2 * humanize.MiByte, 3, 1 * humanize.MiByte},
		{5 * humanize.MiByte, 2 * humanize.MiByte, 4, 0},
	}

	for i, testCase := range testCases {
		s, err := calculatePartSizeFromIdx(GlobalContext, testCase.totalSize, testCase.partSize, testCase.partIndex)
		if err != nil {
			t.Errorf("Test %d: Expected to pass but failed. %s", i+1, err)
		}
		if err == nil && s != testCase.expectedSize {
			t.Errorf("Test %d: The calculated part size is incorrect: expected = %d, found = %d\n", i+1, testCase.expectedSize, s)
		}
	}

	testCasesFailure := []struct {
		totalSize int64
		partSize  int64
		partIndex int
		err       error
	}{
		// partSize is 0, returns error.
		{10, 0, 1, errPartSizeZero},
		// partIndex is 0, returns error.
		{10, 1, 0, errPartSizeIndex},
		// Total size is -1, returns error.
		{-2, 10, 1, errInvalidArgument},
	}

	for i, testCaseFailure := range testCasesFailure {
		_, err := calculatePartSizeFromIdx(GlobalContext, testCaseFailure.totalSize, testCaseFailure.partSize, testCaseFailure.partIndex)
		if err == nil {
			t.Errorf("Test %d: Expected to failed but passed. %s", i+1, err)
		}
		if err != nil && err != testCaseFailure.err {
			t.Errorf("Test %d: Expected err %s, but got %s", i+1, testCaseFailure.err, err)
		}
	}
}

func BenchmarkXlMetaV2Shallow(b *testing.B) {
	fi := FileInfo{
		Volume:           "volume",
		Name:             "object-name",
		VersionID:        "756100c6-b393-4981-928a-d49bbc164741",
		IsLatest:         true,
		Deleted:          false,
		TransitionStatus: "PENDING",
		DataDir:          "bffea160-ca7f-465f-98bc-9b4f1c3ba1ef",
		XLV1:             false,
		ModTime:          time.Now(),
		Size:             1234456,
		Mode:             0,
		Metadata: map[string]string{
			xhttp.AmzRestore:                 "FAILED",
			xhttp.ContentMD5:                 mustGetUUID(),
			xhttp.AmzBucketReplicationStatus: "PENDING",
			xhttp.ContentType:                "application/json",
		},
		Parts: []ObjectPartInfo{
			{
				Number:     1,
				Size:       1234345,
				ActualSize: 1234345,
			},
			{
				Number:     2,
				Size:       1234345,
				ActualSize: 1234345,
			},
		},
		Erasure: ErasureInfo{
			Algorithm:    ReedSolomon.String(),
			DataBlocks:   4,
			ParityBlocks: 2,
			BlockSize:    10000,
			Index:        1,
			Distribution: []int{1, 2, 3, 4, 5, 6, 7, 8},
			Checksums: []ChecksumInfo{
				{
					PartNumber: 1,
					Algorithm:  HighwayHash256S,
					Hash:       nil,
				},
				{
					PartNumber: 2,
					Algorithm:  HighwayHash256S,
					Hash:       nil,
				},
			},
		},
	}
	for _, size := range []int{1, 10, 1000, 100_000} {
		b.Run(fmt.Sprint(size, "-versions"), func(b *testing.B) {
			var xl xlMetaV2
			ids := make([]string, size)
			for i := range size {
				fi.VersionID = mustGetUUID()
				fi.DataDir = mustGetUUID()
				ids[i] = fi.VersionID
				fi.ModTime = fi.ModTime.Add(-time.Second)
				xl.AddVersion(fi)
			}
			// Encode all. This is used for benchmarking.
			enc, err := xl.AppendTo(nil)
			if err != nil {
				b.Fatal(err)
			}
			b.Logf("Serialized size: %d bytes", len(enc))
			rng := rand.New(rand.NewSource(0))
			dump := make([]byte, len(enc))
			b.Run("UpdateObjectVersion", func(b *testing.B) {
				b.SetBytes(int64(size))
				b.ResetTimer()
				b.ReportAllocs()
				for b.Loop() {
					// Load...
					xl = xlMetaV2{}
					err := xl.Load(enc)
					if err != nil {
						b.Fatal(err)
					}
					// Update modtime for resorting...
					fi.ModTime = fi.ModTime.Add(-time.Second)
					// Update a random version.
					fi.VersionID = ids[rng.Intn(size)]
					// Update...
					err = xl.UpdateObjectVersion(fi)
					if err != nil {
						b.Fatal(err)
					}
					// Save...
					dump, err = xl.AppendTo(dump[:0])
					if err != nil {
						b.Fatal(err)
					}
				}
			})
			b.Run("DeleteVersion", func(b *testing.B) {
				b.SetBytes(int64(size))
				b.ResetTimer()
				b.ReportAllocs()
				for b.Loop() {
					// Load...
					xl = xlMetaV2{}
					err := xl.Load(enc)
					if err != nil {
						b.Fatal(err)
					}
					// Update a random version.
					fi.VersionID = ids[rng.Intn(size)]
					// Delete...
					_, err = xl.DeleteVersion(fi)
					if err != nil {
						b.Fatal(err)
					}
					// Save...
					dump, err = xl.AppendTo(dump[:0])
					if err != nil {
						b.Fatal(err)
					}
				}
			})
			b.Run("AddVersion", func(b *testing.B) {
				b.SetBytes(int64(size))
				b.ResetTimer()
				b.ReportAllocs()
				for b.Loop() {
					// Load...
					xl = xlMetaV2{}
					err := xl.Load(enc)
					if err != nil {
						b.Fatal(err)
					}
					// Update modtime for resorting...
					fi.ModTime = fi.ModTime.Add(-time.Second)
					// Update a random version.
					fi.VersionID = mustGetUUID()
					// Add...
					err = xl.AddVersion(fi)
					if err != nil {
						b.Fatal(err)
					}
					// Save...
					dump, err = xl.AppendTo(dump[:0])
					if err != nil {
						b.Fatal(err)
					}
				}
			})
			b.Run("ToFileInfo", func(b *testing.B) {
				b.SetBytes(int64(size))
				b.ResetTimer()
				b.ReportAllocs()
				for b.Loop() {
					// Load...
					xl = xlMetaV2{}
					err := xl.Load(enc)
					if err != nil {
						b.Fatal(err)
					}
					// List...
					_, err = xl.ToFileInfo("volume", "path", ids[rng.Intn(size)], false, true)
					if err != nil {
						b.Fatal(err)
					}
				}
			})
			b.Run("ListVersions", func(b *testing.B) {
				b.SetBytes(int64(size))
				b.ResetTimer()
				b.ReportAllocs()
				for b.Loop() {
					// Load...
					xl = xlMetaV2{}
					err := xl.Load(enc)
					if err != nil {
						b.Fatal(err)
					}
					// List...
					_, err = xl.ListVersions("volume", "path", true)
					if err != nil {
						b.Fatal(err)
					}
				}
			})
			b.Run("ToFileInfoNew", func(b *testing.B) {
				b.SetBytes(int64(size))
				b.ResetTimer()
				b.ReportAllocs()
				for b.Loop() {
					buf, _, _ := isIndexedMetaV2(enc)
					if buf == nil {
						b.Fatal("buf == nil")
					}
					_, err = buf.ToFileInfo("volume", "path", ids[rng.Intn(size)], true)
					if err != nil {
						b.Fatal(err)
					}
				}
			})
			b.Run("ListVersionsNew", func(b *testing.B) {
				b.SetBytes(int64(size))
				b.ResetTimer()
				b.ReportAllocs()
				for b.Loop() {
					buf, _, _ := isIndexedMetaV2(enc)
					if buf == nil {
						b.Fatal("buf == nil")
					}
					_, err = buf.ListVersions("volume", "path", true)
					if err != nil {
						b.Fatal(err)
					}
				}
			})
		})
	}
}
