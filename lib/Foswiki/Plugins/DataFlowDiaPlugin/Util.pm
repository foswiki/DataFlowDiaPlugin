# $Id: //foswiki-dfd/rel2_0_1/lib/Foswiki/Plugins/DataFlowDiaPlugin/Util.pm#2 $

# Copyright 2015 Applied Research Laboratories, the University of
# Texas at Austin.
#
#    This file is part of DataFlowDiaPlugin.
#
#    DataFlowDiaPlugin is free software: you can redistribute it and/or
#    modify it under the terms of the GNU General Public License as
#    published by the Free Software Foundation, either version 3 of
#    the License, or (at your option) any later version.
#
#    DataFlowDiaPlugin is distributed in the hope that it will be
#    useful, but WITHOUT ANY WARRANTY; without even the implied
#    warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#    See the GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with DataFlowDiaPlugin.  If not, see <http://www.gnu.org/licenses/>.
#
# Author: John Knutson
#
# Provide a mechanism for documenting the interconnections between processes.

=begin TML

---+ package Foswiki::Plugins::DataFlowDiaPlugin::Util

Defines basic subroutines for System.DataFlowDiaPlugin.

=cut

package Foswiki::Plugins::DataFlowDiaPlugin::Util;

# Always use strict to enforce variable scoping
use strict;
use warnings;
use vars qw(@EXPORT_OK);

require Exporter;
*import = \&Exporter::import;
@EXPORT_OK = qw(macroError isError isValidID genDotStart genDotEnd
_debugWrite _debugDump _dumpSave _debugFuncStart _debugFuncEnd _debugFile
_debugStack unique intersection difference FAIL);
our %EXPORT_TAGS = (
    'debug' => [ qw( _debugWrite _debugDump _dumpSave _debugFuncStart _debugFuncEnd _debugFile _debugStack ) ],
    'error' => [ qw( macroError isError FAIL isValidID ) ],
    'graphviz' => [ qw( genDotStart genDotEnd ) ],
    'set' => [ qw( unique intersection difference ) ],
    );

#BEGIN { $Exporter::Verbose=1 }

my $errFmtStart = "<nop>DataFlowDiaPlugin Error: ";
my $errFmtEnd = "";
my $indent = 0;        # indentation value for debug output

# @return a formatted error message for macros
# @param[in] $message the contents of the error message
sub macroError {
    my ($message) = @_;

    my ($dbgPackage, $dbgFilename, $dbgLine) = caller;
    _debugWrite("macroError($message) caller: $dbgPackage $dbgFilename $dbgLine");

    return $Foswiki::Plugins::SESSION->inlineAlert(
        'alerts', 'generic',
        $errFmtStart . $message . $errFmtEnd);
}

# Determine if a text string contains a macro error message.
# @param[in] $text A text string that may contain a message generated
#   by macroError
# @return 0 if $text does not contain an error message as produced by
#   macroError.
sub isError {
    return $_[0] =~ /$errFmtStart/;
}

# Determine if a string is valid for use as an identifier.
# @param[in] $text A process, data type or transport identifier to validate.
# @return 0 if $text is not a valid identifier for use by graphviz.
sub isValidID {
    return $_[0] =~ /^[a-zA-Z][a-zA-Z0-9_]*$/;
}


# caller provides an array/list by value
sub unique {
    my @rv = do { my %seen; grep { !$seen{$_}++ } @_ };
    return @rv;
}


# caller provides two array references
sub intersection {
    my %lefthash = map{$_ => 1} @{ $_[0] };
    my @rv = grep( $lefthash{$_}, @{ $_[1] } );
    #_debugWrite("intersection LEFT=(" . join(' ',@{$_[0]}) . ")    RIGHT=(" . join(' ',@{$_[1]}) . ")");
    return @rv;
}


# caller provides two array references
# Returns a list of items in the second arg that are not in the first.
sub difference {
    my %lefthash = map{$_ => 1} @{ $_[0] };
    my @rv = grep( !defined $lefthash{$_}, @{ $_[1] } );
    #_debugWrite("difference LEFT=(" . join(' ',@{$_[0]}) . ")    RIGHT=(" . join(' ',@{$_[1]}) . ")");
    return @rv;
}


# Like die, but includes a stack trace for debugging.
# Use this sub for internal errors (e.g. assertion failures).
# Use "die" for user errors.
sub FAIL {
    my $deathRattle = join(' ',@_);
    my $i = 0;
    my ($pkg, $filename, $line, $subroutine, $hasArgs, $wantArray,
        $evalText, $isRequire, $hints, $bitMask);
    my @stack;
    my $frame = "";
    my $lastpkg = "";
    while (($pkg, $filename, $line, $subroutine, $hasArgs, $wantArray,
            $evalText, $isRequire, $hints, $bitMask) = caller($i++)) {
        $frame = "\[$i\] ";
        if (defined $filename) {
            $frame .= "$filename";
            $frame .= ":$line " if (defined $line);
        }
        # Get the sub from the NEXT frame, because perl's caller
        # function gives you the name of the function being called,
        # rather than the name of the calling function.
        if (($pkg, $filename, $line, $subroutine) = caller($i)) {
            $frame .= $subroutine if (defined $subroutine);
        }
        push(@stack, $frame);
    }
    die($deathRattle . "<br/>\n" . join("<br/>\n", @stack) . "<p/>\n");
}


# @return the beginning portion of a DirectedGraphPlugin graph
sub genDotStart {
    my ($file, $label) = @_;
    my $rv =
        "<dot file=\"$file\" "
        . $Foswiki::Plugins::DataFlowDiaPlugin::dotTagDefault
        . ">\n"
	. "digraph G {\n"
	. "   graph [ tooltip=\"Mouse Over for Tips&#10;Click for links\", ";
    $rv .= "label=\"$label\", "
        if ($label);
    $rv .= $Foswiki::Plugins::DataFlowDiaPlugin::graphDefault
        . " ]\n"
	. "   edge [ " . $Foswiki::Plugins::DataFlowDiaPlugin::edgeDefault
        . " ]\n"
	. "   node [ " . $Foswiki::Plugins::DataFlowDiaPlugin::nodeDefault
        . " ]\n";
    return $rv;
}


# @return the ending portion of a DirectedGraphPlugin graph
sub genDotEnd {
    return "}\n</dot>\n";
}


# write a message to the Foswiki debug log, ONLY IF DEBUG OUTPUT IS ENABLED
sub _debugWrite {
    use Foswiki::Func qw(writeDebug);
    return unless $_[0];
    my $tag = 'DataFlowDiaPlugin: ';
    $tag =~ s/^(.*)/' ' x $indent . $1/e;
    print $tag . $_[0] . "\n"
        if $Foswiki::Plugins::DataFlowDiaPlugin::debugUnitTests;
    Foswiki::Func::writeDebug( $tag . $_[0] )
	if $Foswiki::Plugins::DataFlowDiaPlugin::debugDefault;
}


# Use Data::Dumper to dump a Perl data structure to the Foswiki debug log
sub _debugDump {
    eval { require Data::Dumper; };
    return _debugWrite("warning: Data::Dumper package not available: $@")
	if ($@);
    #$Data::Dumper::Maxrecurse = 1;
    #$Data::Dumper::Maxdepth = 1;
    #local $Data::Dumper::Indent = 1;
    return _debugWrite(Data::Dumper->Dump($_[0]));
}


# Write debug output for the start of a function, for indicating
# function call/stack levels.
sub _debugFuncStart {
    _debugWrite("+ " . $_[0]);
    $indent += 3;
}


# Write debug output for the end of a function, for indicating
# function call/stack levels.
sub _debugFuncEnd {
    $indent -= 3;
    _debugWrite("- " . $_[0]);
}


# Use Data::Dumper to dump a Perl data structure to the specified file
# @param[in] the data structure to save
# @param[in] the name of the file to store the output in
sub _dumpSave {
    my $fn = shift;
    eval { require Data::Dumper; };
    return _debugWrite("warning: Data::Dumper package not available: $@")
	if ($@);
    #$Data::Dumper::Maxrecurse = 1;
    #$Data::Dumper::Maxdepth = 1;
    Foswiki::Func::saveFile($fn, Data::Dumper->Dump($_[0]));
}


# Save a text string to a file in this plug-in's work area.
# @param[in] $web the wiki web related to the contents
# @param[in] $topic the wiki topic related to the contents
# @param[in] $funcName the function name related to the contents
# @param[in] $text the data to store in the file.
sub _debugFile {
    my ($web, $topic, $funcName, $text) = @_;
    my $workArea = Foswiki::Func::getWorkArea("DataFlowDiaPlugin");
    Foswiki::Func::saveFile("$workArea/$funcName.$web.$topic.txt", $text)
	if $Foswiki::Plugins::DataFlowDiaPlugin::debugDefault;
}


# write a stack trace to the Foswiki debug log
sub _debugStack {
    eval { require Devel::StackTrace; };
    return _debugWrite("warning: Devel::StackTrace package not available")
	if ($@);
    return _debugWrite(Devel::StackTrace->new()->as_string());
}

1;
