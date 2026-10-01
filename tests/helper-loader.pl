use strict;
use warnings;
use DynaLoader;
use Cwd qw(abs_path);
open(STDOUT, '>', '/dev/null') or die $!;
my $handle = DynaLoader::dl_load_file(abs_path($ARGV[0])) or die DynaLoader::dl_error();
for my $name (qw(mrc_printNowPlayingInfo mrc_notifications_init mrc_wait_for_notification mrc_sendCommand)) {
    my $symbol = DynaLoader::dl_find_symbol($handle, $name) or die "missing $name";
    DynaLoader::dl_install_xsub("main::$name", $symbol);
}
mrc_notifications_init();
mrc_notifications_init();
mrc_printNowPlayingInfo();
