tell application "Finder"
	set o to icon view options of window of desktop
	set viewInfo to {icon size of o, text size of o, label position of o as text, arrangement of o as text, shows item info of o, shows icon preview of o}
	set n to count of items of desktop
	set namesAndPositions to {name, desktop position, class} of every item of desktop
	return {viewInfo, n, namesAndPositions}
end tell
