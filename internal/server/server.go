// Package server implements the HTTP handlers of the release workload.
//
// The workload has no product logic. It exists as a deterministic OCI release
// target and exposes its build identity so a published image can be checked
// against the source commit that produced it.
package server

import (
	"encoding/json"
	"net/http"

	"github.com/LionelTrichet/secure-container-release/internal/version"
)

// New returns the handler for /healthz and /version.
func New(info version.Info) http.Handler {
	mux := http.NewServeMux()
	mux.Handle("/healthz", getOnly(func(w http.ResponseWriter) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	}))
	mux.Handle("/version", getOnly(func(w http.ResponseWriter) {
		writeJSON(w, http.StatusOK, info)
	}))
	return mux
}

// getOnly answers 405 with "Allow: GET" for any other method, including HEAD.
func getOnly(respond func(w http.ResponseWriter)) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.Header().Set("Allow", http.MethodGet)
			http.Error(w, http.StatusText(http.StatusMethodNotAllowed), http.StatusMethodNotAllowed)
			return
		}
		respond(w)
	})
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	// The status line is already sent; a failure here means the client went
	// away and there is nothing left to report to it.
	_ = json.NewEncoder(w).Encode(body)
}
