//go:build darwin
// +build darwin

package tools

import (
	"io"
	"os"
	"strconv"
	"strings"

	"github.com/git-lfs/git-lfs/v3/errors"
	"github.com/git-lfs/git-lfs/v3/tr"
	"golang.org/x/sys/unix"
)

var cloneFileSupported bool

func init() {
	cloneFileSupported = checkCloneFileSupported()
}

// checkCloneFileSupported return iff Mac OS version is greater or equal to 10.12.x Sierra.
//
// clonefile is supported since Mac OS X 10.12
// https://www.manpagez.com/man/2/clonefile/
//
// kern.osrelease mapping
// 17.x.x. macOS 10.13.x High Sierra.
// 16.x.x  macOS 10.12.x Sierra.
// 15.x.x  OS X  10.11.x El Capitan.
func checkCloneFileSupported() bool {
	bytes, err := unix.Sysctl("kern.osrelease")
	if err != nil {
		return false
	}

	versionString := strings.Split(string(bytes), ".") // major.minor.patch
	if len(versionString) < 2 {
		return false
	}

	major, err := strconv.Atoi(versionString[0])
	if err != nil {
		return false
	}

	return major >= 16
}

// CheckCloneFileSupported runs explicit test of clone file on supplied directory.
// This function creates some (src and dst) file in the directory and remove after test finished.
//
// If check failed (e.g. directory is read-only), returns err.
func CheckCloneFileSupported(dir string) (supported bool, err error) {
	if !cloneFileSupported {
		return false, errors.New(tr.Tr.Get("Unsupported OS version. 10.12.x Sierra or higher required."))
	}

	src, err := os.CreateTemp(dir, "src")
	if err != nil {
		return false, err
	}
	defer os.Remove(src.Name())
	src.Close()

	dst, err := os.CreateTemp(dir, "dst")
	if err != nil {
		return false, err
	}
	defer os.Remove(dst.Name())
	dst.Close()

	return CloneFileByPath(dst.Name(), src.Name())
}

type CloneFileError struct {
	Unsupported bool
	errorString string
}

func (c *CloneFileError) Error() string {
	return c.errorString
}

func CloneFile(_ io.Writer, _ io.Reader) (bool, error) {
	return false, nil // Cloning from io.Writer(file descriptor) is not supported by Darwin.
}

func CloneFileByPath(dst, src string) (bool, error) {
	if !cloneFileSupported {
		return false, &CloneFileError{Unsupported: true, errorString: tr.Tr.Get("clonefile is not supported")}
	}

	if FileExists(dst) {
		if err := os.Remove(dst); err != nil {
			return false, err // File should be not exists before create
		}
	}

	if err := cloneFileSyscall(dst, src); err != nil {
		return false, err
	}

	return true, nil
}

func cloneFileSyscall(dst, src string) *CloneFileError {
	err := unix.Clonefileat(unix.AT_FDCWD, src, unix.AT_FDCWD, dst, unix.CLONE_NOFOLLOW)
	if err != nil {
		return &CloneFileError{
			Unsupported: err == unix.ENOTSUP,
			errorString: tr.Tr.Get("error cloning from %v to %v: %s", src, dst, err),
		}
	}

	return nil
}
