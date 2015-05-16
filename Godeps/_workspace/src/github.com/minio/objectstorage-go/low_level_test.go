/*
 * Minimal object storage library (C) 2015 Minio, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package objectstorage_test

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
)

var robotsTxtHandler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Last-Modified", "sometime")
	fmt.Fprintf(w, "User-agent: go\nDisallow: /something/")
})

func TestNewRequest(t *testing.T) {
}

func TestResponseToError(t *testing.T) {
}

func TestCommonFunctions(t *testing.T) {
}

func TestLowLevelBucketOperations(t *testing.T) {
	ts := httptest.NewServer(robotsTxtHandler)
	defer ts.Close()
}

func TestLowLevelObjectOperations(t *testing.T) {
	ts := httptest.NewServer(robotsTxtHandler)
	defer ts.Close()
}

func TestLowLevelMultiPartOperations(t *testing.T) {
	ts := httptest.NewServer(robotsTxtHandler)
	defer ts.Close()
}