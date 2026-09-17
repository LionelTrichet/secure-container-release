package server

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/LionelTrichet/secure-container-release/internal/version"
)

func testInfo() version.Info {
	return version.Info{
		Version: "9.8.7",
		Commit:  "fedcba9876543210fedcba9876543210fedcba98",
		BuiltAt: "2026-02-03T04:05:06Z",
	}
}

func serve(t *testing.T, method, path string) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	New(testInfo()).ServeHTTP(rec, httptest.NewRequest(method, path, nil))
	return rec
}

func requireJSON(t *testing.T, rec *httptest.ResponseRecorder, target any) {
	t.Helper()
	if got := rec.Header().Get("Content-Type"); got != "application/json" {
		t.Fatalf("Content-Type = %q, want application/json", got)
	}
	if err := json.Unmarshal(rec.Body.Bytes(), target); err != nil {
		t.Fatalf("invalid JSON %q: %v", rec.Body.String(), err)
	}
}

func TestHealthz(t *testing.T) {
	rec := serve(t, http.MethodGet, "/healthz")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	var body map[string]string
	requireJSON(t, rec, &body)
	if len(body) != 1 || body["status"] != "ok" {
		t.Fatalf(`body = %v, want {"status":"ok"}`, body)
	}
}

func TestVersion(t *testing.T) {
	rec := serve(t, http.MethodGet, "/version")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	var got version.Info
	requireJSON(t, rec, &got)
	if want := testInfo(); got != want {
		t.Fatalf("version = %+v, want %+v", got, want)
	}
}

func TestVersionIsExactlyTheInjectedMetadata(t *testing.T) {
	rec := serve(t, http.MethodGet, "/version")
	var raw map[string]string
	requireJSON(t, rec, &raw)
	info := testInfo()
	want := map[string]string{
		"version": info.Version,
		"commit":  info.Commit,
		"builtAt": info.BuiltAt,
	}
	if len(raw) != len(want) {
		t.Fatalf("fields = %v, want exactly %v", raw, want)
	}
	for key, value := range want {
		if raw[key] != value {
			t.Fatalf("%s = %q, want %q", key, raw[key], value)
		}
	}
}

func TestNonGetMethodsAreRejected(t *testing.T) {
	for _, path := range []string{"/healthz", "/version"} {
		for _, method := range []string{http.MethodPost, http.MethodPut, http.MethodDelete, http.MethodHead} {
			rec := serve(t, method, path)
			if rec.Code != http.StatusMethodNotAllowed {
				t.Errorf("%s %s status = %d, want 405", method, path, rec.Code)
			}
			if got := rec.Header().Get("Allow"); got != http.MethodGet {
				t.Errorf("%s %s Allow = %q, want GET", method, path, got)
			}
		}
	}
}

func TestUnknownRoute(t *testing.T) {
	for _, path := range []string{"/", "/unknown", "/healthz/", "/version/extra", "/metrics"} {
		if rec := serve(t, http.MethodGet, path); rec.Code != http.StatusNotFound {
			t.Errorf("GET %s status = %d, want 404", path, rec.Code)
		}
	}
}
