# Apple login OFF integration candidate

Base main: 986ac4d51d9c0298d5cd04a6d38d8d373f697094.
Source PR1420: 1427ce7f8ea00da207044d315fa17b1e1f44f72d, dedicated baseline 22ba6ec4349c66a14244fc76f0e823a0831ae142.

All 52 changed files were compared against both baseline and current main. No divergent existing-file changes were found. The only modified existing source is tool/prepare_ios.sh, whose original blob matches main. This branch preserves all intervening main changes and uses source blobs without reimplementation.

Purpose: run the normal full Flutter/iOS workflows on a main-targeted draft; the source PR targets its dedicated baseline and does not run those general branch-specific jobs.

Apple provider, Dart gate and native plist gate remain OFF. This is not production deployment, enablement or real iPhone evidence. Preserve build20/21 and source-pinned build22 preparation. Managed install/unused restoration/subject recovery, hosted configuration, actual keys and endpoint deployment remain separately pending.
