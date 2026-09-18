Output assets/quickfix-list.gif
Set Shell "bash"
Set FontSize 22
Set FontFamily "DejaVu Sans Mono"
Set Width 1200
Set Height 700
Set Padding 20
Set Theme "Catppuccin Mocha"
Set TypingSpeed 20ms

Type "nvim -u demo/quickfix-list.lua /tmp/quickfix-review-grep-demo/session.lua"
Enter
Sleep 1500ms
Type ":vimgrep /TODO/ **/*.lua | copen"
Enter
Sleep 1500ms
Type "a"
Type "Expired sessions need a real validation check."
Escape
Type "q"
Sleep 1500ms
Down
Type "a"
Type "Parsing failures should be returned to the caller."
Escape
Type "q"
Sleep 1500ms
Type ":QuickfixReviewExport"
Enter
Sleep 1500ms
Enter
Type ":DemoShowClipboard"
Enter
Sleep 2s
Type ":qa!"
Enter
