Output assets/git-diffs.gif
Set Shell "bash"
Set FontSize 22
Set FontFamily "DejaVu Sans Mono"
Set Width 1200
Set Height 700
Set Padding 20
Set Theme "Catppuccin Mocha"
Set TypingSpeed 20ms
Type "nvim -u demo/git-diffs.lua /tmp/quickfix-review-diffs-demo/example.txt"
Enter
Sleep 1500ms
Type ":QuickfixDiffs"
Enter
Sleep 1500ms
Type "a"
Type "This changed range needs validation coverage."
Escape
Type "q"
Sleep 1500ms
Type ":QuickfixReviewList"
Enter
Sleep 2s
Type ":qa!"
Enter
