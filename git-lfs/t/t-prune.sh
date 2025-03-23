#!/usr/bin/env bash

. "$(dirname "$0")/testlib.sh"

begin_test "prune unreferenced and old"
(
  set -e

  reponame="prune_unref_old"
  setup_remote_repo "remote_$reponame"

  clone_repo "remote_$reponame" "clone_$reponame"

  git lfs track "*.dat" 2>&1 | tee track.log
  grep "Tracking \"\*.dat\"" track.log

  # generate content we'll use
  content_unreferenced="To delete: unreferenced"
  content_oldandpushed="To delete: pushed and too old"
  content_oldandunchanged="Keep: pushed and created a while ago, but still current"
  oid_unreferenced=$(calc_oid "$content_unreferenced")
  oid_oldandpushed=$(calc_oid "$content_oldandpushed")
  oid_oldandunchanged=$(calc_oid "$content_oldandunchanged")
  content_retain1="Retained content 1"
  content_retain2="Retained content 2"
  oid_retain1=$(calc_oid "$content_retain1")
  oid_retain2=$(calc_oid "$content_retain2")

  # Remember for something to be 'too old' it has to appear on the MINUS side
  # of the diff outside the prune window, i.e. it's not when it was introduced
  # but when it disappeared from relevance. That's why changes to old.dat on main
  # from 7d ago are included even though the commit itself is outside of the window,
  # that content of old.dat was relevant until it was removed with a commit, inside the window
  # think of it as windows of relevance that overlap until the content is replaced

  # we also make sure we commit today on main so that the recent commits measured
  # from latest commit on main tracks back from there
  echo "[
  {
    \"CommitDate\":\"$(get_date -20d)\",
    \"Files\":[
      {\"Filename\":\"old.dat\",\"Size\":${#content_oldandpushed}, \"Data\":\"$content_oldandpushed\"},
      {\"Filename\":\"stillcurrent.dat\",\"Size\":${#content_oldandunchanged}, \"Data\":\"$content_oldandunchanged\"}]
  },
  {
    \"CommitDate\":\"$(get_date -7d)\",
    \"Files\":[
      {\"Filename\":\"old.dat\",\"Size\":${#content_retain1}, \"Data\":\"$content_retain1\"}]
  },
  {
    \"CommitDate\":\"$(get_date -4d)\",
    \"NewBranch\":\"branch_to_delete\",
    \"Files\":[
      {\"Filename\":\"unreferenced.dat\",\"Size\":${#content_unreferenced}, \"Data\":\"$content_unreferenced\"}]
  },
  {
    \"ParentBranches\":[\"main\"],
    \"Files\":[
      {\"Filename\":\"old.dat\",\"Size\":${#content_retain2}, \"Data\":\"$content_retain2\"}]
  }
  ]" | lfstest-testutils addcommits

  git push origin main
  git branch -D branch_to_delete

  git config lfs.fetchrecentrefsdays 5
  git config lfs.fetchrecentremoterefs true
  git config lfs.fetchrecentcommitsdays 3
  git config lfs.pruneoffsetdays 2

  git lfs prune --dry-run --verbose 2>&1 | tee prune.log

  grep "5 local objects, 3 retained" prune.log
  grep "2 files would be pruned" prune.log
  grep "$oid_oldandpushed" prune.log
  grep "$oid_unreferenced" prune.log

  assert_local_object "$oid_oldandpushed" "${#content_oldandpushed}"
  assert_local_object "$oid_unreferenced" "${#content_unreferenced}"
  git lfs prune
  refute_local_object "$oid_oldandpushed" "${#content_oldandpushed}"
  refute_local_object "$oid_unreferenced" "${#content_unreferenced}"
  assert_local_object "$oid_oldandunchanged" "${#content_oldandunchanged}"
  assert_local_object "$oid_retain1" "${#content_retain1}"
  assert_local_object "$oid_retain2" "${#content_retain2}"

  # now only keep AT refs, no recents
  git config lfs.fetchrecentcommitsdays 0

  git lfs prune --verbose 2>&1 | tee prune.log
  grep "3 local objects, 2 retained" prune.log
  grep "Deleting objects: 100% (1/1), done." prune.log
  grep "$oid_retain1" prune.log
  refute_local_object "$oid_retain1"
  assert_local_object "$oid_retain2" "${#content_retain2}"
)
end_test

begin_test "prune all excluded paths"
(
  set -e

  reponame="prune_unref_old_exclude"
  setup_remote_repo "remote_$reponame"

  clone_repo "remote_$reponame" "clone_$reponame"

  git lfs track "*.dat" 2>&1 | tee track.log
  grep "Tracking \"\*.dat\"" track.log

  # generate content we'll use
  content_oldandexcluded="To delete: pushed and too old and excluded by filter"
  content_oldandunchanged="Keep: pushed and created a while ago, but still current"
  content_prevandexcluded="To delete: pushed and in previous commit to HEAD but excluded by filter"
  content_unreferencedandexcluded="To delete: unreferenced in deleted branch and pushed and excluded by filter"
  content_includedandexcluded="Keep: pushed and both excluded by filter and included by another path"
  content_excluded="To delete: pushed and in HEAD but excluded by filter"
  oid_oldandexcluded=$(calc_oid "$content_oldandexcluded")
  oid_oldandunchanged=$(calc_oid "$content_oldandunchanged")
  oid_prevandexcluded=$(calc_oid "$content_prevandexcluded")
  oid_unreferencedandexcluded=$(calc_oid "$content_unreferencedandexcluded")
  oid_includedandexcluded=$(calc_oid "$content_includedandexcluded")
  oid_excluded=$(calc_oid "$content_excluded")

  echo "[
  {
    \"CommitDate\":\"$(get_date -20d)\",
    \"Files\":[
      {\"Filename\":\"foo/oldandexcluded.dat\",\"Size\":${#content_oldandexcluded}, \"Data\":\"$content_oldandexcluded\"},
      {\"Filename\":\"stillcurrent.dat\",\"Size\":${#content_oldandunchanged}, \"Data\":\"$content_oldandunchanged\"}]
  },
  {
    \"CommitDate\":\"$(get_date -7d)\",
    \"Files\":[
      {\"Filename\":\"foo/oldandexcluded.dat\",\"Size\":${#content_prevandexcluded}, \"Data\":\"$content_prevandexcluded\"}]
  },
  {
    \"CommitDate\":\"$(get_date -4d)\",
    \"NewBranch\":\"branch_to_delete\",
    \"Files\":[
      {\"Filename\":\"unreferenced.dat\",\"Size\":${#content_unreferencedandexcluded}, \"Data\":\"$content_unreferencedandexcluded\"}]
  },
  {
    \"ParentBranches\":[\"main\"],
    \"Files\":[
      {\"Filename\":\"foo/unreferencedandexcluded.dat\",\"Size\":${#content_unreferencedandexcluded}, \"Data\":\"$content_unreferencedandexcluded\"},
      {\"Filename\":\"foo/includedandexcluded.dat\",\"Size\":${#content_includedandexcluded}, \"Data\":\"$content_includedandexcluded\"},
      {\"Filename\":\"included.dat\",\"Size\":${#content_includedandexcluded}, \"Data\":\"$content_includedandexcluded\"},
      {\"Filename\":\"foo/oldandexcluded.dat\",\"Size\":${#content_excluded}, \"Data\":\"$content_excluded\"}]
  }
  ]" | lfstest-testutils addcommits

  git push origin main
  git branch -D branch_to_delete

  git config lfs.fetchrecentrefsdays 5
  git config lfs.fetchrecentremoterefs true
  git config lfs.fetchrecentcommitsdays 3
  git config lfs.pruneoffsetdays 2

  # We need to prevent MSYS from rewriting /foo into a Windows path.
  MSYS_NO_PATHCONV=1 git config "lfs.fetchexclude" "/foo"

  git lfs prune --dry-run --verbose 2>&1 | tee prune.log

  grep "6 local objects, 2 retained" prune.log
  grep "4 files would be pruned" prune.log
  grep "$oid_oldandexcluded" prune.log
  grep "$oid_prevandexcluded" prune.log
  grep "$oid_unreferencedandexcluded" prune.log
  grep "$oid_excluded" prune.log

  assert_local_object "$oid_oldandexcluded" "${#content_oldandexcluded}"
  assert_local_object "$oid_prevandexcluded" "${#content_prevandexcluded}"
  assert_local_object "$oid_unreferencedandexcluded" "${#content_unreferencedandexcluded}"
  assert_local_object "$oid_excluded" "${#content_excluded}"
  git lfs prune
  refute_local_object "$oid_oldandexcluded" "${#content_oldandexcluded}"
  assert_local_object "$oid_oldandunchanged" "${#content_oldandunchanged}"
  refute_local_object "$oid_prevandexcluded" "${#content_prevandexcluded}"
  refute_local_object "$oid_unreferencedandexcluded" "${#content_unreferencedandexcluded}"
  assert_local_object "$oid_includedandexcluded" "${#content_includedandexcluded}"
  refute_local_object "$oid_excluded" "${#content_excluded}"
)
end_test

begin_test "prune keep unpushed"
(
  set -e

  # need to set up many commits on each branch with old data so that would
  # get deleted if it were not for unpushed status (heads would never be pruned but old changes would)
  reponame="prune_keep_unpushed"
  setup_remote_repo "remote_$reponame"

  clone_repo "remote_$reponame" "clone_$reponame"

  git lfs track "*.dat" 2>&1 | tee track.log
  grep "Tracking \"\*.dat\"" track.log

  content_keepunpushedhead1="Keep: unpushed HEAD 1"
  content_keepunpushedhead2="Keep: unpushed HEAD 2"
  content_keepunpushedhead3="Keep: unpushed HEAD 3"
  content_keepunpushedbranch1="Keep: unpushed second branch 1"
  content_keepunpushedbranch2="Keep: unpushed second branch 2"
  content_keepunpushedbranch3="Keep: unpushed second branch 3"
  content_keepunpushedandexcludedbranch1="Keep: unpushed second branch 1 excluded by filter"
  content_keepunpushedandexcludedbranch2="Keep: unpushed second branch 2 excluded by filter"
  content_keepunpushedandexcludedbranch3="Keep: unpushed second branch 3 excluded by filter"
  content_keepunpushedtag1="Keep: unpushed tag only 1"
  content_keepunpushedtag2="Keep: unpushed tag only 2"
  content_keepunpushedtag3="Keep: unpushed tag only 3"
  oid_keepunpushedhead1=$(calc_oid "$content_keepunpushedhead1")
  oid_keepunpushedhead2=$(calc_oid "$content_keepunpushedhead2")
  oid_keepunpushedhead3=$(calc_oid "$content_keepunpushedhead3")
  oid_keepunpushedbranch1=$(calc_oid "$content_keepunpushedbranch1")
  oid_keepunpushedbranch2=$(calc_oid "$content_keepunpushedbranch2")
  oid_keepunpushedbranch3=$(calc_oid "$content_keepunpushedbranch3")
  oid_keepunpushedandexcludedbranch1=$(calc_oid "$content_keepunpushedandexcludedbranch1")
  oid_keepunpushedandexcludedbranch2=$(calc_oid "$content_keepunpushedandexcludedbranch2")
  oid_keepunpushedandexcludedbranch3=$(calc_oid "$content_keepunpushedandexcludedbranch3")
  oid_keepunpushedtag1=$(calc_oid "$content_keepunpushedtag1")
  oid_keepunpushedtag2=$(calc_oid "$content_keepunpushedtag2")
  oid_keepunpushedtag3=$(calc_oid "$content_keepunpushedtag3")

  echo "[
  {
    \"CommitDate\":\"$(get_date -40d)\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_keepunpushedhead1}, \"Data\":\"$content_keepunpushedhead1\"}]
  },
  {
    \"CommitDate\":\"$(get_date -31d)\",
    \"ParentBranches\":[\"main\"],
    \"NewBranch\":\"branch_unpushed\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_keepunpushedbranch1}, \"Data\":\"$content_keepunpushedbranch1\"},
      {\"Filename\":\"foo/file.dat\",\"Size\":${#content_keepunpushedandexcludedbranch1}, \"Data\":\"$content_keepunpushedandexcludedbranch1\"}]
  },
  {
    \"CommitDate\":\"$(get_date -16d)\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_keepunpushedbranch2}, \"Data\":\"$content_keepunpushedbranch2\"},
      {\"Filename\":\"foo/file.dat\",\"Size\":${#content_keepunpushedandexcludedbranch2}, \"Data\":\"$content_keepunpushedandexcludedbranch2\"}]
  },
  {
    \"CommitDate\":\"$(get_date -2d)\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_keepunpushedbranch3}, \"Data\":\"$content_keepunpushedbranch3\"},
      {\"Filename\":\"foo/file.dat\",\"Size\":${#content_keepunpushedandexcludedbranch3}, \"Data\":\"$content_keepunpushedandexcludedbranch3\"}]
  },
  {
    \"CommitDate\":\"$(get_date -31d)\",
    \"ParentBranches\":[\"main\"],
    \"NewBranch\":\"branch_unpushed_tagged_only\",
    \"Files\":[
      {\"Filename\":\"file2.dat\",\"Size\":${#content_keepunpushedtag1}, \"Data\":\"$content_keepunpushedtag1\"}]
  },
  {
    \"CommitDate\":\"$(get_date -16d)\",
    \"Files\":[
      {\"Filename\":\"file2.dat\",\"Size\":${#content_keepunpushedtag2}, \"Data\":\"$content_keepunpushedtag2\"}]
  },
  {
    \"CommitDate\":\"$(get_date -2d)\",
    \"Tags\":[\"tag_unpushed\"],
    \"Files\":[
      {\"Filename\":\"file2.dat\",\"Size\":${#content_keepunpushedtag3}, \"Data\":\"$content_keepunpushedtag3\"}]
  },
  {
    \"CommitDate\":\"$(get_date -21d)\",
    \"ParentBranches\":[\"main\"],
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_keepunpushedhead2}, \"Data\":\"$content_keepunpushedhead2\"}]
  },
  {
    \"CommitDate\":\"$(get_date -0d)\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_keepunpushedhead3}, \"Data\":\"$content_keepunpushedhead3\"}]
  }
  ]" | lfstest-testutils addcommits

  git config lfs.fetchrecentrefsdays 5
  git config lfs.fetchrecentremoterefs true
  git config lfs.fetchrecentcommitsdays 0 # only keep AT refs, no recents
  git config lfs.pruneoffsetdays 2

  # We need to prevent MSYS from rewriting /foo into a Windows path.
  MSYS_NO_PATHCONV=1 git config "lfs.fetchexclude" "/foo"

  # force color codes in git diff meta-information
  git config color.diff always

  git branch -D branch_unpushed_tagged_only

  git lfs prune

  # Now push main and show that only older versions on main will be removed.
  git push origin main

  git lfs prune --verbose 2>&1 | tee prune.log
  grep "12 local objects, 10 retained" prune.log
  grep "Deleting objects: 100% (2/2), done." prune.log
  grep "$oid_keepunpushedhead1" prune.log
  grep "$oid_keepunpushedhead2" prune.log
  refute_local_object "$oid_keepunpushedhead1"
  refute_local_object "$oid_keepunpushedhead2"

  # Merge the unpushed branch and tag, delete them, and then push main.
  # Resolve conflicts by taking other branch.
  git merge -Xtheirs branch_unpushed
  git merge tag_unpushed
  git branch -D branch_unpushed
  git tag -d tag_unpushed
  git push origin main

  # Now make sure we purged all the intermediate commits but also make sure
  # they are on the remote.
  git lfs prune --verbose 2>&1 | tee prune.log
  grep "10 local objects, 2 retained" prune.log
  grep "Deleting objects: 100% (8/8), done." prune.log
  grep "$oid_keepunpushedbranch1" prune.log
  grep "$oid_keepunpushedbranch2" prune.log
  grep "$oid_keepunpushedandexcludedbranch1" prune.log
  grep "$oid_keepunpushedandexcludedbranch2" prune.log
  # This is in the new HEAD and would be retained except that it is also
  # excluded by the filter and has been pushed, so it should have been purged.
  grep "$oid_keepunpushedandexcludedbranch3" prune.log
  grep "$oid_keepunpushedtag1" prune.log
  grep "$oid_keepunpushedtag2" prune.log
  grep "$oid_keepunpushedhead3" prune.log
  refute_local_object "$oid_keepunpushedbranch1"
  refute_local_object "$oid_keepunpushedbranch2"
  refute_local_object "$oid_keepunpushedandexcludedbranch1"
  refute_local_object "$oid_keepunpushedandexcludedbranch2"
  # This is in the new HEAD and would be retained except that it is also
  # excluded by the filter and has been pushed, so it should have been purged.
  refute_local_object "$oid_keepunpushedandexcludedbranch3"
  refute_local_object "$oid_keepunpushedtag1"
  refute_local_object "$oid_keepunpushedtag2"
  # We used -Xtheirs when merging the branch so the old HEAD is now obsolete.
  refute_local_object "$oid_keepunpushedhead3"
  assert_server_object "remote_$reponame" "$oid_keepunpushedbranch1"
  assert_server_object "remote_$reponame" "$oid_keepunpushedbranch2"
  assert_server_object "remote_$reponame" "$oid_keepunpushedandexcludedbranch1"
  assert_server_object "remote_$reponame" "$oid_keepunpushedandexcludedbranch2"
  assert_server_object "remote_$reponame" "$oid_keepunpushedandexcludedbranch3"
  assert_server_object "remote_$reponame" "$oid_keepunpushedtag1"
  assert_server_object "remote_$reponame" "$oid_keepunpushedtag2"
  assert_server_object "remote_$reponame" "$oid_keepunpushedhead3"
)
end_test

begin_test "prune keep recent"
(
  set -e

  reponame="prune_recent"
  setup_remote_repo "remote_$reponame"

  clone_repo "remote_$reponame" "clone_$reponame"

  git lfs track "*.dat" 2>&1 | tee track.log
  grep "Tracking \"\*.dat\"" track.log

  content_keephead="Keep: HEAD"
  content_keeprecentbranch1tip="Keep: Recent branch 1 tip"
  content_keeprecentbranch2tip="Keep: Recent branch 2 tip"
  content_keeprecentcommithead="Keep: Recent commit on HEAD"
  content_keeprecentcommitbranch1="Keep: Recent commit on recent branch 1"
  content_keeprecentcommitbranch2="Keep: Recent commit on recent branch 2"
  content_prunecommitoldbranch1="Prune: old commit on old branch"
  content_prunecommitoldbranch2="Prune: old branch tip"
  content_prunecommitbranch1="Prune: old commit on recent branch 1"
  content_prunecommitbranch2="Prune: old commit on recent branch 2"
  content_prunecommithead="Prune: old commit on HEAD"
  oid_keephead=$(calc_oid "$content_keephead")
  oid_keeprecentbranch1tip=$(calc_oid "$content_keeprecentbranch1tip")
  oid_keeprecentbranch2tip=$(calc_oid "$content_keeprecentbranch2tip")
  oid_keeprecentcommithead=$(calc_oid "$content_keeprecentcommithead")
  oid_keeprecentcommitbranch1=$(calc_oid "$content_keeprecentcommitbranch1")
  oid_keeprecentcommitbranch2=$(calc_oid "$content_keeprecentcommitbranch2")
  oid_prunecommitoldbranch=$(calc_oid "$content_prunecommitoldbranch1")
  oid_prunecommitoldbranch2=$(calc_oid "$content_prunecommitoldbranch2")
  oid_prunecommitbranch1=$(calc_oid "$content_prunecommitbranch1")
  oid_prunecommitbranch2=$(calc_oid "$content_prunecommitbranch2")
  oid_prunecommithead=$(calc_oid "$content_prunecommithead")

  # use a single file so each commit supersedes the last, if different files
  # then history becomes harder to track
  # Also note that when considering 'recent' when editing a single file, it means
  # that the snapshot state overlapped; so the latest commit *before* the day
  # that you're looking at, not just the commits on/after.
  echo "[
  {
    \"CommitDate\":\"$(get_date -50d)\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_prunecommithead}, \"Data\":\"$content_prunecommithead\"}]
  },
  {
    \"CommitDate\":\"$(get_date -30d)\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_keeprecentcommithead}, \"Data\":\"$content_keeprecentcommithead\"}]
  },
  {
    \"CommitDate\":\"$(get_date -8d)\",
    \"NewBranch\":\"branch_old\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_prunecommitoldbranch1}, \"Data\":\"$content_prunecommitoldbranch1\"}]
  },
  {
    \"CommitDate\":\"$(get_date -7d)\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_prunecommitoldbranch2}, \"Data\":\"$content_prunecommitoldbranch2\"}]
  },
  {
    \"CommitDate\":\"$(get_date -9d)\",
    \"ParentBranches\":[\"main\"],
    \"NewBranch\":\"branch1\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_prunecommitbranch1}, \"Data\":\"$content_prunecommitbranch1\"}]
  },
  {
    \"CommitDate\":\"$(get_date -8d)\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_keeprecentcommitbranch1}, \"Data\":\"$content_keeprecentcommitbranch1\"}]
  },
  {
    \"CommitDate\":\"$(get_date -5d)\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_keeprecentbranch1tip}, \"Data\":\"$content_keeprecentbranch1tip\"}]
  },
  {
    \"CommitDate\":\"$(get_date -17d)\",
    \"ParentBranches\":[\"main\"],
    \"NewBranch\":\"branch2\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_prunecommitbranch2}, \"Data\":\"$content_prunecommitbranch2\"}]
  },
  {
    \"CommitDate\":\"$(get_date -10d)\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_keeprecentcommitbranch2}, \"Data\":\"$content_keeprecentcommitbranch2\"}]
  },
  {
    \"CommitDate\":\"$(get_date -2d)\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_keeprecentbranch2tip}, \"Data\":\"$content_keeprecentbranch2tip\"}]
  },
  {
    \"CommitDate\":\"$(get_date -1d)\",
    \"ParentBranches\":[\"main\"],
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_keephead}, \"Data\":\"$content_keephead\"}]
  }
  ]" | lfstest-testutils addcommits

  # keep refs for 6 days & any prev commit that overlaps 2 days before tip (recent + offset)
  git config lfs.fetchrecentrefsdays 5
  git config lfs.fetchrecentremoterefs true
  git config lfs.fetchrecentcommitsdays 1
  git config lfs.pruneoffsetdays 1

  # force color codes in git diff meta-information
  git config color.diff always

  # push everything so that's not a reason to retain
  git push origin main:main branch_old:branch_old branch1:branch1 branch2:branch2

  git lfs prune --verbose 2>&1 | tee prune.log
  grep "11 local objects, 6 retained, done." prune.log
  grep "Deleting objects: 100% (5/5), done." prune.log
  grep "$oid_prunecommitoldbranch" prune.log
  grep "$oid_prunecommitoldbranch2" prune.log
  grep "$oid_prunecommitbranch1" prune.log
  grep "$oid_prunecommitbranch2" prune.log
  grep "$oid_prunecommithead" prune.log

  refute_local_object "$oid_prunecommitoldbranch"
  refute_local_object "$oid_prunecommitoldbranch2"
  refute_local_object "$oid_prunecommitbranch1"
  refute_local_object "$oid_prunecommitbranch2"
  refute_local_object "$oid_prunecommithead"
  assert_local_object "$oid_keephead" "${#content_keephead}"
  assert_local_object "$oid_keeprecentbranch1tip" "${#content_keeprecentbranch1tip}"
  assert_local_object "$oid_keeprecentbranch2tip" "${#content_keeprecentbranch2tip}"
  assert_local_object "$oid_keeprecentcommithead" "${#content_keeprecentcommithead}"
  assert_local_object "$oid_keeprecentcommitbranch1" "${#content_keeprecentcommitbranch1}"
  assert_local_object "$oid_keeprecentcommitbranch2" "${#content_keeprecentcommitbranch2}"

  # now don't include any recent commits in fetch & hence don't retain
  # still retain tips of branches
  git config lfs.fetchrecentcommitsdays 0
  git lfs prune --verbose 2>&1 | tee prune.log
  grep "6 local objects, 3 retained, done." prune.log
  grep "Deleting objects: 100% (3/3), done." prune.log
  assert_local_object "$oid_keephead" "${#content_keephead}"
  assert_local_object "$oid_keeprecentbranch1tip" "${#content_keeprecentbranch1tip}"
  assert_local_object "$oid_keeprecentbranch2tip" "${#content_keeprecentbranch2tip}"
  refute_local_object "$oid_keeprecentcommithead"
  refute_local_object "$oid_keeprecentcommitbranch1"
  refute_local_object "$oid_keeprecentcommitbranch2"

  # now don't include any recent refs at all, only keep HEAD
  git config lfs.fetchrecentrefsdays 0
  git lfs prune --verbose 2>&1 | tee prune.log
  grep "3 local objects, 1 retained, done." prune.log
  grep "Deleting objects: 100% (2/2), done." prune.log
  assert_local_object "$oid_keephead" "${#content_keephead}"
  refute_local_object "$oid_keeprecentbranch1tip"
  refute_local_object "$oid_keeprecentbranch2tip"
)
end_test

begin_test "prune remote tests"
(
  set -e

  reponame="prune_no_or_nonorigin_remote"
  git init "$reponame"
  cd "$reponame"

  git lfs track "*.dat" 2>&1 | tee track.log
  grep "Tracking \"\*.dat\"" track.log

  echo "[
  {
    \"CommitDate\":\"$(get_date -50d)\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":30}]
  },
  {
    \"CommitDate\":\"$(get_date -40d)\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":28}]
  },
  {
    \"CommitDate\":\"$(get_date -35d)\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":37}]
  },
  {
    \"CommitDate\":\"$(get_date -25d)\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":42}]
  }
  ]" | lfstest-testutils addcommits

  # set no recents so max ability to prune normally
  git config lfs.fetchrecentrefsdays 0
  git config lfs.fetchrecentremoterefs true
  git config lfs.fetchrecentcommitsdays 0
  git config lfs.pruneoffsetdays 1

  # can never prune with no remote
  git lfs prune --verbose 2>&1 | tee prune.log
  grep "4 local objects, 4 retained, done." prune.log


  # also make sure nothing is pruned when remote is not origin
  # create 2 remotes, neither of which is called origin & push to both
  setup_remote_repo "remote1_$reponame"
  setup_remote_repo "remote2_$reponame"
  cd "$TRASHDIR/$reponame"
  git remote add not_origin "$GITSERVER/remote1_$reponame"
  git push not_origin main

  git lfs prune --verbose 2>&1 | tee prune.log
  grep "4 local objects, 4 retained, done." prune.log

  # now set the prune remote to be not_origin, should now prune
  # do a dry run so we can also verify
  git config lfs.pruneremotetocheck not_origin

  git lfs prune --verbose --dry-run 2>&1 | tee prune.log
  grep "4 local objects, 1 retained, done." prune.log
  grep "3 files would be pruned" prune.log
)
end_test

begin_test "prune verify"
(
  set -e

  reponame="prune_verify"
  setup_remote_repo "remote_$reponame"

  clone_repo "remote_$reponame" "clone_$reponame"

  git lfs track "*.dat" 2>&1 | tee track.log
  grep "Tracking \"\*.dat\"" track.log

  content_head="HEAD content"
  content_commit3="Content for commit 3 (prune)"
  content_commit2_failverify="Content for commit 2 (prune - fail verify)"
  content_commit1="Content for commit 1 (prune)"
  oid_head=$(calc_oid "$content_head")
  oid_commit3=$(calc_oid "$content_commit3")
  oid_commit2_failverify=$(calc_oid "$content_commit2_failverify")
  oid_commit1=$(calc_oid "$content_commit1")

  echo "[
  {
    \"CommitDate\":\"$(get_date -50d)\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_commit1}, \"Data\":\"$content_commit1\"}]
  },
  {
    \"CommitDate\":\"$(get_date -40d)\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_commit2_failverify}, \"Data\":\"$content_commit2_failverify\"}]
  },
  {
    \"CommitDate\":\"$(get_date -35d)\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_commit3}, \"Data\":\"$content_commit3\"}]
  },
  {
    \"CommitDate\":\"$(get_date -25d)\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_head}, \"Data\":\"$content_head\"}]
  }
  ]" | lfstest-testutils addcommits

  # push all so no unpushed reason to not prune
  git push origin main

  # set no recents so max ability to prune normally
  git config lfs.fetchrecentrefsdays 0
  git config lfs.fetchrecentremoterefs true
  git config lfs.fetchrecentcommitsdays 0
  git config lfs.pruneoffsetdays 1

  # confirm that it would prune with verify when no issues
  git lfs prune --dry-run --verify-remote --verbose 2>&1 | tee prune.log
  grep "4 local objects, 1 retained, 3 verified with remote, done." prune.log
  grep "3 files would be pruned" prune.log
  grep "$oid_commit3" prune.log
  grep "$oid_commit2_failverify" prune.log
  grep "$oid_commit1" prune.log

  # delete one file on the server to make the verify fail
  delete_server_object "remote_$reponame" "$oid_commit2_failverify"
  # this should now fail
  git lfs prune --verify-remote 2>&1 | tee prune.log
  grep "4 local objects, 1 retained, 2 verified with remote, 1 not on remote, done." prune.log
  grep "missing on remote:" prune.log
  grep "$oid_commit2_failverify" prune.log
  # Nothing should have been deleted
  assert_local_object "$oid_commit1" "${#content_commit1}"
  assert_local_object "$oid_commit2_failverify" "${#content_commit2_failverify}"
  assert_local_object "$oid_commit3" "${#content_commit3}"

  # Now test with the global option
  git config lfs.pruneverifyremotealways true
  # no verify arg but should be pulled from global
  git lfs prune 2>&1 | tee prune.log
  grep "4 local objects, 1 retained, 2 verified with remote, 1 not on remote, done." prune.log
  grep "missing on remote:" prune.log
  grep "$oid_commit2_failverify" prune.log
  # Nothing should have been deleted
  assert_local_object "$oid_commit1" "${#content_commit1}"
  assert_local_object "$oid_commit2_failverify" "${#content_commit2_failverify}"
  assert_local_object "$oid_commit3" "${#content_commit3}"

  # --when-unverified=continue we would prune verified objects but skip unverified objects
  git lfs prune --when-unverified=continue --dry-run --verbose 2>&1 | tee prune.log
  grep "4 local objects, 1 retained, 2 verified with remote, 1 not on remote, done." prune.log
  grep "2 files would be pruned" prune.log
  grep "$oid_commit1" prune.log
  grep "$oid_commit3" prune.log

  # now try overriding the global option
  git lfs prune --no-verify-remote 2>&1 | tee prune.log
  grep "4 local objects, 1 retained, done." prune.log
  grep "Deleting objects: 100% (3/3), done." prune.log
  # should now have been deleted
  refute_local_object "$oid_commit1"
  refute_local_object "$oid_commit2_failverify"
  refute_local_object "$oid_commit3"
)
end_test

begin_test "prune verify large numbers of refs"
(
  set -e

  reponame="prune_verify_large"
  setup_remote_repo "remote_$reponame"

  clone_repo "remote_$reponame" "clone_$reponame"

  git lfs track "*.dat" 2>&1 | tee track.log
  grep "Tracking \"\*.dat\"" track.log

  content_head="HEAD content"
  content_commit1="Recent commit"
  content_oldcommit1="Old content $(lfstest-genrandom --base64 40)"
  content_oldcommit2="Old content $(lfstest-genrandom --base64 40)"
  oid_head=$(calc_oid "$content_head")

  # Add two recent commits that should not be pruned
  echo "[
  {
    \"CommitDate\":\"$(get_date -50d)\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_oldcommit1}, \"Data\":\"$content_oldcommit1\"}]
  },
  {
    \"CommitDate\":\"$(get_date -45d)\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_oldcommit2}, \"Data\":\"$content_oldcommit2\"}]
  },
  {
    \"CommitDate\":\"$(get_date -2d)\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_commit1}, \"Data\":\"$content_commit1\"}]
  },
  {
    \"CommitDate\":\"$(get_date -1d)\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_head}, \"Data\":\"$content_head\"}]
  }
  ]" | lfstest-testutils addcommits

  # Generate a large number of refs to old commits make sure prune has a lot of data to read
  git checkout $(git log --pretty=oneline  main | tail -2 | awk '{print $1}' | head -1)
  for i in $(seq 0 1000); do
    git tag v$i
  done
  git checkout main

  # push all so no unpushed reason to not prune
  # git push origin main

  # set no recents so max ability to prune normally
  git config lfs.fetchrecentrefsdays 3
  git config lfs.fetchrecentremoterefs true
  git config lfs.fetchrecentcommitsdays 3
  git config lfs.pruneoffsetdays 3

  # confirm that prune does not hang
  git lfs prune --dry-run --verify-remote --verbose 2>&1 | tee prune.log
)
end_test

begin_test "prune unreachable"
(
  set -e

  reponame="prune_unreachable"
  setup_remote_repo "remote_$reponame"

  clone_repo "remote_$reponame" "clone_$reponame"

  git lfs track "*.dat" 2>&1 | tee track.log
  grep "Tracking \"\*.dat\"" track.log

  content_head="HEAD content"
  content_orphan="orphan content (not pruned)"
  content_commit3="Content for commit 3 (prune)"
  content_commit2="Content for commit 2"
  content_commit1="Content for commit 1 (prune)"
  oid_head=$(calc_oid "$content_head")
  oid_orphan=$(calc_oid "$content_orphan")
  oid_commit3=$(calc_oid "$content_commit3")
  oid_commit2=$(calc_oid "$content_commit2")
  oid_commit1=$(calc_oid "$content_commit1")

  echo "[
  {
    \"CommitDate\":\"$(get_date -50d)\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_commit1}, \"Data\":\"$content_commit1\"}]
  },
  {
    \"CommitDate\":\"$(get_date -40d)\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_commit2}, \"Data\":\"$content_commit2\"}]
  },
  {
    \"CommitDate\":\"$(get_date -35d)\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_commit3}, \"Data\":\"$content_commit3\"}]
  },
  {
    \"CommitDate\":\"$(get_date -25d)\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_head}, \"Data\":\"$content_head\"}]
  }
  ]" | lfstest-testutils addcommits

  # push all so no unpushed reason to not prune
  git push origin main

  # set no recents so max ability to prune normally
  git config lfs.fetchrecentrefsdays 0
  git config lfs.fetchrecentremoterefs true
  git config lfs.fetchrecentcommitsdays 0
  git config lfs.pruneoffsetdays 1

  # add one file to the index and then remove it to see if unreachable files are pruned
  echo -n "$content_orphan" > file.dat
  git add file.dat
  git reset file.dat

  # confirm that it would prune without --verify-unreachable
  git lfs prune --dry-run --verify-remote --verbose 2>&1 | tee prune.log
  grep "5 local objects, 1 retained, 3 verified with remote, done." prune.log
  grep "4 files would be pruned" prune.log
  grep "$oid_commit3" prune.log
  grep "$oid_commit2" prune.log
  grep "$oid_commit1" prune.log
  grep "$oid_orphan" prune.log

  # this should now halt as one file cannot be verified
  git lfs prune --verify-remote --verify-unreachable 2>&1 | tee prune.log
  grep "5 local objects, 1 retained, 3 verified with remote, 1 not on remote, done." prune.log
  grep "missing on remote:" prune.log
  grep "$oid_orphan" prune.log

  # No files should have been deleted
  assert_local_object "$oid_head" "${#content_head}"
  assert_local_object "$oid_commit1" "${#content_commit1}"
  assert_local_object "$oid_commit2" "${#content_commit2}"
  assert_local_object "$oid_commit3" "${#content_commit3}"
  assert_local_object "$oid_orphan" "${#content_orphan}"

  # test config option
  git config lfs.pruneverifyunreachablealways true
  git lfs prune --verify-remote 2>&1 | tee prune.log
  grep "5 local objects, 1 retained, 3 verified with remote, 1 not on remote, done." prune.log
  grep "missing on remote:" prune.log
  grep "$oid_orphan" prune.log

  # now try overriding the global option
  git lfs prune --verify-remote --no-verify-unreachable --dry-run 2>&1 | tee prune.log
  grep "5 local objects, 1 retained, 3 verified with remote, done." prune.log
  grep "4 files would be pruned" prune.log

  # now test with continue to see that it does prune verified objects
  git lfs prune --verify-remote --when-unverified=continue 2>&1 | tee prune.log
  grep "5 local objects, 1 retained, 3 verified with remote, 1 not on remote, done." prune.log
  grep "Deleting objects: 100% (3/3), done." prune.log

  # The orphan file should not have been deleted
  refute_local_object "$oid_commit1" "${#content_commit1}"
  refute_local_object "$oid_commit2" "${#content_commit2}"
  refute_local_object "$oid_commit3" "${#content_commit3}"
  assert_local_object "$oid_orphan" "${#content_orphan}"
)
end_test

begin_test "prune keep stashed changes"
(
  set -e

  reponame="prune_keep_stashed"
  setup_remote_repo "remote_$reponame"

  clone_repo "remote_$reponame" "clone_$reponame"

  git lfs track "*.dat" 2>&1 | tee track.log
  grep "Tracking \"\*.dat\"" track.log

  # generate content we'll use
  content_oldandpushed="To delete: pushed and too old"
  oid_oldandpushed=$(calc_oid "$content_oldandpushed")
  content_unreferenced="To delete: unreferenced"
  oid_unreferenced=$(calc_oid "$content_unreferenced")
  content_retain1="Retained content 1"
  oid_retain1=$(calc_oid "$content_retain1")

  content_inrepo="This is the original committed data"
  oid_inrepo=$(calc_oid "$content_inrepo")
  content_stashed="This data will be stashed and should not be deleted"
  oid_stashed=$(calc_oid "$content_stashed")
  content_stashedandexcluded="This data will be stashed and should not be deleted despite being excluded"
  oid_stashedandexcluded=$(calc_oid "$content_stashedandexcluded")
  content_stashedbranch="This data will be stashed on a branch and should not be deleted"
  oid_stashedbranch=$(calc_oid "$content_stashedbranch")
  content_stashedandexcludedbranch="This data will be stashed on a branch and should not be deleted despite being excluded"
  oid_stashedandexcludedbranch=$(calc_oid "$content_stashedandexcludedbranch")

  # We need to test with older commits to ensure they get pruned as expected
  echo "[
  {
    \"CommitDate\":\"$(get_date -20d)\",
    \"Files\":[
      {\"Filename\":\"old.dat\",\"Size\":${#content_oldandpushed}, \"Data\":\"$content_oldandpushed\"}]
  },
  {
    \"CommitDate\":\"$(get_date -7d)\",
    \"Files\":[
      {\"Filename\":\"old.dat\",\"Size\":${#content_retain1}, \"Data\":\"$content_retain1\"}]
  },
  {
    \"CommitDate\":\"$(get_date -4d)\",
    \"NewBranch\":\"branch_to_delete\",
    \"Files\":[
      {\"Filename\":\"unreferenced.dat\",\"Size\":${#content_unreferenced}, \"Data\":\"$content_unreferenced\"},
      {\"Filename\":\"foo/unreferenced.dat\",\"Size\":${#content_unreferenced}, \"Data\":\"$content_unreferenced\"}]
  },
  {
    \"CommitDate\":\"$(get_date -1d)\",
    \"ParentBranches\":[\"main\"],
    \"Files\":[
      {\"Filename\":\"stashedfile.dat\",\"Size\":${#content_inrepo}, \"Data\":\"$content_inrepo\"},
      {\"Filename\":\"foo/stashedfile.dat\",\"Size\":${#content_inrepo}, \"Data\":\"$content_inrepo\"}]
  }
  ]" | lfstest-testutils addcommits

  git push origin main

  assert_local_object "$oid_oldandpushed" "${#content_oldandpushed}"
  assert_local_object "$oid_unreferenced" "${#content_unreferenced}"
  assert_local_object "$oid_retain1" "${#content_retain1}"

  # now modify the files, and stash them
  printf '%s' "$content_stashed" > stashedfile.dat
  printf '%s' "$content_stashedandexcluded" > foo/stashedfile.dat
  git stash

  # Switch to a branch, modify files, stash them, and delete the branch.
  git checkout branch_to_delete
  printf '%s' "$content_stashedbranch" > unreferenced.dat
  printf '%s' "$content_stashedandexcludedbranch" > foo/unreferenced.dat
  git stash
  git checkout main
  git branch -D branch_to_delete

  # Prove that the stashed data was stored in LFS (should call clean filter)
  assert_local_object "$oid_stashed" "${#content_stashed}"
  assert_local_object "$oid_stashedandexcluded" "${#content_stashedandexcluded}"
  assert_local_object "$oid_stashedbranch" "${#content_stashedbranch}"
  assert_local_object "$oid_stashedandexcludedbranch" "${#content_stashedandexcludedbranch}"

  # We need to prevent MSYS from rewriting /foo into a Windows path.
  MSYS_NO_PATHCONV=1 git config "lfs.fetchexclude" "/foo"

  # force color codes in git diff meta-information
  git config color.diff always

  # Prune data, should NOT delete stashed files
  git lfs prune

  refute_local_object "$oid_oldandpushed" "${#content_oldandpushed}"
  refute_local_object "$oid_unreferenced" "${#content_unreferenced}"
  assert_local_object "$oid_retain1" "${#content_retain1}"
  assert_local_object "$oid_stashed" "${#content_stashed}"
  assert_local_object "$oid_stashedandexcluded" "${#content_stashedandexcluded}"
  assert_local_object "$oid_stashedbranch" "${#content_stashedbranch}"
  assert_local_object "$oid_stashedandexcludedbranch" "${#content_stashedandexcludedbranch}"
)
end_test

begin_test "prune keep stashed changes in index"
(
  set -e

  reponame="prune_keep_stashed_index"
  setup_remote_repo "remote_$reponame"

  clone_repo "remote_$reponame" "clone_$reponame"

  git lfs track "*.dat" 2>&1 | tee track.log
  grep "Tracking \"\*.dat\"" track.log

  # generate content we'll use
  content_oldandpushed="To delete: pushed and too old"
  oid_oldandpushed=$(calc_oid "$content_oldandpushed")
  content_unreferenced="To delete: unreferenced"
  oid_unreferenced=$(calc_oid "$content_unreferenced")
  content_retain1="Retained content 1"
  oid_retain1=$(calc_oid "$content_retain1")

  content_inrepo="This is the original committed data"
  oid_inrepo=$(calc_oid "$content_inrepo")
  content_indexstashed="This data will be stashed from the index and should not be deleted"
  oid_indexstashed=$(calc_oid "$content_indexstashed")
  content_indexstashedandexcluded="This data will be stashed from the index and should not be deleted despite being excluded"
  oid_indexstashedandexcluded=$(calc_oid "$content_indexstashedandexcluded")
  content_stashed="This data will be stashed and should not be deleted"
  oid_stashed=$(calc_oid "$content_stashed")
  content_stashedandexcluded="This data will be stashed and should not be deleted despite being excluded"
  oid_stashedandexcluded=$(calc_oid "$content_stashedandexcluded")
  content_indexstashedbranch="This data will be stashed on a branch from the index and should not be deleted"
  oid_indexstashedbranch=$(calc_oid "$content_indexstashedbranch")
  content_indexstashedandexcludedbranch="This data will be stashed on a branch from the index and should not be deleted despite being excluded"
  oid_indexstashedandexcludedbranch=$(calc_oid "$content_indexstashedandexcludedbranch")
  content_stashedbranch="This data will be stashed on a branch and should not be deleted"
  oid_stashedbranch=$(calc_oid "$content_stashedbranch")
  content_stashedandexcludedbranch="This data will be stashed on a branch and should not be deleted despite being excluded"
  oid_stashedandexcludedbranch=$(calc_oid "$content_stashedandexcludedbranch")

  # We need to test with older commits to ensure they get pruned as expected
  echo "[
  {
    \"CommitDate\":\"$(get_date -20d)\",
    \"Files\":[
      {\"Filename\":\"old.dat\",\"Size\":${#content_oldandpushed}, \"Data\":\"$content_oldandpushed\"}]
  },
  {
    \"CommitDate\":\"$(get_date -7d)\",
    \"Files\":[
      {\"Filename\":\"old.dat\",\"Size\":${#content_retain1}, \"Data\":\"$content_retain1\"}]
  },
  {
    \"CommitDate\":\"$(get_date -4d)\",
    \"NewBranch\":\"branch_to_delete\",
    \"Files\":[
      {\"Filename\":\"unreferenced.dat\",\"Size\":${#content_unreferenced}, \"Data\":\"$content_unreferenced\"},
      {\"Filename\":\"foo/unreferenced.dat\",\"Size\":${#content_unreferenced}, \"Data\":\"$content_unreferenced\"}]
  },
  {
    \"CommitDate\":\"$(get_date -1d)\",
    \"ParentBranches\":[\"main\"],
    \"Files\":[
      {\"Filename\":\"stashedfile.dat\",\"Size\":${#content_inrepo}, \"Data\":\"$content_inrepo\"},
      {\"Filename\":\"foo/stashedfile.dat\",\"Size\":${#content_inrepo}, \"Data\":\"$content_inrepo\"}]
  }
  ]" | lfstest-testutils addcommits

  git push origin main

  assert_local_object "$oid_oldandpushed" "${#content_oldandpushed}"
  assert_local_object "$oid_unreferenced" "${#content_unreferenced}"
  assert_local_object "$oid_retain1" "${#content_retain1}"

  # now modify the files, and add them to the index
  printf '%s' "$content_indexstashed" > stashedfile.dat
  printf '%s' "$content_indexstashedandexcluded" > foo/stashedfile.dat
  git add stashedfile.dat foo/stashedfile.dat

  # now modify the files again, and stash them
  printf '%s' "$content_stashed" > stashedfile.dat
  printf '%s' "$content_stashedandexcluded" > foo/stashedfile.dat
  git stash

  # Switch to a branch, modify files in the index and working tree, stash them,
  # and delete the branch.
  git checkout branch_to_delete
  printf '%s' "$content_indexstashedbranch" > unreferenced.dat
  printf '%s' "$content_indexstashedandexcludedbranch" > foo/unreferenced.dat
  git add unreferenced.dat foo/unreferenced.dat
  printf '%s' "$content_stashedbranch" > unreferenced.dat
  printf '%s' "$content_stashedandexcludedbranch" > foo/unreferenced.dat
  git stash
  git checkout main
  git branch -D branch_to_delete

  # Prove that the stashed data was stored in LFS (should call clean filter)
  assert_local_object "$oid_indexstashed" "${#content_indexstashed}"
  assert_local_object "$oid_indexstashedandexcluded" "${#content_indexstashedandexcluded}"
  assert_local_object "$oid_stashed" "${#content_stashed}"
  assert_local_object "$oid_stashedandexcluded" "${#content_stashedandexcluded}"
  assert_local_object "$oid_indexstashedbranch" "${#content_indexstashedbranch}"
  assert_local_object "$oid_indexstashedandexcludedbranch" "${#content_indexstashedandexcludedbranch}"
  assert_local_object "$oid_stashedbranch" "${#content_stashedbranch}"
  assert_local_object "$oid_stashedandexcludedbranch" "${#content_stashedandexcludedbranch}"

  # We need to prevent MSYS from rewriting /foo into a Windows path.
  MSYS_NO_PATHCONV=1 git config "lfs.fetchexclude" "/foo"

  # force color codes in git diff meta-information
  git config color.diff always

  # Prune data, should NOT delete stashed file or stashed changes to index
  git lfs prune

  refute_local_object "$oid_oldandpushed" "${#content_oldandpushed}"
  refute_local_object "$oid_unreferenced" "${#content_unreferenced}"
  assert_local_object "$oid_retain1" "${#content_retain1}"
  assert_local_object "$oid_indexstashed" "${#content_indexstashed}"
  assert_local_object "$oid_indexstashedandexcluded" "${#content_indexstashedandexcluded}"
  assert_local_object "$oid_stashed" "${#content_stashed}"
  assert_local_object "$oid_stashedandexcluded" "${#content_stashedandexcluded}"
  assert_local_object "$oid_indexstashedbranch" "${#content_indexstashedbranch}"
  assert_local_object "$oid_indexstashedandexcludedbranch" "${#content_indexstashedandexcludedbranch}"
  assert_local_object "$oid_stashedbranch" "${#content_stashedbranch}"
  assert_local_object "$oid_stashedandexcludedbranch" "${#content_stashedandexcludedbranch}"
)
end_test

begin_test "prune keep stashed untracked files"
(
  set -e

  reponame="prune_keep_stashed_untracked"
  setup_remote_repo "remote_$reponame"

  clone_repo "remote_$reponame" "clone_$reponame"

  git lfs track "*.dat" 2>&1 | tee track.log
  grep "Tracking \"\*.dat\"" track.log

  # Commit .gitattributes first so it is not removed by "git stash -u" and then
  # not restored when we checkout the branch and try to modify LFS objects.
  git add .gitattributes
  git commit -m attribs

  # generate content we'll use
  content_oldandpushed="To delete: pushed and too old"
  oid_oldandpushed=$(calc_oid "$content_oldandpushed")
  content_unreferenced="To delete: unreferenced"
  oid_unreferenced=$(calc_oid "$content_unreferenced")
  content_retain1="Retained content 1"
  oid_retain1=$(calc_oid "$content_retain1")

  content_inrepo="This is the original committed data"
  oid_inrepo=$(calc_oid "$content_inrepo")
  content_indexstashed="This data will be stashed from the index and should not be deleted"
  oid_indexstashed=$(calc_oid "$content_indexstashed")
  content_indexstashedandexcluded="This data will be stashed from the index and should not be deleted despite being excluded"
  oid_indexstashedandexcluded=$(calc_oid "$content_indexstashedandexcluded")
  content_stashed="This data will be stashed and should not be deleted"
  oid_stashed=$(calc_oid "$content_stashed")
  content_stashedandexcluded="This data will be stashed and should not be deleted despite being excluded"
  oid_stashedandexcluded=$(calc_oid "$content_stashedandexcluded")
  content_untrackedstashed="This UNTRACKED FILE data will be stashed and should not be deleted"
  oid_untrackedstashed=$(calc_oid "$content_untrackedstashed")
  content_untrackedstashedandexcluded="This UNTRACKED FILE data will be stashed and should not be deleted despite being excluded"
  oid_untrackedstashedandexcluded=$(calc_oid "$content_untrackedstashedandexcluded")
  content_indexstashedbranch="This data will be stashed on a branch from the index and should not be deleted"
  oid_indexstashedbranch=$(calc_oid "$content_indexstashedbranch")
  content_indexstashedandexcludedbranch="This data will be stashed on a branch from the index and should not be deleted despite being excluded"
  oid_indexstashedandexcludedbranch=$(calc_oid "$content_indexstashedandexcludedbranch")
  content_stashedbranch="This data will be stashed on a branch and should not be deleted"
  oid_stashedbranch=$(calc_oid "$content_stashedbranch")
  content_stashedandexcludedbranch="This data will be stashed on a branch and should not be deleted despite being excluded"
  oid_stashedandexcludedbranch=$(calc_oid "$content_stashedandexcludedbranch")
  content_untrackedstashedbranch="This UNTRACKED FILE data will be stashed on a branch and should not be deleted"
  oid_untrackedstashedbranch=$(calc_oid "$content_untrackedstashedbranch")
  content_untrackedstashedandexcludedbranch="This UNTRACKED FILE data will be stashed on a branch and should not be deleted despite being excluded"
  oid_untrackedstashedandexcludedbranch=$(calc_oid "$content_untrackedstashedandexcludedbranch")

  # We need to test with older commits to ensure they get pruned as expected
  echo "[
  {
    \"CommitDate\":\"$(get_date -20d)\",
    \"Files\":[
      {\"Filename\":\"old.dat\",\"Size\":${#content_oldandpushed}, \"Data\":\"$content_oldandpushed\"}]
  },
  {
    \"CommitDate\":\"$(get_date -7d)\",
    \"Files\":[
      {\"Filename\":\"old.dat\",\"Size\":${#content_retain1}, \"Data\":\"$content_retain1\"}]
  },
  {
    \"CommitDate\":\"$(get_date -4d)\",
    \"NewBranch\":\"branch_to_delete\",
    \"Files\":[
      {\"Filename\":\"unreferenced.dat\",\"Size\":${#content_unreferenced}, \"Data\":\"$content_unreferenced\"},
      {\"Filename\":\"foo/unreferenced.dat\",\"Size\":${#content_unreferenced}, \"Data\":\"$content_unreferenced\"}]
  },
  {
    \"CommitDate\":\"$(get_date -1d)\",
    \"ParentBranches\":[\"main\"],
    \"Files\":[
      {\"Filename\":\"stashedfile.dat\",\"Size\":${#content_inrepo}, \"Data\":\"$content_inrepo\"},
      {\"Filename\":\"foo/stashedfile.dat\",\"Size\":${#content_inrepo}, \"Data\":\"$content_inrepo\"}]
  }
  ]" | lfstest-testutils addcommits

  git push origin main

  assert_local_object "$oid_oldandpushed" "${#content_oldandpushed}"
  assert_local_object "$oid_unreferenced" "${#content_unreferenced}"
  assert_local_object "$oid_retain1" "${#content_retain1}"

  # now modify the files, and add them to the index
  printf '%s' "$content_indexstashed" > stashedfile.dat
  printf '%s' "$content_indexstashedandexcluded" > foo/stashedfile.dat
  git add stashedfile.dat foo/stashedfile.dat

  # now modify the files again, and stash them
  printf '%s' "$content_stashed" > stashedfile.dat
  printf '%s' "$content_stashedandexcluded" > foo/stashedfile.dat

  # Also create untracked files
  printf '%s' "$content_untrackedstashed" > untrackedfile.dat
  printf '%s' "$content_untrackedstashedandexcluded" > foo/untrackedfile.dat

  # stash, including untracked
  git stash -u

  # Switch to a branch, modify files in the index and working tree and create
  # untracked files, stash them, and delete the branch.
  git checkout branch_to_delete
  printf '%s' "$content_indexstashedbranch" > unreferenced.dat
  printf '%s' "$content_indexstashedandexcludedbranch" > foo/unreferenced.dat
  git add unreferenced.dat foo/unreferenced.dat
  printf '%s' "$content_stashedbranch" > unreferenced.dat
  printf '%s' "$content_stashedandexcludedbranch" > foo/unreferenced.dat
  printf '%s' "$content_untrackedstashedbranch" > untrackedfile.dat
  printf '%s' "$content_untrackedstashedandexcludedbranch" > foo/untrackedfile.dat
  git stash -u
  git checkout main
  git branch -D branch_to_delete

  # Prove that ALL stashed data was stored in LFS (should call clean filter)
  assert_local_object "$oid_indexstashed" "${#content_indexstashed}"
  assert_local_object "$oid_indexstashedandexcluded" "${#content_indexstashedandexcluded}"
  assert_local_object "$oid_stashed" "${#content_stashed}"
  assert_local_object "$oid_stashedandexcluded" "${#content_stashedandexcluded}"
  assert_local_object "$oid_untrackedstashed" "${#content_untrackedstashed}"
  assert_local_object "$oid_untrackedstashedandexcluded" "${#content_untrackedstashedandexcluded}"
  assert_local_object "$oid_indexstashedbranch" "${#content_indexstashedbranch}"
  assert_local_object "$oid_indexstashedandexcludedbranch" "${#content_indexstashedandexcludedbranch}"
  assert_local_object "$oid_stashedbranch" "${#content_stashedbranch}"
  assert_local_object "$oid_stashedandexcludedbranch" "${#content_stashedandexcludedbranch}"
  assert_local_object "$oid_untrackedstashedbranch" "${#content_untrackedstashedbranch}"
  assert_local_object "$oid_untrackedstashedandexcludedbranch" "${#content_untrackedstashedandexcludedbranch}"

  # We need to prevent MSYS from rewriting /foo into a Windows path.
  MSYS_NO_PATHCONV=1 git config "lfs.fetchexclude" "/foo"

  # force color codes in git diff meta-information
  git config color.diff always

  # Prune data, should NOT delete stashed file or stashed changes to index
  git lfs prune

  refute_local_object "$oid_oldandpushed" "${#content_oldandpushed}"
  refute_local_object "$oid_unreferenced" "${#content_unreferenced}"
  assert_local_object "$oid_retain1" "${#content_retain1}"
  assert_local_object "$oid_indexstashed" "${#content_indexstashed}"
  assert_local_object "$oid_indexstashedandexcluded" "${#content_indexstashedandexcluded}"
  assert_local_object "$oid_stashed" "${#content_stashed}"
  assert_local_object "$oid_stashedandexcluded" "${#content_stashedandexcluded}"
  assert_local_object "$oid_untrackedstashed" "${#content_untrackedstashed}"
  assert_local_object "$oid_untrackedstashedandexcluded" "${#content_untrackedstashedandexcluded}"
  assert_local_object "$oid_indexstashedbranch" "${#content_indexstashedbranch}"
  assert_local_object "$oid_indexstashedandexcludedbranch" "${#content_indexstashedandexcludedbranch}"
  assert_local_object "$oid_stashedbranch" "${#content_stashedbranch}"
  assert_local_object "$oid_stashedandexcludedbranch" "${#content_stashedandexcludedbranch}"
  assert_local_object "$oid_untrackedstashedbranch" "${#content_untrackedstashedbranch}"
  assert_local_object "$oid_untrackedstashedandexcludedbranch" "${#content_untrackedstashedandexcludedbranch}"
)
end_test

begin_test "prune recent changes with --recent"
(
  set -e

  reponame="prune_recent_arg"
  setup_remote_repo "remote_$reponame"

  clone_repo "remote_$reponame" "clone_$reponame"

  git lfs track "*.dat"

  # generate content we'll use
  content_inrepo="this is the original committed data"
  oid_inrepo=$(calc_oid "$content_inrepo")
  content_new="this data will be recent"
  oid_new=$(calc_oid "$content_new")
  content_stashed="This data will be stashed and should not be deleted"
  oid_stashed=$(calc_oid "$content_stashed")

  echo "[
  {
    \"CommitDate\":\"$(get_date -1d)\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_inrepo}, \"Data\":\"$content_inrepo\"}]
  }
  ]" | lfstest-testutils addcommits

  # now modify the file, and commit it
  printf '%s' "$content_new" > file.dat
  git add .
  git commit -m 'Update file.dat'

  # now modify the file, and stash it
  printf '%s' "$content_stashed" > file.dat
  git stash

  git config lfs.fetchrecentrefsdays 5
  git config lfs.fetchrecentremoterefs true
  git config lfs.fetchrecentcommitsdays 3

  assert_local_object "$oid_new" "${#content_new}"
  assert_local_object "$oid_inrepo" "${#content_inrepo}"
  assert_local_object "$oid_stashed" "${#content_stashed}"

  # prune data, should not delete.
  git lfs prune --recent

  assert_local_object "$oid_new" "${#content_new}"
  assert_local_object "$oid_inrepo" "${#content_inrepo}"
  assert_local_object "$oid_stashed" "${#content_stashed}"

  git push origin HEAD

  # prune data.
  git lfs prune --recent

  assert_local_object "$oid_new" "${#content_new}"
  refute_local_object "$oid_inrepo" "${#content_inrepo}"
  assert_local_object "$oid_stashed" "${#content_stashed}"
)
end_test

begin_test "prune keep files in index"
(
  set -e

  reponame="prune_index"
  setup_remote_repo "remote_$reponame"

  clone_repo "remote_$reponame" "clone_$reponame"

  git lfs track "*.dat"

  # generate content we'll use
  content_inrepo="this is the original committed data"
  oid_inrepo=$(calc_oid "$content_inrepo")
  content_new="this data will be indexed"
  oid_new=$(calc_oid "$content_new")
  content_untracked="This data will be untracked and added to the index and should not be deleted"
  oid_untracked=$(calc_oid "$content_untracked")

  echo "[
  {
    \"CommitDate\":\"$(get_date -1d)\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_inrepo}, \"Data\":\"$content_inrepo\"}]
  }
  ]" | lfstest-testutils addcommits

  # now modify the file, and add it to the index
  printf '%s' "$content_new" > file.dat
  git add .

  # now add the file, and add it to the index
  printf '%s' "$content_untracked" > untracked.dat
  git add .

  assert_local_object "$oid_new" "${#content_new}"
  assert_local_object "$oid_inrepo" "${#content_inrepo}"
  assert_local_object "$oid_untracked" "${#content_untracked}"

  # prune data, should not delete.
  git lfs prune

  assert_local_object "$oid_new" "${#content_new}"
  assert_local_object "$oid_inrepo" "${#content_inrepo}"
  assert_local_object "$oid_untracked" "${#content_untracked}"

  git push origin HEAD

  # force prune data should not delete in index
  git lfs prune --force

  assert_local_object "$oid_new" "${#content_new}"
  refute_local_object "$oid_inrepo" "${#content_inrepo}"
  assert_local_object "$oid_untracked" "${#content_untracked}"
)
end_test

begin_test "prune --force"
(
  set -e

  reponame="prune_force"
  setup_remote_repo "remote_$reponame"

  clone_repo "remote_$reponame" "clone_$reponame"

  git lfs track "*.dat"

  # generate content we'll use
  content_inrepo="this is the original committed data"
  oid_inrepo=$(calc_oid "$content_inrepo")
  content_new="this data will be recent"
  oid_new=$(calc_oid "$content_new")
  content_stashed="This data will be stashed and should not be deleted"
  oid_stashed=$(calc_oid "$content_stashed")

  echo "[
  {
    \"CommitDate\":\"$(get_date -1d)\",
    \"Files\":[
      {\"Filename\":\"file.dat\",\"Size\":${#content_inrepo}, \"Data\":\"$content_inrepo\"}]
  }
  ]" | lfstest-testutils addcommits

  # now modify the file, and commit it
  printf '%s' "$content_new" > file.dat
  git add .
  git commit -m 'Update file.dat'

  # now modify the file, and stash it
  printf '%s' "$content_stashed" > file.dat
  git stash

  git config lfs.fetchrecentrefsdays 5
  git config lfs.fetchrecentremoterefs true
  git config lfs.fetchrecentcommitsdays 3

  assert_local_object "$oid_new" "${#content_new}"
  assert_local_object "$oid_inrepo" "${#content_inrepo}"
  assert_local_object "$oid_stashed" "${#content_stashed}"

  # prune data, should not delete.
  git lfs prune --force

  assert_local_object "$oid_new" "${#content_new}"
  assert_local_object "$oid_inrepo" "${#content_inrepo}"
  assert_local_object "$oid_stashed" "${#content_stashed}"

  git push origin HEAD

  # prune data.
  git lfs prune --force

  refute_local_object "$oid_new" "${#content_new}"
  refute_local_object "$oid_inrepo" "${#content_inrepo}"
  assert_local_object "$oid_stashed" "${#content_stashed}"
)
end_test

begin_test "prune does not fail on empty files"
(
  set -e

  reponame="prune-empty-file"
  setup_remote_repo "remote-$reponame"

  clone_repo "remote-$reponame" "clone-$reponame"

  git lfs track "*.dat" 2>&1 | tee track.log
  grep "Tracking \"\*.dat\"" track.log

  touch empty.dat
  git add .gitattributes empty.dat
  git commit -m 'Add empty'
  git push origin main

  git lfs prune --force
)
end_test

begin_test "prune does not invoke external diff programs"
(
  set -e

  reponame="prune-external-diff"
  setup_remote_repo "remote-$reponame"

  clone_repo "remote-$reponame" "clone-$reponame"

  git config diff.word.textconv 'false'
  echo "*.dot diff=word" >.git/info/attributes

  for n in $(seq 1000); do (echo "$n" > "$n.dot") done
  git add .
  git commit -am "initial"
  git lfs prune
)
end_test

begin_test "prune doesn't hang on long lines in diff"
(
    set -e

    reponame="prune_longlines"
    git init "$reponame"
    cd "$reponame"

    git lfs track "*.dat" 2>&1 | tee track.log
    grep "Tracking \"\*.dat\"" track.log

    echo "test data" >test.dat
    git add .gitattributes test.dat

    git commit -m tracked

    git lfs untrack "*.dat" 2>&1 | tee untrack.log
    grep "Untracking \"\*.dat\"" untrack.log

    # Exceed the default buffer size that would be used by bufio.Scanner
    dd if=/dev/zero bs=1024 count=128 | tr '\0' 'A' >test.dat
    git add .gitattributes test.dat

    git commit -m untracked

    git lfs prune
)
end_test

begin_test "prune doesn't hang on long lines in stash diff"
(
    set -e

    reponame="prune_longlines"
    git init "$reponame"
    cd "$reponame"

    git lfs track "*.dat" 2>&1 | tee track.log
    grep "Tracking \"\*.dat\"" track.log

    echo "test data" >test.dat
    git add .gitattributes test.dat

    git commit -m tracked

    git lfs untrack "*.dat" 2>&1 | tee untrack.log
    grep "Untracking \"\*.dat\"" untrack.log

    # Exceed the default buffer size that would be used by bufio.Scanner
    dd if=/dev/zero bs=1024 count=128 | tr '\0' 'A' >test.dat
    git stash

    git lfs prune
)
end_test
