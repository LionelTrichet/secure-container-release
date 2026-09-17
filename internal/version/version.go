// Package version holds build metadata injected at link time.
package version

// Version, Commit and BuiltAt are the only mutable package variables in the
// repository. They are linker injection targets, set with
// -ldflags "-X <module>/internal/version.<Name>=<value>".
var (
	Version = "dev"
	Commit  = "unknown"
	BuiltAt = "unknown"
)

// Info is the build metadata served by /version.
type Info struct {
	Version string `json:"version"`
	Commit  string `json:"commit"`
	BuiltAt string `json:"builtAt"`
}

// Current returns the metadata the binary was linked with.
func Current() Info {
	return Info{Version: Version, Commit: Commit, BuiltAt: BuiltAt}
}
