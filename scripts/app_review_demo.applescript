property appName : "TriColumns"
property stepDelay : 3

on standardWindow(appProcess)
    tell application "System Events"
        repeat 40 times
            try
                return first window of appProcess whose subrole is "AXStandardWindow"
            end try
            delay 0.25
        end repeat
    end tell
    error "TriColumns main window was not found."
end standardWindow

do shell script "/usr/bin/killall TriColumns >/dev/null 2>&1; true"
delay 2

do shell script "/usr/bin/open -n /Applications/TriColumns.app"
delay 5

tell application "System Events"
    tell process appName
        set frontmost to true
        set mainWindow to my standardWindow(it)

        -- Show the offline, fictional workspace without changing saved URLs.
        keystroke "d" using {command down, shift down}
        delay 5

        -- Demonstrate that all three columns remain equal while resizing.
        set size of mainWindow to {1900, 1200}
        set position of mainWindow to {100, 100}
        delay stepDelay
        set size of mainWindow to {2700, 1500}
        set position of mainWindow to {100, 100}
        delay stepDelay

        -- Show the persisted per-column URL settings without modifying them.
        keystroke "," using command down
        delay 5
        keystroke "w" using command down
        delay stepDelay

        -- Return to the sample workspace and leave it visible for the closing shot.
        keystroke "d" using {command down, shift down}
        delay 5
    end tell
end tell

display notification "Review demo flow completed" with title appName
