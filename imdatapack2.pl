eval 'exec ${PERLHOME}/bin/perl -S $0 ${1+"$@"}' # -*- perl -si*-
    if 0;

use Getopt::Std;

@supportedProcesses = ("owmmsxcode","owmmstracing","owmmsrelay","owmmsalarm","convserv","ccrserv","imdirserv","imdircacheserv","immgrserv","imqueueserv","imconfserv","imconfcacheserv","popserv","imapserv","mta","mss","imextserv","notifyserv","eventrtr","papnmc","sipamdocnmc","sipschnmc","sipnmc","sipocnmc","sippublishnmc","sipmwiocnmc","smppnmc","smtpnmc","snppnmc","vsrserv","vsrsipproxy","ttsserv");

my $PROG = 'imdatapack2.pl';
my $VERSION = '2.1.1';
my $IM = $ENV{'INTERMAIL'} || die "$PROG: \$INTERMAIL is not set.\n";
my $envHome = $ENV{'HOME'} || die "$PROG: \$HOME is not set.\n";

$| = 1;

my $debug=0;
my $logsToCollect=1;
my $rundir = `pwd`;chomp($rundir);
my $tarfile;
my $now = time || die "$PROG: Failed to get current time.\n";
my $timeString = `date +%Y%m%d%H%M`;
my $tar = '/bin/tar';
my $uname ='uname';
my $ps = '/bin/ps';
my $prtconf = '/usr/sbin/prtconf';
my $sar = '/usr/sbin/sar';
my $gdb = `which gdb 2>/dev/null`;
my $strace = `which gdb 2>/dev/null`;
my $server = $ARGV[0];
my $logMatched = 0;
my $pi = 5;
my $pn = 5;
my $nprocs = 0;
my $maxfilesize = 100 * 1024 * 1024 * 1024;
my $gotcores = 0;
my $host = cmd("cat $IM/config/hostname", 1);
$tarball = "imdatapack2.$host.$server.$timeString";
chomp($tarball);
my $tarballTmpDir = $rundir . "/imdatapack2.tmp/" . $tarball;
`rm -rf $rundir/imdatapack2.tmp/`;
`mkdir -p $tarballTmpDir 2>/dev/null`;

$tarballFilename = $tarball . ".tar";
my $tarballAbsolutePath = "$rundir" . "/" . "$tarballFilename";

my $fullUname = `uname -a`;


#STAGE ZERO - PRE-FLIGHT CHECKS
my $arch = `$uname`;
chomp $arch;
die "$PROG does not support $arch" unless ($arch eq 'Linux' || $arch eq 'SunOS');

$inputString = "@ARGV[0] @ARGV[1] @ARGV[2] @ARGV[3] @ARGV[4] @ARGV[5] @ARGV[6] @ARGV[7] @ARGV[8] @ARGV[9] @ARGV[10] @ARGV[11] @ARGV[12] @ARGV[13] ";

if(scalar @ARGV==0){die "A server argument must be specified, for help, use --help\n";}

if($inputString =~ /--help/)
        {
        usage();
        }

if(@ARGV[0] =~ /([\S]+)/)
        {
        $server=$1;
        foreach(@supportedProcesses)
                {
                if($server eq $_){$supported=1;last if (1==1);}
                }
        if ($supported!=1){die "Process $server is not supported, for help, use --help\n";}
        }

if($inputString =~ /--logsback ([0-9]+)/)
        {
        $logsToCollect=$1;
        }

if($inputString =~ /--alternatelogdir ([\S]+) /)
        {
        $alternateLogDir=$1;if($debug==1){print "debug=1 alternateLogDir is $alternateLogDir\n";}
        }

if($inputString =~ /--debug/)
        {
        $debug=1;
        }

if($arch eq 'Linux')
        {
        if($gdb eq ""){print "*****Linux utility gdb is not present. This utility can save considerable time in troubleshooting issues.  Please ensure that this is installed.\n";$gdbInstalled=0;}
        elsif($gdb ne ""){$gdbInstalled=1;}
        if($strace eq ""){print "*****Linux utility strace is not present. This utility can save considerable time in troubleshooting issues.  Please ensure that this is installed.\n";}
        }


if($debug==1){print "inputString is $inputString\n";}
print "$PROG $VERSION started by $ENV{USER} on $host which runs $arch at " . `date` . "\n";

#STAGE ONE - CREATE DATE FILE AND CREATE TARBALL
print "Creating date file and tarball...\n";
cd("$rundir/imdatapack2.tmp/");

`date > $tarballTmpDir/datestamp`;
`cp $envHome/.profile $tarballTmpDir/profile`;
`cp $envHome/.cshrc $tarballTmpDir/cshrc`;

cmd("$tar -cf $tarballAbsolutePath $tarball/datestamp");
cmd("$tar -uhf $tarballAbsolutePath $tarball/cshrc");
cmd("$tar -uhf $tarballAbsolutePath $tarball/profile");

`rm $tarballTmpDir/date`;
`rm $tarballTmpDir/cshrc`;
`rm $tarballTmpDir/profile`;


#STAGE TWO - GET SYSTEM INFO
print "Copying system info...\n";
mkdir("$tarballTmpDir/system", 0770);
if ($arch eq 'SunOS') 
        {
        `uname -a > $tarballTmpDir/system/uname_a`;
        `uname -X > $tarballTmpDir/system/uname_X`;
        `prtconf > $tarballTmpDir/system/prtconf`;
        `prtdiag > $tarballTmpDir/system/prtdiag`;
        `cp /var/adm/messages $tarballTmpDir/system/messages`;
        `cp /etc/system $tarballTmpDir/system/system`;
        }
else 
        {
        `uname -a > $tarballTmpDir/system/uname_a`;
        #`cp /var/log/messages $tmpdir/imdatapack2.tmp/system/messages`; #looks like us poor regular linux users can't read this file :(
        `cp /proc/cpuinfo $tarballTmpDir/system/cpuinfo`;
        }
print "   Adding system info to tarball...\n";
cd("$rundir/imdatapack2.tmp/");
cmd("$tar -uhf $tarballAbsolutePath $tarball/system");
`rm -rf $tarballTmpDir/system`;


#STAGE THREE - GET CONFIG.DB
print "Copying config.db...\n";
if($debug==1){print "tarballTmpDir is $tarballTmpDir\n";}
`cp $IM/config/config.db $tarballTmpDir` if (smallenough($file));
print "   Adding config.db to tarball...\n";
cd("$rundir/imdatapack2.tmp/");
cmd("$tar -uhf $tarballAbsolutePath $tarball/config.db");
`rm -f $tarballTmpDir/config.db`;


#STAGE FOUR - GET CORES WITH LOGS AND LIBRARIES
@coreFiles = findCores();
if(@coreFiles) 
        {
        @coreFilesCopied = getCores();
        getLibs(@coreFilesCopied);
        foreach my $file (@coreFilesSelected)
                {
                $coreModifyTime = getMtime($file);
                if($debug==1){print "core file is $file and core mtime is $coreModifyTime\n";}
                push(@coreModifyTimestamps,$coreModifyTime);
                getCoreLogs($coreModifyTime,$logsToCollect);
                }
        }
else
        {
        print "No core files were found...not collecting libraries or cores.  Current log files will be collected.  The --logsback argument can still be used.";
        getCoreLogs(time(),$logsToCollect);
        }

cd("$rundir");
print "Removing temporary directory...\n";
`rm -rf imdatapack2.tmp/`;
`chmod 777 $tarballAbsolutePath`; 
print "Completed\n";


#-------------------FUNCTIONS-----------------
sub getMtime
        {
        my $file = @_[0];
        my @stats = stat($file);
        $mtime= $stats[9];
        return $mtime;
        }


sub getCoreLogs () #PASS IN A UNIX EPOCH TIMESTAMP AND CORRESPONDING LOG WILL BE COLLECTED
        {
        $coreModifyTime = @_[0];   #CREATE VARIABLE BASED ON EPOCH TIME WHICH WAS PASSED IN
        $logsBack = @_[1];   #CREATE VARIABLE BASED ON NUMBER OF LOGS BACK TO COLLECT
        $logsFound=0;
        print "\nTrying to find logs for core file...\n";
        cd("$IM");
        if(defined $alternateLogDir)  #change the ls command for if there is a second absolute path defined
                {
                if($debug==1){print "debug alternate log directory was defined\n";}
                cd("$IM");
                @logFiles = split(/\n/, cmd("ls -1t log/$server.$host*\.log* $alternateLogDir/$server.$host*\.log*")); #create array logFiles of all server log filenames
                }
        elsif(not defined $alternateLogDir)
                {
                if($debug==1){print "debug alternate log directory was NOT defined\n";}
                cd("$IM");
                @logFiles = split(/\n/, cmd("ls -1t log/$server.$host*\.log*")); #create array logFiles of all server log filenames
                }
        foreach my $file (@logFiles)                    #create array of mtimes found
                {
                cd("$IM");
                my @logStats = stat($file);
                $logMtime = $logStats[9];
                if($debug==1){print "debug=1 file is $file and logMtime is $logMtime\n";}
                push(@logMtimes,$logMtime);
                }
        sort @logMtimes;                #this may already be sorted, by using ls -tr
        if($debug==1){foreach(@logMtimes){print "debug=1 sorted mtime $_\n"};}   
        my $next = undef;
        $counter = 0;

        while($coreMtime < @logMtimes[$counter])
                {
                if($debug==1){print "debug=1 counter is $counter, coreMtime is $coreMtime and logMtimescounter is @logMtimes[$counter]\n";}
                $counter++;
                }
        if($debug==1){print "debug=9 logMtimes contains $#logMtimes items and counter is $counter\n";}


        if($counter!=$#logMtimes)
                {
                if($debug==1){print "debug=7 entered case 1\n";}
                $logsFound=1;
                $closestLogMtime=@logMtimes[$counter-1];  #fiddle with this
                }
        elsif($counter==1) #THIS COVERS SITUATION OF ONLY HAVING 1 LOG
                {
                if($debug==1){print "debug=7 entered case 2\n";}
                $logsFound=1;
                $closestLogMtime=@logMtimes[$counter-1];  #fiddle with this to get the right logs
                }
        elsif($counter>=$#logMtimes)
                {
                if($debug==1){print "debug=7 entered case 3\n";}
                if($debug==1){print "debug=9 ran out of logs\n";}
                $logsFound = 0;
                } #check to see if we ran out of logs while looking back through mtime
        if($debug==1){print "debug=10 closestLogMtime is $closestLogMtime and logsFound is $logsFound\n";}
        cd("$IM");

#BY NOW, WE WILL EITHER HAVE LOGSFOUND CORRESPONDING TO THE MTIME OF THE CORE FILE OR NOT

        if($logsFound==1)
                {
                mkdir("$tarballTmpDir/log", 0770);   #MAKE DIRECTORY IN TEMPORARY LOCATION
                for($turn=0;$turn<$logsBack;$turn++)
                        {
                        for($counter=0;$counter<=$#logFiles;$counter++)
                                {
                                my @logStats = stat(@logFiles[$counter-$turn]);
                                $logMtime = $logStats[9];
                                if($debug==1){print "debug=1 comparing $closestLogMtime and $logMtime\n";}
                                if($closestLogMtime==$logMtime)
                                        {
                                if($debug==1){print "debug=1 matched file is @logFiles[$counter] and counter is $counter\n";}
                                $coreLogIndexNumber = $counter;
                                $logsFound = 1;
                                if(@logFiles[$counter]=~/([\S\s]+[0-9]+).[a-z]+/)
                                        {
                                        cd("$IM");
                                        $logString = $1;
                                        if($debug==1){print "logString is $logString\n";}
                                        system("cp $logString\.* $tarballTmpDir/log/");
                                        }
                                break;
                                }
                        }


                        }
                cd("$rundir/imdatapack2.tmp/");
                @logListing = split(/\n/, cmd("ls -1t $tarball/log/$server.$host*\.*"));
                #need to handle where there are no log files collected
                foreach(@logListing)
                        {
                        $logFile = $_;
                        print "Compressing $logFile\n";
                        `gzip --fast -f $logFile`;
                        print "   Adding $logFile.gz to tarball...\n";
                        cmd("$tar -uhf $tarballAbsolutePath $logFile*");
                        `rm -f $logFile.gz`;
                        }
                }
       elsif($logsFound==0)
                {
                print "...Logs were not found for core file :(\n";
                return;
                }
        }


sub getLibs #pass in an array of absolute core file paths and it will return a list of all binaries/libraries which may be needed
        {
        print "\nCollecting libraries for analyzing cores...\n";
        mkdir("$tarballTmpDir/applibs", 0770);
        my @corePaths = @_;
        if($arch eq 'SunOS')
                {
                @binLibs = split(/\n/, cmd("pldd @corePaths[0]"));
                if(@binLibs[0] =~ /:[\s\t]+(\/[\S]+)/){@binLibs[0] = $1;$binaryAbsoluteFilePath = $1;}
                if($binaryAbsoluteFilePath=~/^[\S\/]+\/([\w]+).{0,1}[\S]*$/){$symlinkName = $1;}
                if($binaryAbsoluteFilePath=~/^[\S\/]+\/([\w]+.{0,1}[\S]*)$/){$binaryFilename = $1;}
                if($debug==1){print "SunOS detected\n";}
                }
        elsif($arch eq 'Linux')
                {
                if($debug==1){print "debug=12 linux detected\n";}
                cd("$IM");
                $binaryRelativePath = `find bin/ lib/ -type f -name $server`;
                chomp($binaryRelativePath);
                if($debug==1){print "debug=88 binaryRelativePath is $binaryRelativePath\n";}
                if($gdbInstalled==1)
                        {
                        print "   gdb was installed, so collecting all libraries loaded in the core\n";
                        if($debug==1){print "debug=1243 binaryRelativePath is $binaryRelativePath and corePaths0 is @corePaths[0]\n";}
                        push(@binLibs,"$IM/$binaryRelativePath");
                        $gdbOutput=`gdb $binaryRelativePath @corePaths[0] 2>/dev/null <<< 'info shared'`;
                        if($debug==1){print "debug=1243 gdbOutput is $gdbOutput\n";}
                        if($gdbOutput=~/(0x[\s\S]+     \/[\S\s\n]+)/m){@gdbOutputArray = split(/\n/, $1);if($debug==1){print "one is $1\n";}}
                        foreach(@gdbOutputArray)
                                {
                                if(/0x[\s\S]+     (\/[\s\S]+)/){push(@binLibs,$1)};
                                }
                        }
                elsif($gdbInstalled!=1)
                        {
                        print "gdb is not installed, so collecteding libraries based on ldd output\n";
                        if(-r "lib/$server" || -r bin/$server) #this may need a fiddle
                                {
                                if($debug==1){print "debug=1 found binary for $server and it is $_\n";}
                                @binLibs = split(/\n/, `ldd lib/$server`);
                                foreach(@binLibs)
                                        {
                                        if(/(\/[\s\S]+) \(0x/){push(@binLibs2,$1);}
                                        }
                                push(@binLibs2,"$IM/lib/$server");
                                }
                        @binLibs = @binLibs2;
                        }
                }
        foreach my $file (@binLibs)
                {
                if($debug==1){print "debug=11 cp $file $tarballTmpDir/applibs/";}
                `cp -f $file $tarballTmpDir/applibs/`;
                }
        print "Compressing libraries...\n";
        `gzip --fast -f $tarballTmpDir/applibs/*`;
        cd("$rundir/imdatapack2.tmp/");
        print "   Adding libraries to tarball...\n";
        cmd("$tar -uhf $tarballAbsolutePath $tarball/applibs");
        cd("$rundir/imdatapack2.tmp/$tarball/");
        `ln -s applibs/$binaryFilename $symlinkName`;
        cd("$rundir/imdatapack2.tmp/");
        cmd("$tar -uf $tarballAbsolutePath $tarball/$symlinkName");  #no h argument to tar so that it doesn't follow the symlink that doesnt work
        `rm $tarball/$symlinkName`;
        `rm -rf $tarballTmpDir/applibs`;
        return @binLibs;
        }


sub abort
        {
        die "\n$PROG: $_[0]\n";
        }


sub usage
        {
        print STDERR "Usage: $PROG server_name [--logsback <num>] [--alternatelogdir <path>] [--debug]\n";
        print STDERR "       --help Displays usage.\n";
        `rm -rf imdatapack2.tmp/`;
        exit 1;
        }


sub error
        {
        print STDERR "\n$PROG: $_[0]\n";
        }


sub event
        {
        my $fatal = shift;
        my $msg = shift;
        $fatal ? abort($msg) : error($msg);
        }


sub cmd 
        {
        my $cmd = shift;
        my $fatal = shift;
        my $quiet = shift;
        open(CMD, "$cmd 2>&1|") || 
        event($fatal, "$cmd: Failed to open pipe.");
        my $out;
        $out .= $_ while (<CMD>);
        close(CMD);
        chomp $out;
        my $err = $? >> 8;
        if ($err) 
                {
                abort("$cmd: status $err\n - $out") if ($fatal);
                error("$cmd: status $err\n - $out") unless ($quiet);
                undef $out;
                }
        return $out;
        }


sub recent 
        {
        my $file = shift;
        my @stats = stat($file);
        my $mtime = $stats[9];
        #print "now is $now and mtime is $mtime\n";
        return 1 if (($now - $mtime) <= $THREE_HOURS); 
        return 0;
        }


sub smallenough
        {
        my $file = shift;
        my @stats = stat($file);
        return 1 if ($stats[7] <= $maxfilesize);
        return 0;
        }


sub cd
        {
        chdir $_[0] || abort("chdir $_[0] failed");
        }


sub findCores
        {
        print "Looking for core files in default location...\n";
        $coreFiles1Location = "$IM/tmp/$server/";
        $coreFiles1 = `find $coreFiles1Location -type f -name "core*" 2>/dev/null`;

        if($coreFiles1 eq NULL)
                {
                print "No core files were found in the default location of $coreFiles1Location\n";
                }
        else
                {
                @coreFiles1 = split("\n",$coreFiles1);
                foreach(@coreFiles1)
                        {
                        #print "$_\n";
                        `file $_`;
                        if(`file $_` =~ /core file/){print "   found core file $_\n";push(@coreFiles,$_);}
                        }
                }

        print "\nWould you like to look in another location for cores? [y/n] ";
        chomp($answer = <STDIN>);
        if($answer eq "y" || $answer eq "Y")
                {
                print "Enter the alternate location for cores: ";
                chomp($coreFiles2Location = <STDIN>);
                print "Looking for core files in alternate location...\n";
                $coreFiles2 = `find $coreFiles2Location -type f -name "core*" 2>/dev/null`;
                @coreFiles2 = split("\n",$coreFiles2);

                if($coreFiles2 eq NULL)
                        {
                        print "No core files were found in the alternate location of $coreFiles2Location\n";
                        }
                else
                        {
                        @coreFiles2 = split("\n",$coreFiles2);
                        foreach(@coreFiles2)
                                {
                                if(`file $_` =~ /core file/){print "   found core file $_\n";push(@coreFiles,$_);}
                                }
                        }
                }
        return @coreFiles;
        }


sub getCores
        {
        `mkdir $tarballTmpDir/cores`;
        `ls -l $tarballTmpDir`;
        foreach(@coreFiles)
                {
                $test = `ls -lh $_ | awk '{print \$5,\$6,\$7,\$8}'`;
                chomp($test);
                print "Do you wish to collect $_ $test? [y/n] ";
                chomp($answer = <STDIN>);
                if($answer eq "y" || $answer eq "Y")
                        {
                        push(@coreFilesSelected,$_);
                        my @stats = stat($_);
                        $coreMtime = $stats[9];
                        if($debug==1){print "debug=46 coreMtime is $coreMtime\n";}
                        push(@coreMtimes,$coreMtime);
                        #last;  #USE THIS TO TOGGLE WHETHER YOU CAN COLLECT MORE THAN ONE CORE - ISSUES WITH PERFORMANCE ON REPEATED ADDING TO TARBALL - NEED TO HAVE A THINK
                        }
                }
        foreach my $file (@coreFilesSelected)
                {
                print "\nCollecting core $file for packaging...\n";
                `cp $file $tarballTmpDir/cores/`;
                if ($arch eq 'SunOS')
                        {
                        if($debug==1){print "Solaris detected, so using the solaris method of collecting cores\n";}
                        $pflagsFilename = "pflags" . $file;
                        if($file =~ /(\/[\S]+\/)([\S]+)/)
                                {
                                print "Creating pflags file...\n";
                                `pflags $file > $tarballTmpDir/cores/$2.pflags`;
                                print "Creating pstack file...\n";
                                `pstack $file > "$tarballTmpDir/cores/$2.pstack"`; #create pstack file
                                open(FH, "< $tarballTmpDir/cores/$2.pflags");
                                $tmpCoreFilename = $2;
                                @lines = <FH>;
                                close(FH);
                                for(0..@lines)
                                        {
                                        if($lines[$_] =~ /([\s\S]+cursig = SIG[A-Z]+)/)
                                                {
                                                $index = $_;
                                                }
                                        }
                                if(@lines[$index-1] =~ /\/([0-9]+):/)
                                        {
                                        $coringTid = $1;#print "coringTid is $coringTid\n";
                                        }
                                print "Creating pflags.tid file...\n";
                                open(FH,">$tarballTmpDir/cores/$tmpCoreFilename.pflags.$coringTid");
                                print FH "@lines[$index-1]";
                                print FH "@lines[$index]";
                                close(FH);
                                print "Creating pstack.tid file...\n";
                                $status = cmd("pstack $tarballTmpDir/cores/$tmpCoreFilename/$coringTid");# > "$tmpdir/imdatapack2.tmp/cores/$2.pstack.$coringTid"`;
                                open(FH,">$tarballTmpDir/cores/$tmpCoreFilename.pstack.$coringTid");
                                print FH "$status\n";
                                close(FH);
                                }
                        }
                elsif($arch eq 'Linux')
                        {
                        if($debug==1){print "Linux detected, so not analyzing cores on the core host.\n";}
                        }
                print "\nCompressing core files...\n";
                cd("$rundir/imdatapack2.tmp/");
                my @coreListing = split(/\n/, cmd("ls -1 $tarball/cores/*", 0, 1));
                if($debug==1){foreach(@coreListing){print "$_\n";}}
                foreach $file (@coreListing)
                        {
                        print "Compressing $file\n";
                        `gzip --fast -f $file 2>/dev/null`;
                        print "   Adding $file files to tarball...\n";
                        cd("$rundir/imdatapack2.tmp/");
                        cmd("$tar -uhf $tarballAbsolutePath $file\.gz");
                        if($debug==1){print "trying to delete $file\.gz\n";}
                        `rm -f $file.gz`;
                        }
                }
        cd("$tarballTmpDir");
        `rm -rf $tarball/cores/`;
        return @coreFilesSelected;
        return @coreMtimes;
        }
