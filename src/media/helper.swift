import Foundation
import Darwin

// Perl is the host, but Swift still does the metadata work. Apple's Perl bundle
// identity lets the loaded dylib query MediaRemote in this setup. Keep the loader
// in a child process rather than moving its private API calls into the widget.
// DynaLoader installs the dylib's exported entry points as Perl subs; stdout is
// then a PID handshake followed by one payload per line. Keep diagnostic output
// off stdout, or the parent will read it as metadata.
let nowPlayingHelperScript = #"""
use strict;
use warnings;
use Cwd qw(abs_path);
use DynaLoader;

$| = 1;
$SIG{PIPE} = sub { exit(0); };

# Prefer the explicit path supplied by Swift, then try development and bundle
# layouts. Resolve it before dl_load_file so the loader gets an absolute path.
my $abs;
for my $p ($ENV{WALLIFY_FETCHER_DYLIB} || (), qw(
    build/lib/libmetadata_fetcher.dylib
    ../Frameworks/libmetadata_fetcher.dylib
    ../Resources/libmetadata_fetcher.dylib
    ../Resources/build/lib/libmetadata_fetcher.dylib
    /Applications/Wallify.app/Contents/Frameworks/libmetadata_fetcher.dylib
)) {
    if ($p && -f $p) {
        $abs = abs_path($p);
        last;
    }
}
if (!$abs) { exit(1); }

my $libref = DynaLoader::dl_load_file($abs) or exit(2);
my $sym = DynaLoader::dl_find_symbol($libref, "mrc_printNowPlayingInfo") or exit(3);
my $init_sym = DynaLoader::dl_find_symbol($libref, "mrc_notifications_init") or exit(4);
my $wait_sym = DynaLoader::dl_find_symbol($libref, "mrc_wait_for_notification") or exit(5);
DynaLoader::dl_install_xsub("main::fetch", $sym);
DynaLoader::dl_install_xsub("main::init_notifications", $init_sym);
DynaLoader::dl_install_xsub("main::wait_notification", $wait_sym);

# The parent validates this PID before allowing signals to target the helper.
# Autoflush above makes both the handshake and later snapshots visible at once.
print "$$\n";
init_notifications();
my $wake = 1;
$SIG{USR1} = sub { $wake = 1; };
while (1) {
    if ($wake) {
        $wake = 0;
        fetch();
    } else {
        wait_notification();
        fetch();
    }
}
"""#

func runNowPlayingHelper(script: String = nowPlayingHelperScript, receive: ([UInt8]) -> Bool) {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
    process.arguments = ["-e", script]
    var environment = ProcessInfo.processInfo.environment
    environment["PERL_SIGNALS"] = "unsafe"
    if environment["WALLIFY_FETCHER_DYLIB"] == nil {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let candidates = [Bundle.main.privateFrameworksURL?.appendingPathComponent("libmetadata_fetcher.dylib"),
                          executable.appendingPathComponent("../lib/libmetadata_fetcher.dylib")]
        environment["WALLIFY_FETCHER_DYLIB"] = candidates.compactMap { $0 }.first {
            FileManager.default.fileExists(atPath: $0.path)
        }?.path
    }
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
    // Source changes end this read loop. Close its pipe, terminate the owned child,
    // and reap it before the worker starts another helper.
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
