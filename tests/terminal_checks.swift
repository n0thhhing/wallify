import Foundation

func checkTerminalProtocol() {
    var input = TerminalInput()
    func feed(_ text: String) -> [TerminalEvent] { input.feed(Array(text.utf8)) }
    precondition(feed("\u{1b}[<0;12;").isEmpty)
    precondition(feed("5M") == [.mouse(0, 11, 4, false)])
    precondition(feed("\u{1b}[<0;12;5m\u{1b}[D\u{1b}[C ") == [.mouse(0, 11, 4, true), .key(112), .key(110), .key(32)])
    precondition(feed("\u{1b}[<0;;12;5M\u{1b}[<0;0;2M\u{1b}[<999;2;2M").isEmpty)
    precondition(feed("\u{1b}_Gi=1;OK\u{1b}").isEmpty)
    precondition(feed("\\q") == [.key(113)])
    precondition(feed("\u{1b}[" + String(repeating: "1", count: 5000)).isEmpty)
    precondition(feed("q") == [.key(113)])
    let data = Data((0..<9000).map { UInt8($0 % 256) })
    let encoded = kittyImage(data, id: 2, columns: 68, rows: 12, tmux: false)
    let chunks = encoded.components(separatedBy: "\u{1b}_G").dropFirst()
    precondition(chunks.count == 3)
    var payload = ""
    for chunk in chunks {
        let fields = chunk.components(separatedBy: ";")
        let body = fields[1].replacingOccurrences(of: "\u{1b}\\", with: "")
        precondition(body.count <= 4096)
        payload += body
    }
    precondition(Data(base64Encoded: payload) == data)
    precondition(encoded.contains("a=T,f=100,i=2,p=1,C=1,q=2,c=68,r=12,m=1"))
    precondition(chunks.last!.hasPrefix("m=0,q=2;"))
    let tmux = kittyImage(Data([1]), id: 1, columns: 1, rows: 1, tmux: true)
    precondition(tmux.hasPrefix("\u{1b}Ptmux;\u{1b}\u{1b}_G"))
}
