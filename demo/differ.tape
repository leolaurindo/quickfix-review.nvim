Output assets/differ.gif
Set Shell "bash"
Set FontSize 22
Set FontFamily "DejaVu Sans Mono"
Set Width 1200
Set Height 700
Set Padding 20
Set Theme "Catppuccin Mocha"
Set TypingSpeed 20ms
Type "nvim -u demo/differ.lua /tmp/quickfix-review-differ-demo/README.md"
Enter
Sleep 1500ms
Type ":Differ"
Enter
Sleep 1500ms
Type ":QuickfixReviewAdd"
Enter
Type "This changed line deserves an explanation."
Escape
Type "q"
Sleep 1500ms
Enter
Sleep 1500ms
Type ":QuickfixReviewList"
Enter
Sleep 2s
Type ":qa!"
Enter
