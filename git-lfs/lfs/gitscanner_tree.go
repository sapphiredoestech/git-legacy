package lfs

import (
	"io"
	"path"
	"path/filepath"

	"github.com/git-lfs/git-lfs/v3/config"
	"github.com/git-lfs/git-lfs/v3/errors"
	"github.com/git-lfs/git-lfs/v3/filepathfilter"
	"github.com/git-lfs/git-lfs/v3/git"
	"github.com/git-lfs/git-lfs/v3/git/gitattr"
	"github.com/git-lfs/git-lfs/v3/subprocess"
	"github.com/git-lfs/git-lfs/v3/tr"
)

func runScanTree(cb GitScannerFoundPointer, ref string, filter *filepathfilter.Filter, gitEnv, osEnv config.Environment) error {
	// We don't use the nameMap approach here since that's imprecise when >1 file
	// can be using the same content
	treeShas, err := lsTreeBlobs(ref, func(t *git.TreeBlob) bool {
		return t != nil && t.Size < blobSizeCutoff && filter.Allows(t.Filename)
	})
	if err != nil {
		return err
	}

	pcw, err := catFileBatchTree(treeShas, gitEnv, osEnv)
	if err != nil {
		return err
	}

	for p := range pcw.Results {
		cb(p, nil)
	}

	if err := pcw.Wait(); err != nil {
		cb(nil, err)
	}
	return nil
}

func runScanLFSFiles(cb GitScannerFoundPointer, ref string, filter *filepathfilter.Filter, gitEnv, osEnv config.Environment) error {
	var treeShas *TreeBlobChannelWrapper
	var err error
	if git.IsGitVersionAtLeast("2.42.0") {
		treeShas, err = lsFilesBlobs(func(t *git.TreeBlob) bool {
			return t != nil && t.Size < blobSizeCutoff && filter.Allows(t.Filename)
		})
	} else {
		treeShas, err = lsTreeBlobs(ref, func(t *git.TreeBlob) bool {
			return t != nil && t.Size < blobSizeCutoff && filter.Allows(t.Filename)
		})
	}
	// We don't use the nameMap approach here since that's imprecise when >1 file
	// can be using the same content
	if err != nil {
		return err
	}

	pcw, err := catFileBatchTree(treeShas, gitEnv, osEnv)
	if err != nil {
		return err
	}

	for p := range pcw.Results {
		cb(p, nil)
	}

	if err := pcw.Wait(); err != nil {
		cb(nil, err)
	}
	return nil
}

// catFileBatchTree() uses an ObjectDatabase from the
// github.com/git-lfs/gitobj/v2 package to get the contents of Git
// blob objects, given their SHA1s from git.TreeBlob structs, similar
// to the behaviour of 'git cat-file --batch'.
// Input git.TreeBlob structs should be sent over the treeblobs channel.
// The blob contents will be decoded as Git LFS pointers and any valid
// pointers will be returned as pointer.Pointer structs in a new channel.
func catFileBatchTree(treeblobs *TreeBlobChannelWrapper, gitEnv, osEnv config.Environment) (*PointerChannelWrapper, error) {
	scanner, err := NewPointerScanner(gitEnv, osEnv)
	if err != nil {
		return nil, err
	}

	pointers := make(chan *WrappedPointer, chanBufSize)
	errchan := make(chan error, 10) // Multiple errors possible

	go func() {
		hasNext := true
		for t := range treeblobs.Results {
			hasNext = scanner.Scan(t.Oid)

			if p := scanner.Pointer(); p != nil {
				p.Name = t.Filename
				pointers <- p
			}

			if err := scanner.Err(); err != nil {
				errchan <- err
			}

			if !hasNext {
				break
			}
		}

		// If the scanner quit early, we may still have treeblobs to
		// read, so waiting for it to close will cause a deadlock.
		if hasNext {
			// Deal with nested error from incoming treeblobs
			err := treeblobs.Wait()
			if err != nil {
				errchan <- err
			}
		}

		if err = scanner.Close(); err != nil {
			errchan <- err
		}

		close(pointers)
		close(errchan)
	}()

	return NewPointerChannelWrapper(pointers, errchan), nil
}

// Use ls-tree at ref to find a list of candidate tree blobs which might be lfs files
// The returned channel will be sent these blobs which should be sent to catFileBatchTree
// for final check & conversion to Pointer
func lsTreeBlobs(ref string, predicate func(*git.TreeBlob) bool) (*TreeBlobChannelWrapper, error) {
	return lsBlobs(func() (*subprocess.BufferedCmd, error) {
		return git.LsTree(ref)
	}, predicate)
}

func lsBlobs(backend func() (*subprocess.BufferedCmd, error), predicate func(*git.TreeBlob) bool) (*TreeBlobChannelWrapper, error) {
	cmd, err := backend()
	if err != nil {
		return nil, err
	}

	cmd.Stdin.Close()

	blobs := make(chan git.TreeBlob, chanBufSize)
	errchan := make(chan error, 1)

	go func() {
		scanner := git.NewLsTreeScanner(cmd.Stdout)
		for scanner.Scan() {
			if t := scanner.TreeBlob(); predicate(t) {
				blobs <- *t
			}
		}

		stderr, _ := io.ReadAll(cmd.Stderr)
		err := cmd.Wait()
		if err != nil {
			errchan <- errors.New(tr.Tr.Get("error in `git ls-tree`: %v %v", err, string(stderr)))
		}
		close(blobs)
		close(errchan)
	}()

	return NewTreeBlobChannelWrapper(blobs, errchan), nil
}

// Use ls-files at ref to find a list of candidate tree blobs which might be lfs files
// The returned channel will be sent these blobs which should be sent to catFileBatchTree
// for final check & conversion to Pointer
func lsFilesBlobs(predicate func(*git.TreeBlob) bool) (*TreeBlobChannelWrapper, error) {
	return lsBlobs(func() (*subprocess.BufferedCmd, error) {
		return git.LsFilesLFS()
	}, predicate)
}

func catFileBatchTreeForPointers(treeblobs *TreeBlobChannelWrapper, gitEnv, osEnv config.Environment) (map[string]*WrappedPointer, *filepathfilter.Filter, error) {
	pscanner, err := NewPointerScanner(gitEnv, osEnv)
	if err != nil {
		return nil, nil, err
	}
	oscanner, err := git.NewObjectScanner(gitEnv, osEnv)
	if err != nil {
		return nil, nil, err
	}

	pointers := make(map[string]*WrappedPointer)

	paths := make([]git.AttributePath, 0)
	processor := gitattr.NewMacroProcessor()

	hasNext := true
	for t := range treeblobs.Results {
		if path.Base(t.Filename) == ".gitattributes" {
			hasNext = oscanner.Scan(t.Oid)

			if rdr := oscanner.Contents(); rdr != nil {
				paths = append(paths, git.AttrPathsFromReader(
					processor,
					t.Filename,
					"",
					rdr,
					t.Filename == ".gitattributes", // Read macros from the top-level attributes
				)...)
			}

			if err := oscanner.Err(); err != nil {
				return nil, nil, err
			}
		} else if t.Size < blobSizeCutoff {
			hasNext = pscanner.Scan(t.Oid)

			// It's intentional that we insert nil for
			// non-pointers; we want to keep track of them
			// as well as pointers.
			p := pscanner.Pointer()
			if p != nil {
				p.Name = t.Filename
			}
			pointers[t.Filename] = p

			if err := pscanner.Err(); err != nil {
				return nil, nil, err
			}
		} else {
			pointers[t.Filename] = nil
		}

		if !hasNext {
			break
		}
	}

	// If the scanner quit early, we may still have treeblobs to
	// read, so waiting for it to close will cause a deadlock.
	if hasNext {
		// Deal with nested error from incoming treeblobs
		err := treeblobs.Wait()
		if err != nil {
			return nil, nil, err
		}
	}

	if err = pscanner.Close(); err != nil {
		return nil, nil, err
	}
	if err = oscanner.Close(); err != nil {
		return nil, nil, err
	}

	includes := make([]filepathfilter.Pattern, 0, len(paths))
	excludes := make([]filepathfilter.Pattern, 0, len(paths))
	for _, path := range paths {
		// Convert all separators to `/` before creating a pattern to
		// avoid characters being escaped in situations like `subtree\*.md`
		pattern := filepathfilter.NewPattern(filepath.ToSlash(path.Path), filepathfilter.GitAttributes)
		if path.Tracked {
			includes = append(includes, pattern)
		} else {
			excludes = append(excludes, pattern)
		}
	}

	return pointers, filepathfilter.NewFromPatterns(includes, excludes, filepathfilter.DefaultValue(false)), nil
}

func runScanTreeForPointers(cb GitScannerFoundPointer, tree string, gitEnv, osEnv config.Environment) error {
	treeShas, err := lsTreeBlobs(tree, func(t *git.TreeBlob) bool {
		return t != nil && (t.Mode == 0100644 || t.Mode == 0100755)
	})
	if err != nil {
		return err
	}

	pointers, filter, err := catFileBatchTreeForPointers(treeShas, gitEnv, osEnv)
	if err != nil {
		return err
	}

	for name, p := range pointers {
		// This file matches the patterns in .gitattributes, so it
		// should be a pointer.  If it is not, then it is a plain Git
		// blob, which we report as an error.
		if filter.Allows(name) {
			if p == nil {
				cb(nil, errors.NewPointerScanError(errors.NewNotAPointerError(nil), tree, name))
			} else {
				cb(p, nil)
			}
		}
	}
	return nil
}
