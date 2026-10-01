import Foundation
import Darwin

// Apple's Perl bundle identity lets the existing MediaRemote helper read metadata.
let nowPlayingHelperScript = #"""
use strict; use warnings; use Cwd qw(abs_path); use DynaLoader; $| = 1; $SIG{PIPE} = sub { exit(0); }; my $abs; for my $p ($ENV{WALLIFY_FETCHER_DYLIB} || (), qw(zig-out/lib/libmetadata_fetcher.dylib ../Frameworks/libmetadata_fetcher.dylib ../Resources/libmetadata_fetcher.dylib ../Resources/zig-out/lib/libmetadata_fetcher.dylib /Applications/Wallify.app/Contents/Frameworks/libmetadata_fetcher.dylib)) { if ($p && -f $p) { $abs = abs_path($p); last; } } if (!$abs) { exit(1); } my $libref = DynaLoader::dl_load_file($abs) or exit(2); my $sym = DynaLoader::dl_find_symbol($libref, "mrc_printNowPlayingInfo") or exit(3); my $init_sym = DynaLoader::dl_find_symbol($libref, "mrc_notifications_init") or exit(4); my $wait_sym = DynaLoader::dl_find_symbol($libref, "mrc_wait_for_notification") or exit(5); DynaLoader::dl_install_xsub("main::fetch", $sym); DynaLoader::dl_install_xsub("main::init_notifications", $init_sym); DynaLoader::dl_install_xsub("main::wait_notification", $wait_sym); print "$$\n"; init_notifications(); my $wake = 1; $SIG{USR1} = sub { $wake = 1; }; while (1) { if ($wake) { $wake = 0; fetch(); } else { wait_notification(); fetch(); } }
"""#

func runNowPlayingHelper(script: String = nowPlayingHelperScript, receive: ([UInt8]) -> Bool) {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
    process.arguments = ["-e", script]
    var environment = ProcessInfo.processInfo.environment
    environment["PERL_SIGNALS"] = "unsafe"
    process.environment = environment
    process.standardOutput = pipe
    do { try process.run() }
    catch { NSLog("Wallify: metadata helper launch failed: %@", error.localizedDescription); return }
    pipe.fileHandleForWriting.closeFile()
    let fd = dup(pipe.fileHandleForReading.fileDescriptor)
    guard fd >= 0, let stream = fdopen(fd, "r") else {
        if fd >= 0 { close(fd) }
        pipe.fileHandleForReading.closeFile()
        process.terminate(); process.waitUntilExit()
        return
    }
    pipe.fileHandleForReading.closeFile()
    defer {
        setSpotifyHelperPID(-1)
        fclose(stream)
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
    }
    var buffer = [CChar](repeating: 0, count: 4098)
    guard fgets(&buffer, Int32(buffer.count), stream) != nil,
          Int32(String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)) == process.processIdentifier else { return }
    setSpotifyHelperPID(process.processIdentifier)
    var droppingLine = false
    while fgets(&buffer, Int32(buffer.count), stream) != nil {
        let line = String(cString: buffer)
        let complete = line.hasSuffix("\n")
        if droppingLine { droppingLine = !complete; continue }
        guard complete else { droppingLine = true; continue }
        let raw = line.trimmingCharacters(in: CharacterSet(charactersIn: " \r\n"))
        guard receive(Array(raw.utf8)) else { return }
    }
}
