package githistory

import (
	"testing"

	"github.com/git-lfs/git-lfs/v3/git"
	"github.com/stretchr/testify/assert"
)

func TestRefUpdaterMovesRefs(t *testing.T) {
	db := DatabaseFromFixture(t, "linear-history-with-tags.git")
	root, _ := db.Root()

	AssertRef(t, db,
		"refs/tags/middle", HexDecode(t, "228afe30855933151f7a88e70d9d88314fd2f191"))

	updater := &refUpdater{
		cacheFn: func(old []byte) ([]byte, bool) {
			return HexDecode(t, "d941e4756add6b06f5bee766fcf669f55419f13f"), true
		},
		refs: []*git.Ref{
			{
				Name: "middle",
				Sha:  "228afe30855933151f7a88e70d9d88314fd2f191",
				Type: git.RefTypeLocalTag,
			},
		},
		root: root,
		db:   db,
	}

	err := updater.updateRefs()

	assert.NoError(t, err)

	AssertRef(t, db,
		"refs/tags/middle", HexDecode(t, "d941e4756add6b06f5bee766fcf669f55419f13f"))
}

func TestRefUpdaterMovesRefsWithAnnotatedTags(t *testing.T) {
	db := DatabaseFromFixture(t, "linear-history-with-annotated-tags.git")
	root, _ := db.Root()

	AssertRef(t, db,
		"refs/tags/middle", HexDecode(t, "05797a38b05f910e6efe40dc1a5c0a046a9403e8"))

	updater := &refUpdater{
		cacheFn: func(old []byte) ([]byte, bool) {
			return HexDecode(t, "d941e4756add6b06f5bee766fcf669f55419f13f"), true
		},
		refs: []*git.Ref{
			{
				Name: "middle",
				Sha:  "05797a38b05f910e6efe40dc1a5c0a046a9403e8",
				Type: git.RefTypeLocalTag,
			},
		},
		root: root,
		db:   db,
	}

	err := updater.updateRefs()

	assert.NoError(t, err)

	AssertRef(t, db,
		"refs/tags/middle", HexDecode(t, "9a3c2b4823ad6b300ef25197f0435b267d4f0ad8"))
}

func TestRefUpdaterIgnoresUnovedRefs(t *testing.T) {
	db := DatabaseFromFixture(t, "linear-history-with-tags.git")
	root, _ := db.Root()

	AssertRef(t, db,
		"refs/tags/middle", HexDecode(t, "228afe30855933151f7a88e70d9d88314fd2f191"))

	updater := &refUpdater{
		cacheFn: func(old []byte) ([]byte, bool) {
			return nil, false
		},
		refs: []*git.Ref{
			{
				Name: "middle",
				Sha:  "228afe30855933151f7a88e70d9d88314fd2f191",
				Type: git.RefTypeLocalTag,
			},
		},
		root: root,
		db:   db,
	}

	err := updater.updateRefs()

	assert.NoError(t, err)

	AssertRef(t, db,
		"refs/tags/middle", HexDecode(t, "228afe30855933151f7a88e70d9d88314fd2f191"))
}
