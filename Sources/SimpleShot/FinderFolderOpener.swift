import AppKit
import Carbon

@MainActor
enum FinderFolderOpener {
    // Pass the path as an Apple-event argument, never as executable script text.
    static let scriptSource = """
    property screenshotWindowID : missing value

    on openScreenshotFolder(folderPath)
        set folderAlias to POSIX file folderPath as alias
        tell application "Finder"
            set screenshotWindow to missing value
            if my screenshotWindowID is not missing value then
                if exists Finder window id (my screenshotWindowID) then
                    set screenshotWindow to Finder window id (my screenshotWindowID)
                end if
            end if
            if screenshotWindow is missing value then
                set screenshotWindow to make new Finder window
                set my screenshotWindowID to id of screenshotWindow
            end if
            -- Finder can ignore target in make-window properties. Set it explicitly,
            -- using a stable window ID so reordering windows cannot change the target.
            set screenshotWindow to Finder window id (id of screenshotWindow)
            set target of screenshotWindow to folderAlias
            set collapsed of screenshotWindow to false
            set current view of screenshotWindow to list view
            tell list view options of screenshotWindow
                set sort column to modification date column
                set sort direction of column modification date column to reversed
                set visible of column modification date column to true
            end tell
            set index of screenshotWindow to 1
            activate
            return POSIX path of (target of screenshotWindow as alias)
        end tell
    end openScreenshotFolder
    """

    // Keep the script's window ID between clicks. Never adopt an unrelated window,
    // even if it happens to be displaying the screenshot directory.
    private static var script = NSAppleScript(source: scriptSource)
    private static var finderLaunchDate: Date?

    static func event(for directory: URL) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kASAppleScriptSuite),
            eventID: AEEventID(kASSubroutineEvent), targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(string: "openscreenshotfolder"), forKeyword: AEKeyword(keyASSubroutineName))
        let arguments = NSAppleEventDescriptor.list()
        arguments.insert(NSAppleEventDescriptor(string: directory.path), at: 1)
        event.setParam(arguments, forKeyword: AEKeyword(keyDirectObject))
        return event
    }

    static func open(_ directory: URL) {
        let launchDate = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.launchDate
        if launchDate != finderLaunchDate {
            script = NSAppleScript(source: scriptSource)
            finderLaunchDate = launchDate
        }
        var error: NSDictionary?
        if let script {
            if script.compileAndReturnError(&error) {
                let result = script.executeAppleEvent(event(for: directory), error: &error)
                if error == nil, confirmsDirectory(result.stringValue, expected: directory) { return }
            }
        }
        // Browsing still works if Finder automation is declined or unavailable.
        NSWorkspace.shared.open(directory)
        let alert = NSAlert()
        alert.messageText = "The folder opened, but Finder’s view could not be set"
        if (error?[NSAppleScript.errorNumber] as? NSNumber)?.intValue == -1743 {
            alert.informativeText = "Allow SimpleShot to control Finder in System Settings → Privacy & Security → Automation, then click the screenshot path again. This is separate from Screen Recording permission."
        } else {
            alert.informativeText = (error?[NSAppleScript.errorMessage] as? String)
                ?? "Choose List View in Finder and sort Date Modified with the newest files first."
        }
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    static func confirmsDirectory(_ path: String?, expected directory: URL) -> Bool {
        guard let path, path.hasPrefix("/") else { return false }
        return URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
            == directory.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
