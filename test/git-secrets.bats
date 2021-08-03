#!/usr/bin/env bats
load test_helper

@test "no arguments prints usage instructions" {
  repo_run git-secrets
  [ $status -eq 0 ]
  [ $(expr "${lines[0]}" : "usage: git secrets") -ne 0 ]
}

@test "-h prints help" {
  repo_run git-secrets -h
  [ $(expr "${lines[0]}" : "usage: git secrets") -ne 0 ]
}

@test "Invalid scan filename fails" {
  repo_run git-secrets --scan /path/to/not/there
  [ $status -eq 2 ]
  echo "$output" | grep "No such file"
}

@test "Does not require secrets" {
  git config --unset-all secrets.patterns || true
  repo_run git-secrets --scan $BATS_TEST_FILENAME
  [ $status -eq 0 ]
}

@test "No prohibited matches exits 0" {
  echo 'it is ok' > "$BATS_TMPDIR/test.txt"
  repo_run git-secrets --scan "$BATS_TMPDIR/test.txt"
  [ $status -eq 0 ]
}

@test "Scans all files when no file provided" {
  setup_bad_repo
  repo_run git-secrets --scan
  [ $status -eq 1 ]
}

@test "Scans all files including history" {
  setup_bad_repo
  repo_run git-secrets --scan-history
  [ $status -eq 1 ]
}

@test "Scans all files when no file provided with secret in history" {
  setup_bad_repo_history
  repo_run git-secrets --scan
  [ $status -eq 0 ]
}

@test "Scans all files including history with secret in history" {
  setup_bad_repo_history
  repo_run git-secrets --scan-history
  [ $status -eq 1 ]
}

@test "Scans history with secrets distributed among branches in history" {
  cd $TEST_REPO
  echo '@todo' > $TEST_REPO/history_failure.txt
  git add -A
  git commit -m "Testing history"
  echo 'todo' > $TEST_REPO/history_failure.txt
  git add -A
  git commit -m "Testing history"
  git checkout -b testbranch
  echo '@todo' > $TEST_REPO/history_failure.txt
  git add -A
  git commit -m "Testing history"
  git checkout master
  cd -
  repo_run git-secrets --scan-history
  [ $status -eq 1 ]
}

@test "--scan-between includes the referenced commits" {
  cd $TEST_REPO
  echo '@todo 1' > $TEST_REPO/history_failure_1.txt
  git add -A
  git commit -m "Bad commit 1"
  echo '@todo 2' > $TEST_REPO/history_failure_2.txt
  git add -A
  git commit -m "Bad commit 2"
  echo 'pass 1' > $TEST_REPO/pass_1.txt
  git add -A
  git commit -m "Good commit 1"
  cd -
  repo_run git-secrets --scan-between "HEAD..HEAD"
  [ $status -eq 0 ]

  repo_run git-secrets --scan-between "HEAD~1..HEAD~1"
  [ $status -eq 1 ]
  [[ "${lines[1]}" =~ ^.*:history_failure_2\.txt:1:@todo[[:space:]]2$ ]]

  repo_run git-secrets --scan-between "HEAD~2..HEAD~2"
  [ $status -eq 1 ]
  [[ "${lines[1]}" =~ ^.*:history_failure_1\.txt:1:@todo[[:space:]]1$ ]]

  repo_run git-secrets --scan-between "HEAD~2..HEAD"
  [[ "${lines[1]}" =~ ^.*:history_failure_1\.txt:1:@todo[[:space:]]1.*$ ]]
  [[ "${lines[2]}" =~ ^.*:history_failure_2\.txt:1:@todo[[:space:]]2.*$ ]]
}

@test "--scan-between does not include merges" {
  cd $TEST_REPO
  echo '@todo include' > $TEST_REPO/history_failure_1.txt
  git add -A
  git commit -m "Master commit 1"

  git checkout -b "new-branch"
  touch foo
  git add -A
  git commit -m "New branch commit 1"

  git checkout master
  echo '@todo exclude' > $TEST_REPO/history_failure_2.txt
  git add -A
  git commit -m "Master commit 2"

  git checkout "new-branch"
  git merge master -m "Merge master"
  echo '@todo include' > $TEST_REPO/history_failure_1_new_branch.txt
  git add -A
  git commit -m "Master commit 2"

  repo_run git-secrets --scan-between "HEAD~3..HEAD"
  [ $status -eq 1 ]
  [[ "${lines[1]}" =~ ^.*:history_failure_1\.txt:1:@todo[[:space:]]include.*$ ]]
  [[ "${lines[2]}" =~ ^.*:history_failure_1_new_branch\.txt:1:@todo[[:space:]]include.*$ ]]
  for line in ${lines[*]}; do
    [[ ! "${line}" =~ ^.*exclude.*$ ]]
  done
}

@test "--scan-between fails, two commits, first with secrets" {
  cd $TEST_REPO
  echo '@todo' > $TEST_REPO/history_failure.txt
  git add -A
  git commit -m "Bad commit"
  echo 'hi' > $TEST_REPO/harmless.txt
  git add -A
  git commit -m "Good commit"
  cd -
  repo_run git-secrets --scan-between "HEAD..HEAD"
  [ $status -eq 0 ]
  repo_run git-secrets --scan-between "HEAD~1..HEAD"
  [ $status -eq 1 ]
}

@test "--scan-between fails commit at HEAD~1 with secrets" {
  setup_bad_repo_history
  repo_run git-secrets --scan-between HEAD..HEAD
  [ $status -eq 1 ]
}

@test "--scan-between passes at HEAD without secrets" {
  setup_good_repo_history
  repo_run git-secrets --scan-between HEAD..HEAD
  [ $status -eq 0 ]
}

@test "--scan-between fails with invalid SHA1 hash" {
  repo_run git-secrets --scan-between "abc..def"
  [ $status -eq 1 ]
}

@test "Scans recursively" {
  setup_bad_repo
  mkdir -p $TEST_REPO/foo/bar/baz
  echo '@todo more stuff' > $TEST_REPO/foo/bar/baz/data.txt
  repo_run git-secrets --scan -r $TEST_REPO/foo
  [ $status -eq 1 ]
}

@test "Scans recursively only if -r is given" {
  setup_bad_repo
  mkdir -p $TEST_REPO/foo/bar/baz
  echo '@todo more stuff' > $TEST_REPO/foo/bar/baz/data.txt
  repo_run git-secrets --scan $TEST_REPO/foo
  [ $status -eq 0 ]
}

@test "Excludes allowed patterns from failures" {
  git config --add secrets.patterns 'foo="baz{1,5}"'
  git config --add secrets.allowed 'foo="bazzz"'
  echo 'foo="bazzz" is ok because 3 "z"s' > "$BATS_TMPDIR/test.txt"
  repo_run git-secrets --scan "$BATS_TMPDIR/test.txt"
  [ $status -eq 0 ]
  echo 'This is NOT: ok foo="bazzzz"' > "$BATS_TMPDIR/test.txt"
  repo_run git-secrets --scan "$BATS_TMPDIR/test.txt"
  [ $status -eq 1 ]
}

@test "Prohibited matches exits 1" {
  file="$TEST_REPO/test.txt"
  echo '@todo stuff' > $file
  echo 'this is forbidden right?' >> $file
  repo_run git-secrets --scan $file
  [ $status -eq 1 ]
  [ "${lines[0]}" == "$file:1:@todo stuff" ]
  [ "${lines[1]}" == "$file:2:this is forbidden right?" ]
}

@test "Only matches on word boundaries" {
  file="$TEST_REPO/test.txt"
  # Note that the following does not match as it is not a word.
  echo 'mesa Jar Jar Binks' > $file
  # The following do match because they are in word boundaries.
  echo 'foo.me' >> $file
  echo '"me"' >> $file
  repo_run git-secrets --scan $file
  [ $status -eq 1 ]
  [ "${lines[0]}" == "$file:2:foo.me" ]
  [ "${lines[1]}" == "$file:3:\"me\"" ]
}

@test "Can scan from stdin using -" {
  echo "foo" | "${BATS_TEST_DIRNAME}/../git-secrets" --scan -
  echo "me" | "${BATS_TEST_DIRNAME}/../git-secrets" --scan - && exit 1 || true
}

@test "installs hooks for repo" {
  setup_bad_repo
  repo_run git-secrets --install $TEST_REPO
  [ -f $TEST_REPO/.git/hooks/pre-commit ]
  [ -f $TEST_REPO/.git/hooks/prepare-commit-msg ]
  [ -f $TEST_REPO/.git/hooks/commit-msg ]
}

@test "fails if hook exists and no -f" {
  repo_run git-secrets --install $TEST_REPO
  repo_run git-secrets --install $TEST_REPO
  [ $status -eq 1 ]
}

@test "Overwrites hooks if -f is given" {
  repo_run git-secrets --install $TEST_REPO
  repo_run git-secrets --install -f $TEST_REPO
  [ $status -eq 0 ]
}

@test "installs hooks for repo with Debian style directories" {
  setup_bad_repo
  mkdir $TEST_REPO/.git/hooks/pre-commit.d
  mkdir $TEST_REPO/.git/hooks/prepare-commit-msg.d
  mkdir $TEST_REPO/.git/hooks/commit-msg.d
  run git-secrets --install $TEST_REPO
  [ -f $TEST_REPO/.git/hooks/pre-commit.d/git-secrets ]
  [ -f $TEST_REPO/.git/hooks/prepare-commit-msg.d/git-secrets ]
  [ -f $TEST_REPO/.git/hooks/commit-msg.d/git-secrets ]
}

@test "installs hooks to template directory" {
  setup_bad_repo
  run git-secrets --install $TEMPLATE_DIR
  [ $status -eq 0 ]
  run git init --template $TEMPLATE_DIR
  [ $status -eq 0 ]
  [ -f "${TEST_REPO}/.git/hooks/pre-commit" ]
  [ -f "${TEST_REPO}/.git/hooks/prepare-commit-msg" ]
  [ -f "${TEST_REPO}/.git/hooks/commit-msg" ]
}

@test "Scans using keys from credentials file" {
  echo 'aws_access_key_id = abc123' > $BATS_TMPDIR/test.ini
  echo 'aws_secret_access_key=foobaz' >> $BATS_TMPDIR/test.ini
  echo 'aws_access_key_id = "Bernard"' >> $BATS_TMPDIR/test.ini
  echo 'aws_secret_access_key= "Laverne"' >> $BATS_TMPDIR/test.ini
  echo 'aws_access_key_id= Hoagie+man' >> $BATS_TMPDIR/test.ini
  cd $TEST_REPO
  run git secrets --aws-provider $BATS_TMPDIR/test.ini
  [ $status -eq 0 ]
  echo "$output" | grep -F "foobaz"
  echo "$output" | grep -F "abc123"
  echo "$output" | grep -F "Bernard"
  echo "$output" | grep -F "Laverne"
  echo "$output" | grep -F 'Hoagie\+man'
  run git secrets --add-provider -- git secrets --aws-provider $BATS_TMPDIR/test.ini
  [ $status -eq 0 ]
  echo '(foobaz) test' > $TEST_REPO/bad_file
  echo "abc123 test" >> $TEST_REPO/bad_file
  echo 'Bernard test' >> $TEST_REPO/bad_file
  echo 'Laverne test' >> $TEST_REPO/bad_file
  echo 'Hoagie+man test' >> $TEST_REPO/bad_file
  repo_run git-secrets --scan $TEST_REPO/bad_file
  [ $status -eq 1 ]
  echo "$output" | grep "foobaz"
  echo "$output" | grep "abc123"
  echo "$output" | grep "Bernard"
  echo "$output" | grep "Laverne"
  echo "$output" | grep -F 'Hoagie+man'
}

@test "Lists secrets for a repo" {
  repo_run git-secrets --list
  [ $status -eq 0 ]
  echo "$output" | grep -F 'secrets.patterns @todo'
  echo "$output" | grep -F 'secrets.patterns forbidden|me'
}

@test "Adds secrets to a repo and de-dedupes" {
  repo_run git-secrets --add 'testing+123'
  [ $status -eq 0 ]
  repo_run git-secrets --add 'testing+123'
  [ $status -eq 1 ]
  repo_run git-secrets --add --literal 'testing+abc'
  [ $status -eq 0 ]
  repo_run git-secrets --add -l 'testing+abc'
  [ $status -eq 1 ]
  repo_run git-secrets --list
  echo "$output" | grep -F 'secrets.patterns @todo'
  echo "$output" | grep -F 'secrets.patterns forbidden|me'
  echo "$output" | grep -F 'secrets.patterns testing+123'
  echo "$output" | grep -F 'secrets.patterns testing\+abc'
}

@test "Adds allowed patterns to a repo and de-dedupes" {
  repo_run git-secrets --add -a 'testing+123'
  [ $status -eq 0 ]
  repo_run git-secrets --add --allowed 'testing+123'
  [ $status -eq 1 ]
  repo_run git-secrets --add -a -l 'testing+abc'
  [ $status -eq 0 ]
  repo_run git-secrets --add -a -l 'testing+abc'
  [ $status -eq 1 ]
  repo_run git-secrets --list
  echo "$output" | grep -F 'secrets.patterns @todo'
  echo "$output" | grep -F 'secrets.patterns forbidden|me'
  echo "$output" | grep -F 'secrets.allowed testing+123'
  echo "$output" | grep -F 'secrets.allowed testing\+abc'
}

@test "Empty lines must be ignored in .gitallowed files" {
  setup_bad_repo
  echo '' >> $TEST_REPO/.gitallowed
  repo_run git-secrets --scan
  [ $status -eq 1 ]
}

@test "Comment lines must be ignored in .gitallowed files" {
  setup_bad_repo_with_hash
  repo_run git-secrets --scan
  [ $status -eq 1 ]
  echo '#hash' > $TEST_REPO/.gitallowed
  repo_run git-secrets --scan
  [ $status -eq 1 ]
  echo 'hash' > $TEST_REPO/.gitallowed
  repo_run git-secrets --scan
  [ $status -eq 0 ]
}

@test "Scans all files and allowing none of the bad patterns in .gitallowed" {
  setup_bad_repo
  echo 'hello' > $TEST_REPO/.gitallowed
  repo_run git-secrets --scan
  [ $status -eq 1 ]
}

@test "Scans all files and allowing all bad patterns in .gitallowed" {
  setup_bad_repo
  echo '@todo' > $TEST_REPO/.gitallowed
  echo 'forbidden' >> $TEST_REPO/.gitallowed
  echo 'me' >> $TEST_REPO/.gitallowed
  repo_run git-secrets --scan
  [ $status -eq 0 ]
}

@test "Adds common AWS patterns" {
  repo_run git config --unset-all secrets
  repo_run git-secrets --register-aws
  git config --local --get secrets.providers
  repo_run git-secrets --list
  echo "$output" | grep -F '(A3T[A-Z0-9]|AKIA|AGPA|AIDA|AROA|AIPA|ANPA|ANVA|ASIA)[A-Z0-9]{16}'
  echo "$output" | grep "AKIAIOSFODNN7EXAMPLE"
  echo "$output" | grep "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
}

@test "Adds providers" {
  repo_run git-secrets --add-provider -- echo foo baz bar
  [ $status -eq 0 ]
  repo_run git-secrets --add-provider -- echo bam
  [ $status -eq 0 ]
  repo_run git-secrets --list
  echo "$output" | grep -F 'echo foo baz bar'
  echo "$output" | grep -F 'echo bam'
  echo 'foo baz bar' > $TEST_REPO/bad_file
  echo 'bam' >> $TEST_REPO/bad_file
  repo_run git-secrets --scan $TEST_REPO/bad_file
  [ $status -eq 1 ]
  echo "$output" | grep -F 'foo baz bar'
  echo "$output" | grep -F 'bam'
}

@test "Strips providers that return nothing" {
  repo_run git-secrets --add-provider -- 'echo'
  [ $status -eq 0 ]
  repo_run git-secrets --add-provider -- 'echo 123'
  [ $status -eq 0 ]
  repo_run git-secrets --list
  echo "$output" | grep -F 'echo 123'
  echo 'foo' > $TEST_REPO/bad_file
  repo_run git-secrets --scan $TEST_REPO/bad_file
  [ $status -eq 0 ]
}

@test "--recursive cannot be used with SCAN_*" {
  repo_run git-secrets --scan -r --cached
  [ $status -eq 1 ]
  repo_run git-secrets --scan -r --no-index
  [ $status -eq 1 ]
  repo_run git-secrets --scan -r --untracked
  [ $status -eq 1 ]
}

@test "--recursive can be used with --scan" {
  repo_run git-secrets --scan -r
  [ $status -eq 0 ]
}

@test "--recursive can't be used with --list" {
  repo_run git-secrets --list -r
  [ $status -eq 1 ]
}

@test "-f can only be used with --install" {
  repo_run git-secrets --scan -f
  [ $status -eq 1 ]
}

@test "-a can only be used with --add" {
  repo_run git-secrets --scan -a
  [ $status -eq 1 ]
}

@test "-l can only be used with --add" {
  repo_run git-secrets --scan -l
  [ $status -eq 1 ]
}

@test "--cached can only be used with --scan" {
  repo_run git-secrets --list --cached
  [ $status -eq 1 ]
}

@test "--no-index can only be used with --scan" {
  repo_run git-secrets --list --no-index
  [ $status -eq 1 ]
}

@test "--untracked can only be used with --scan" {
  repo_run git-secrets --list --untracked
  [ $status -eq 1 ]
}
