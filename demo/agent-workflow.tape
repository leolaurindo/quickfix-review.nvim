Output assets/agent-workflow.gif

Set Shell "bash"
Set FontSize 22
Set FontFamily "DejaVu Sans Mono"
Set Width 1200
Set Height 700
Set Padding 20
Set Theme "Catppuccin Mocha"
Set TypingSpeed 20ms

Type "nvim -u demo/init.lua /tmp/quickfix-review-agent-demo/auth.lua"
Enter
Sleep 1500ms

# Add two location-aware notes directly from the source buffer.
Type ":2QuickfixReviewAdd"
Enter
Type "Please validate this token before accepting it."
Escape
Type "q"
Sleep 1500ms
Enter
Type ":5QuickfixReviewAdd"
Enter
Type "What should callers receive when validation fails?"
Escape
Type "q"
Sleep 1500ms
Enter

Type ":QuickfixReviewList"
Enter
Sleep 1500ms
Type ":QuickfixReviewSendAgent!"
Enter
Sleep 1500ms
Enter
Type ":DemoShowSentReview"
Enter
Sleep 1500ms
Type ":bdelete!"
Enter
Sleep 1500ms

# The watched response adds two agent findings.
Type ":DemoAgentRespond"
Enter
Sleep 1500ms
Enter
Sleep 1500ms
Enter
Type ":QuickfixReviewList"
Enter
Sleep 1500ms
Down
Down
Sleep 2s
Type ":qa!"
Enter
