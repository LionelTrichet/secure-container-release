package version

import (
	"encoding/json"
	"testing"
)

func TestDefaults(t *testing.T) {
	got := Current()
	want := Info{Version: "dev", Commit: "unknown", BuiltAt: "unknown"}
	if got != want {
		t.Fatalf("Current() = %+v, want %+v", got, want)
	}
}

func TestCurrentReflectsLinkerVariables(t *testing.T) {
	saved := Info{Version: Version, Commit: Commit, BuiltAt: BuiltAt}
	t.Cleanup(func() {
		Version, Commit, BuiltAt = saved.Version, saved.Commit, saved.BuiltAt
	})

	Version = "0.1.0"
	Commit = "0123456789abcdef0123456789abcdef01234567"
	BuiltAt = "2026-01-02T03:04:05+00:00"

	want := Info{
		Version: "0.1.0",
		Commit:  "0123456789abcdef0123456789abcdef01234567",
		BuiltAt: "2026-01-02T03:04:05+00:00",
	}
	if got := Current(); got != want {
		t.Fatalf("Current() = %+v, want %+v", got, want)
	}
}

func TestJSONFieldNames(t *testing.T) {
	data, err := json.Marshal(Info{Version: "v", Commit: "c", BuiltAt: "b"})
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if got, want := string(data), `{"version":"v","commit":"c","builtAt":"b"}`; got != want {
		t.Fatalf("JSON = %s, want %s", got, want)
	}
}
