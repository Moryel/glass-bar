import AppKit

// Contact selected in Contacts (AppleScript; asks for Automation permission on first use). The bar shows name, call, FaceTime, message, email.
struct Contact: Equatable {
    var name: String
    var phone: String
    var email: String

    static let bundleID = "com.apple.AddressBook"

    /// Called on the work queue.
    static func read() -> Contact? {
        let runScript = """
        set ayr to character id 10
        tell application "Contacts"
            set s to selection
            if (count s) = 0 then return ""
            set p to item 1 of s
            set tel to ""
            try
                set tel to value of first phone of p
            end try
            set ep to ""
            try
                set ep to value of first email of p
            end try
            return (name of p) & ayr & tel & ayr & ep
        end tell
        """
        guard let m = SystemControl.runScript(runScript)?.stringValue, !m.isEmpty else { return nil }
        let p = m.components(separatedBy: "\n")
        guard p.count == 3 else { return nil }
        return Contact(name: p[0], phone: p[1], email: p[2])
    }

    private var phoneNumber: String { phone.filter { $0.isNumber || $0 == "+" } }

    func sendMessage() { open("imessage://\(phoneNumber.isEmpty ? email : phoneNumber)") }
    func call() { if !phoneNumber.isEmpty { open("facetime-audio://\(phoneNumber)") } }
    func videoCall() { open("facetime://\(phoneNumber.isEmpty ? email : phoneNumber)") }
    func sendEmail() { if !email.isEmpty { open("mailto:\(email)") } }

    private func open(_ s: String) {
        guard let u = URL(string: s.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? s) else { return }
        NSWorkspace.shared.open(u)
    }
}
