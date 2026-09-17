tell application "Finder"
	set o to icon view options of window of desktop
	set orig to text size of o
	set text size of o to 4
	set r1 to text size of o
	delay 4
	set text size of o to orig
	set r2 to text size of o
	return {orig, r1, r2}
end tell
