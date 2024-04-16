use base 'basetest';
use strict;
use testapi;

sub run {
    my $self = shift;

    # Export the system and user journals.
    #
    # See <https://www.freedesktop.org/wiki/Software/systemd/export/>.
    select_console('user-virtio-terminal');
    assert_script_run('journalctl --merge --output export | xz > /tmp/journal.xz');
    upload_asset('/tmp/journal.xz', public => 1);
    select_console('x11');
}

1;
