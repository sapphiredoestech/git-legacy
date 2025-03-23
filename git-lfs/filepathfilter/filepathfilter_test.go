package filepathfilter

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestPatternMatch(t *testing.T) {
	assertPatternMatch(t, "*",
		"a",
		"a.a",
		"a/b",
		"a/b.b",
		"a/b/c",
		"a/b/c.c",
	)

	assertPatternMatch(t, "filename.txt", "filename.txt")
	assertPatternMatch(t, "*.txt", "filename.txt")
	refutePatternMatch(t, "*.tx", "filename.txt")
	assertPatternMatch(t, "f*.txt", "filename.txt")
	refutePatternMatch(t, "g*.txt", "filename.txt")
	assertPatternMatch(t, "file*", "filename.txt")
	refutePatternMatch(t, "file", "filename.txt")

	// With no path separators, should match in subfolders
	assertPatternMatch(t, "*.txt", "sub/filename.txt")
	refutePatternMatch(t, "*.tx", "sub/filename.txt")
	assertPatternMatch(t, "f*.txt", "sub/filename.txt")
	refutePatternMatch(t, "g*.txt", "sub/filename.txt")
	assertPatternMatch(t, "file*", "sub/filename.txt")
	refutePatternMatch(t, "file", "sub/filename.txt")

	// matches only in subdir
	assertPatternMatch(t, "sub/*.txt", "sub/filename.txt")
	refutePatternMatch(t, "sub/*.txt",
		"top/sub/filename.txt",
		"sub/filename.dat",
		"other/filename.txt",
	)

	// Needs wildcard for exact filename
	assertPatternMatch(t, "**/filename.txt", "sub/sub/sub/filename.txt")

	// Should not match dots to subparts
	refutePatternMatch(t, "*.ign", "sub/shouldignoreme.txt")

	// Path specific
	assertPatternMatch(t, "sub",
		"sub",
		"top/sub",
	)
	refutePatternMatch(t, "sub",
		"subfilename.txt",
		"sub/filename.txt",
		"top/sub/filename.txt",
	)

	assertPatternMatch(t, "/sub",
		"sub",
	)
	refutePatternMatch(t, "/sub",
		"subfilename.txt",
		"sub/filename.txt",
		"top/sub",
		"top/sub/filename.txt",
	)

	refutePatternMatch(t, "sub/",
		"sub",
		"subfilename.txt",
		"sub/filename.txt",
		"top/sub",
		"top/sub/filename.txt",
	)
	assertPatternMatchIgnore(t, "sub/",
		"sub/",
		"sub/filename.txt",
		"top/sub/",
		"top/sub/filename.txt",
	)
	refutePatternMatchIgnore(t, "sub/",
		"subfilename.txt",
	)

	refutePatternMatch(t, "/sub/",
		"sub",
		"subfilename.txt",
		"sub/filename.txt",
		"top/sub",
		"top/sub/filename.txt",
	)
	assertPatternMatchIgnore(t, "/sub/",
		"sub/",
		"sub/filename.txt",
	)
	refutePatternMatchIgnore(t, "/sub/",
		"subfilename.txt",
		"top/sub",
		"top/sub/filename.txt",
	)

	// Absolute
	assertPatternMatch(t, "*.dat", "/path/to/sub/.git/test.dat")
	assertPatternMatch(t, "**/.git", "/path/to/sub/.git")
}

func assertPatternMatch(t *testing.T, pattern string, filenames ...string) {
	p := NewPattern(pattern, GitAttributes)
	for _, filename := range filenames {
		assert.True(t, p.Match(filename), "%q should match pattern %q", filename, pattern)
	}
}

func assertPatternMatchIgnore(t *testing.T, pattern string, filenames ...string) {
	p := NewPattern(pattern, GitIgnore)
	for _, filename := range filenames {
		assert.True(t, p.Match(filename), "%q should match pattern %q", filename, pattern)
	}
}

func refutePatternMatch(t *testing.T, pattern string, filenames ...string) {
	p := NewPattern(pattern, GitAttributes)
	for _, filename := range filenames {
		assert.False(t, p.Match(filename), "%q should not match pattern %q", filename, pattern)
	}
}

func refutePatternMatchIgnore(t *testing.T, pattern string, filenames ...string) {
	p := NewPattern(pattern, GitIgnore)
	for _, filename := range filenames {
		assert.False(t, p.Match(filename), "%q should not match pattern %q", filename, pattern)
	}
}

type filterTest struct {
	expectedResult  bool
	expectedPattern string
	includes        []string
	excludes        []string
}

func TestFilterReportsIncludePatterns(t *testing.T) {
	filter := New([]string{"*.foo", "*.bar"}, nil, GitAttributes)

	assert.Equal(t, []string{"*.foo", "*.bar"}, filter.Include())
}

func TestFilterReportsExcludePatterns(t *testing.T) {
	filter := New(nil, []string{"*.baz", "*.quux"}, GitAttributes)

	assert.Equal(t, []string{"*.baz", "*.quux"}, filter.Exclude())
}
