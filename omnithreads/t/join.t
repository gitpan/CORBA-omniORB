use strict;
use warnings;

BEGIN {
    if ($ENV{'PERL_CORE'}){
        chdir 't';
        unshift @INC, '../lib';
    }
    use Config;
    if (! $Config{'useithreads'}) {
        print("1..0 # Skip: Perl not compiled with 'useithreads'\n");
        exit(0);
    }
}

use ExtUtils::testlib;

use omnithreads;

BEGIN {
    eval {
        require omnithreads::shared;
        import omnithreads::shared;
    };
    if ($@ || ! $omnithreads::shared::threads_shared) {
        print("1..0 # Skip: omnithreads::shared not available\n");
        exit(0);
    }

    $| = 1;
    print("1..17\n");   ### Number of tests that will be run ###
};

my $TEST;
BEGIN {
    share($TEST);
    $TEST = 1;
}

ok(1, 'Loaded');

sub ok {
    my ($ok, $name) = @_;

    lock($TEST);
    my $id = $TEST++;

    # You have to do it this way or VMS will get confused.
    if ($ok) {
        print("ok $id - $name\n");
    } else {
        print("not ok $id - $name\n");
        printf("# Failed test at line %d\n", (caller)[2]);
    }

    return ($ok);
}

sub skip {
    ok(1, '# Skipped: ' . $_[0]);
}


### Start of Testing ###

{
    my $retval = omnithreads->create(sub { return ("hi") })->join();
    ok($retval eq 'hi', "Check basic returnvalue");
}
{
    my ($thread) = omnithreads->create(sub { return (1,2,3) });
    my @retval = $thread->join();
    ok($retval[0] == 1 && $retval[1] == 2 && $retval[2] == 3,'');
}
{
    my $retval = omnithreads->create(sub { return [1] })->join();
    ok($retval->[0] == 1,"Check that a array ref works",);
}
{
    my $retval = omnithreads->create(sub { return { foo => "bar" }})->join();
    ok($retval->{foo} eq 'bar',"Check that hash refs work");
}
{
    my $retval = omnithreads->create( sub {
        open(my $fh, "+>threadtest") || die $!;
        print $fh "test\n";
        return $fh;
    })->join();
    ok(ref($retval) eq 'GLOB', "Check that we can return FH $retval");
    print $retval "test2\n";
    close($retval);
    unlink("threadtest");
}
{
    my $test = "hi";
    my $retval = omnithreads->create(sub { return $_[0]}, \$test)->join();
    ok($$retval eq 'hi','');
}
{
    my $test = "hi";
    share($test);
    my $retval = omnithreads->create(sub { return $_[0]}, \$test)->join();
    ok($$retval eq 'hi','');
    $test = "foo";
    ok($$retval eq 'foo','');
}
{
    my %foo;
    share(%foo);
    omnithreads->create(sub { 
        my $foo;
        share($foo);
        $foo = "thread1";
        return $foo{bar} = \$foo;
    })->join();
    ok(1,"");
}

# We parse ps output so this is OS-dependent.
if ($^O eq 'linux') {
    # First modify $0 in a subthread.
    #print "# mainthread: \$0 = $0\n";
    omnithreads->create(sub{ #print "# subthread: \$0 = $0\n";
                        $0 = "foobar";
                        #print "# subthread: \$0 = $0\n"
                 })->join;
    #print "# mainthread: \$0 = $0\n";
    #print "# pid = $$\n";
    if (open PS, "ps -f |") { # Note: must work in (all) systems.
        my ($sawpid, $sawexe);
        while (<PS>) {
            chomp;
            #print "# [$_]\n";
            if (/^\s*\S+\s+$$\s/) {
                $sawpid++;
                if (/\sfoobar\s*$/) { # Linux 2.2 leaves extra trailing spaces.
                    $sawexe++;
                }
                last;
            }
        }
        close PS or die;
        if ($sawpid) {
            ok($sawpid && $sawexe, 'altering $0 is effective');
        } else {
            skip("\$0 check: did not see pid $$ in 'ps -f |'");
        }
    } else {
        skip("\$0 check: opening 'ps -f |' failed: $!");
    }
} else {
    skip("\$0 check: only on Linux");
}

{
    my $t = omnithreads->create(sub {});
    $t->join();
    omnithreads->create(sub {})->join();
    eval { $t->join(); };
    ok(($@ =~ /Thread already joined/), "Double join works");
    eval { $t->detach(); };
    ok(($@ =~ /Cannot detach a joined thread/), "Detach joined thread");
}

{
    my $t = omnithreads->create(sub {});
    $t->detach();
    omnithreads->create(sub {})->join();
    eval { $t->detach(); };
    ok(($@ =~ /Thread already detached/), "Double detach works");
    eval { $t->join(); };
    ok(($@ =~ /Cannot join a detached thread/), "Join detached thread");
}

{
    # The "use IO::File" is not actually used for anything; its only purpose
    # is incite a lot of calls to newCONSTSUB.  See the p5p archives for
    # the thread "maint@20974 or before broke mp2 ithreads test".
    use IO::File;
    # This coredumped between #20930 and #21000
    $_->join for map omnithreads->create(sub{ok($_, "stress newCONSTSUB")}), 1..2;
}

# EOF
