# $Id: //foswiki-dfd/rel2_0_1/test/unit/DataFlowDiaPlugin/DataFlowDiaPluginRenderTests.pm#4 $

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

use strict;
use warnings;

package DataFlowDiaPluginRenderTests;

use FoswikiFnTestCase;
our @ISA = qw( FoswikiFnTestCase );

use strict;
use warnings;
use Foswiki;
use CGI;
use XML::LibXML;
use File::Temp qw(tempdir);
use File::Path;

use Foswiki::Plugins::DataFlowDiaPlugin;

# Peculiarities discovered while writing these tests
# 1) double-spaces between edges and data nodes in graphs but not between procs
# 2) one unexpected space after the transport anchor

# plug-in preferences key name
my $pip = "DATAFLOWDIAPLUGIN_";
# plug-in preferences values
my $dotTagOpts    = "inline=\"png\" map=\"1\" vectorformats=\"dot\"";
my $graphDefaults = "rankdir=\"LR\",labelloc=\"t\"";
my $edgeDefaults  = "fontsize=8";
my $nodeDefaults  = "style=filled,fontsize=9,fillcolor=white";
my $procDefaults  = "shape=\"ellipse\"";
my $depProc       = "shape=\"ellipse\",fillcolor=red";
my $dataDefaults  = "shape=\"note\"";
my $depData       = "shape=\"note\",fillcolor=red";
my $depMarkup     = "del";
my $bothExtra     = ", dir=\"both\", color=\"black:red\"";
my $STDTT         = "tooltip=\"Mouse Over for Tips&#10;Click for links\",";
# default ID when unspecified
my $defaultID     = "DEFAULT";
# other shortcuts
my $procFN = "DFD_PROC_";
my $procLB = "Process Data Flow";
my $dataFN = "DFD_DATA_";
my $dataLB = "Data Type Usage";
my $cnctFN = "DFD_CONNECT_";
 # indent/fill
my $defIndent = "   ";
my $F = $defIndent;

my $procTag = Foswiki::Plugins::DataFlowDiaPlugin::Process::getAnchorTag();
my $dataTag = Foswiki::Plugins::DataFlowDiaPlugin::DataType::getAnchorTag();
my $xportTag = Foswiki::Plugins::DataFlowDiaPlugin::Transport::getAnchorTag();
my $locTag = Foswiki::Plugins::DataFlowDiaPlugin::Locale::getAnchorTag();

sub new {
    my $self = shift()->SUPER::new(@_);
    return $self;
}

# Set up the test fixture
sub set_up {
    my $self = shift;
    $self->SUPER::set_up();
    # BUG shouldn't this be set up in FoswikiFnTestCase?
    $Foswiki::Plugins::SESSION = $self->{session};

    $self->{'tempdir'} = tempdir("dfdrenderXXXXXX", DIR => File::Spec->tmpdir);
    $self->{'success'}     = 0;
    $self->{'secondweb'}   = $self->{test_web} . "Second";
    $self->{'secondtopic'} = $self->{test_topic} . "Second";
    my $webObject = $self->populateNewWeb($self->{'secondweb'});
    $webObject->finish();

    # Use consistent preferences across all tests
    Foswiki::Func::setPreferencesValue($pip . "DEBUG", "0");
    Foswiki::Func::setPreferencesValue($pip . "DOTTAGOPTS", $dotTagOpts);
    Foswiki::Func::setPreferencesValue($pip . "GRAPHDEFAULTS", $graphDefaults);
    Foswiki::Func::setPreferencesValue($pip . "EDGEDEFAULTS", $edgeDefaults);
    Foswiki::Func::setPreferencesValue($pip . "NODEDEFAULTS", $nodeDefaults);
    Foswiki::Func::setPreferencesValue($pip . "PROCDEFAULTS", $procDefaults);
    Foswiki::Func::setPreferencesValue($pip . "DEPPROCDEFAULTS", $depProc);
    Foswiki::Func::setPreferencesValue($pip . "DATADEFAULTS", $dataDefaults);
    Foswiki::Func::setPreferencesValue($pip . "DEPDATADEFAULTS", $depData);
    Foswiki::Func::setPreferencesValue($pip . "DEPMARKUP", $depMarkup);

    Foswiki::Plugins::DataFlowDiaPlugin::initPlugin(
        $self->{test_web},  $self->{test_topic},
        $self->{test_user}, $Foswiki::cfg{SystemWebName}
        );

    #$Foswiki::Plugins::DataFlowDiaPlugin::debugUnitTests = 1;
}


sub tear_down {
    my $self = shift;
    $self->removeWeb($self->{'secondweb'});
    $self->SUPER::tear_down();
    # actually tear-down is apparently called each freaking test.
    # this may be unnecessary, it looks like tear_down isn't called on failure
    if ($self->{'success'}) {
        #printf "cleaning up " . $self->{'tempdir'} . "\n";
        File::Path::remove_tree($self->{'tempdir'});
    } else {
        printf "Results in " . $self->{'tempdir'} . "\n";
    }
}


sub saveData {
    my ($self, $fn, $text) = @_;
    my $path = File::Spec->catfile($self->{'tempdir'}, $fn);
    open(my $out, ">", $path) or die("Unable to open $path for output: $!\n");
    print $out $text;
    close($out);
}


sub runAndCheck {
    my ($self,
        $testText,
        $expected,
        $web,
        $topic) = @_;
    $self->{'success'} = 0;
    Foswiki::Plugins::DataFlowDiaPlugin::commonTagsHandler(
        $testText, $topic || $self->{test_topic}, $web || $self->{test_web}, 0,
        undef);
    $self->saveData("expected.txt", $expected);
    $self->saveData("got.txt", $testText);
    $self->assert_str_equals($expected, $testText);
    $self->{'success'} = 1;
}


sub getGVNName {
    my ($self,
        $id,
        $subID,
        $localeID,
        $localeSubID,
        $instNum,
        $locale2ID,
        $locale2SubID,
        $web,
        $xport1Web,
        $xport1ID,
        $xport1SubID,
        $xport2Web,
        $xport2ID,
        $xport2SubID) = @_;
    my $extraLocText = "";
    my $xport1LocText = "";
    my $xport2LocText = "";
    my @ra;
    push @ra, ($web || $self->{test_web});
    push @ra, $id;
    push @ra, $subID;
    push @ra, ($web || $self->{test_web});
    push @ra, $localeID;
    push @ra, $localeSubID;
    push @ra, ($xport1Web || $self->{test_web}), $xport1ID, $xport1SubID
        if ($xport1ID);
    push @ra, ($web || $self->{test_web}), $locale2ID, $locale2SubID
        if ($locale2ID);
    push @ra, ($xport2Web || $self->{test_web}), $xport2ID, $xport2SubID
        if ($xport2ID);
    push @ra, $instNum;
    my $rv = join("_", @ra);
    return $rv;
}


sub getTooltip {
    my ($type,
        $id,
        $subid,
        $name,
        $group,
        $def) = @_;
    my $defText = ($def ? "" : "(undefined)&#10;");
    return "tooltip=\"type: $type&#10;id: $id&#10;subid: $subid&#10;name: $name&#10;group: $group&#10;$defText\"";
}


sub getDotDef {
    my ($type,
        $gvnName,
        $nodeAttrs,
        $url,
        $entityName,
        $entityID,
        $subID,
        $group,
        $def) = @_;
    my $urlText = (defined($url) ? ",URL=\"$url\"" : "");
    my $label = "";
    $label .= "$group\\n"
        if ($group ne $defaultID);
    $label .= $entityName;
    $label .= "\\n" . $subID
        if ($subID ne $defaultID);
    return "$F$gvnName [ $nodeAttrs$urlText,label=\"$label\","
        . getTooltip($type, $entityID, $subID, $entityName, $group, $def)
        . " ]\n";
}


sub getProcDotDef {
    my ($gvnName,
        $nodeAttrs,
        $url,
        $procName,
        $procID,
        $subID,
        $group) = @_;
    return getDotDef("Process", $gvnName, $nodeAttrs, $url, $procName, $procID,
                     $subID, $group, 1);
}


sub getDataDotDef {
    my ($gvnName,
        $nodeAttrs,
        $url,
        $dataName,
        $dataID,
        $subID,
        $group,
        $def) = @_;
    return getDotDef("DataType", $gvnName, $nodeAttrs, $url, $dataName, $dataID,
                     $subID, $group, $def);
}


sub getEdge {
    my ($from,
        $to,
        $type,
        $edgeName,
        $edgeID,
        $edgeSubID,
        $group,
        $def,
        $extraText,
        $reverse,
        $url) = @_;
    $extraText ||= "";
    my $reverseText = ($reverse ? ", dir=back" : "");
    my $tt = getTooltip($type, $edgeID, $edgeSubID, $edgeName, $group, $def);
    my $label = ($edgeName eq $defaultID) ? "" : $edgeName;
    $label .= "\\n" . $edgeSubID
        if ($edgeSubID ne $defaultID);
    my $urlText = (defined($url) ? ", URL=\"$url\"" : "");
    my $rv = $F . $from . " -> " . $to . " [ label=\"" . $label . "\""
        . $reverseText . $urlText . ", " . $tt . ", label" . $tt . $extraText
        . " ]\n";
    return $rv;
}


sub getEverything {
    my ($self,
        $tag,
        $id,
        $subID,
        $localeID,
        $localeSubID,
        $instNum,
        $locale2ID,
        $locale2SubID,
        $web,
        $topic,
        $xport1Web,
        $xport1ID,
        $xport1SubID,
        $xport2Web,
        $xport2ID,
        $xport2SubID) = @_;
    my $anchor = $tag . ucfirst($id);
    my $url = Foswiki::Func::getViewUrl(
        ($web || $self->{test_web}), ($topic || $self->{test_topic}))
        . "#" . $anchor;
    my $gvn = $self->getGVNName(
        $id, $subID || $defaultID, $localeID || $defaultID,
        $localeSubID || $defaultID, $instNum || 1,
        $locale2ID, $locale2SubID, $web, $xport1Web, $xport1ID, $xport1SubID,
        $xport2Web, $xport2ID, $xport2SubID);
    return ($anchor, $url, $gvn);
}


sub getGraphTop {
    my ($anchorName, $file, $label) = @_;
    my $rv = (defined($anchorName) ? getAnchor($anchorName) : "");
    $rv .= "<dot file=\"$file\" $dotTagOpts>\ndigraph G {\n" . $F
        . "graph [ $STDTT ";
    $rv .= "label=\"$label\", "
        if ($label);
    $rv .= $graphDefaults . " ]\n"
        . "   edge [ $edgeDefaults ]\n"
        . "   node [ $nodeDefaults ]\n";
    return $rv;
}


sub getGraphBottom {
    return "}\n</dot>\n";
}


sub getSubGraphTop {
    my ($self,
        $loc,
        $name,
        $web) = @_;
    my $rv = $F . "subgraph cluster_" . ($web || $self->{test_web}) .
        "_" . $loc . "_" . $defaultID . " {\n";
    $F .= $defIndent;
    $rv .= $F . "graph [ label=\"" . ($name ? $name : $loc) . "\" ]\n";
    return $rv;
}


sub getSubGraphBottom {
    my $loc = shift;
    # unindent
    $F =~ s/$defIndent$//;
    return $F . "}\n";
}


sub getAnchor {
    return "<a name=\"" . $_[0] . "\"></a> ";
}


# Test DFDPROC with no I/O or any other parameters
# Defined entities:
#   Process: dfdtp1
sub test_DFDPROC_1 {
    my $self = shift;
    my $procID = "dfdtp1";
    my $procName = $procID;
    my $subID = $defaultID;
    my $localeID = $defaultID;
    my $localeSubID = $defaultID;
    my $instNum = "1";
    my $testText = "%DFDPROC{id=\"$procID\"}%";
    my $anchorName = $procTag . ucfirst($procID);
    my $url = Foswiki::Func::getViewUrl($self->{test_web}, $self->{test_topic})
        . "#" . $anchorName;
    # graphviz node name
    my $gvnName = $self->getGVNName(
        $procID, $subID, $localeID, $localeSubID, $instNum);
    my $expected =
        getGraphTop($anchorName, "$procFN$procID", "$procID $procLB")
        . getProcDotDef($gvnName, $procDefaults, $url, $procName,
                        $procID, $subID, $defaultID)
        . getGraphBottom();
    $self->runAndCheck($testText, $expected);
}


# Test DFDPROC with no I/O or any other parameters
# Defined entities:
#   Process: dfdtp2
sub test_DFDPROC_2 {
    my $self = shift;
    my $procID = "dfdtp2";
    my $procName = "TEST PROC 2";
    my $subID = $defaultID;
    my $localeID = $defaultID;
    my $localeSubID = $defaultID;
    my $instNum = "1";
    my $url = "http://www.google.com";
    my $testText = "%DFDPROC{id=\"dfdtp2\" name=\"TEST PROC 2\" deprecated=\"on\" url=\"$url\"}%";
    my $anchorName = $procTag . ucfirst($procID);
    # graphviz node name
    my $gvnName = $self->getGVNName(
        $procID, $subID, $localeID, $localeSubID, $instNum);
    my $expected =
        getGraphTop($anchorName, "$procFN$procID", "$procID $procLB")
        . getProcDotDef($gvnName, $depProc, $url, $procName,
                        $procID, $subID, $defaultID)
        . getGraphBottom();
    $self->runAndCheck($testText, $expected);
}


# Test DFDPROC with undefined I/O and transports
# Defined entities:
#   Process: dfdtp3
# Undefined entities:
#   Transport: ix, ox, iox
#   Data:      dfdtd1, dfdtd2, dfdtd3, dfdtd4, dfdtd5
sub test_DFDPROC_3 {
    my $self = shift;
    my $procID = "dfdtp3";
    my $procName = $procID;
    my $subID = $defaultID;
    my $localeID = $defaultID;
    my $localeSubID = $defaultID;
    my $instNum = "1";
    my $inXportID = "ix";
    my $outXportID = "ox";
    my $inoutXportID = "iox";
    my $testText = "%DFDPROC{id=\"dfdtp3\" inxport=\"$inXportID\" inputs=\"dfdtd1, dfdtd2\" outxport=\"$outXportID\" outputs=\"dfdtd3, dfdtd1\" inoutxport=\"$inoutXportID\" inouts=\"dfdtd4, dfdtd5\"}%";
    my $anchorName = $procTag . ucfirst($procID);
    my $url = Foswiki::Func::getViewUrl($self->{test_web}, $self->{test_topic})
        . "#" . $anchorName;
    # graphviz node names
    my $procGVNName = $self->getGVNName(
        $procID, $subID, $localeID, $localeSubID, $instNum);
    my $d1_1GVNName = $self->getGVNName(
        "dfdtd1", $defaultID, $defaultID, $defaultID, 1, $defaultID,
        $defaultID, undef, undef, $inXportID, $defaultID,
        undef, $inXportID, $defaultID);
    my $d1_2GVNName = $self->getGVNName(
        "dfdtd1", $defaultID, $defaultID, $defaultID, 2, $defaultID,
        $defaultID, undef, undef, $outXportID, $defaultID,
        undef, $outXportID, $defaultID);
    my $d2GVNName = $self->getGVNName(
        "dfdtd2", $defaultID, $defaultID, $defaultID, 1, $defaultID,
        $defaultID, undef, undef, $inXportID, $defaultID,
        undef, $inXportID, $defaultID);
    my $d3GVNName = $self->getGVNName(
        "dfdtd3", $defaultID, $defaultID, $defaultID, 1, $defaultID,
        $defaultID, undef, undef, $outXportID, $defaultID,
        undef, $outXportID, $defaultID);
    my $d4GVNName = $self->getGVNName(
        "dfdtd4", $defaultID, $defaultID, $defaultID, 1, $defaultID,
        $defaultID, undef, undef, $inoutXportID, $defaultID,
        undef, $inoutXportID, $defaultID);
    my $d5GVNName = $self->getGVNName(
        "dfdtd5", $defaultID, $defaultID, $defaultID, 1, $defaultID,
        $defaultID, undef, undef, $inoutXportID, $defaultID,
        undef, $inoutXportID, $defaultID);
    my $expected =
        getGraphTop($anchorName, "$procFN$procID", "$procID $procLB")
        . getProcDotDef($procGVNName, $procDefaults, $url, $procName,
                        $procID, $subID, $defaultID)
        . getDataDotDef($d1_1GVNName, $dataDefaults, undef, "dfdtd1",
                        "dfdtd1", $defaultID, $defaultID)
        . getDataDotDef($d1_2GVNName, $dataDefaults, undef, "dfdtd1",
                        "dfdtd1", $defaultID, $defaultID)
        . getDataDotDef($d2GVNName, $dataDefaults, undef, "dfdtd2",
                        "dfdtd2", $defaultID, $defaultID)
        . getDataDotDef($d3GVNName, $dataDefaults, undef, "dfdtd3",
                        "dfdtd3", $defaultID, $defaultID)
        . getDataDotDef($d4GVNName, $dataDefaults, undef, "dfdtd4",
                        "dfdtd4", $defaultID, $defaultID)
        . getDataDotDef($d5GVNName, $dataDefaults, undef, "dfdtd5",
                        "dfdtd5", $defaultID, $defaultID)
        . getEdge($procGVNName, $d1_2GVNName, "Transport", $outXportID,
                  $outXportID, $defaultID, $defaultID, 0)
        . getEdge($procGVNName, $d3GVNName, "Transport", $outXportID,
                  $outXportID, $defaultID, $defaultID, 0)
        . getEdge($procGVNName, $d4GVNName, "Transport", $inoutXportID,
                  $inoutXportID, $defaultID, $defaultID, 0, $bothExtra)
        . getEdge($procGVNName, $d5GVNName, "Transport", $inoutXportID,
                  $inoutXportID, $defaultID, $defaultID, 0, $bothExtra)
        . getEdge($d1_1GVNName, $procGVNName, "Transport", $inXportID,
                  $inXportID, $defaultID, $defaultID, 0)
        . getEdge($d2GVNName, $procGVNName, "Transport", $inXportID,
                  $inXportID, $defaultID, $defaultID, 0)
        . getGraphBottom();
    $self->runAndCheck($testText, $expected);
}


# Test DFDPROC with undefined I/O and transports plus sub-id and overrides
# Defined entities:
#   Process: dfdtp4
# Undefined entities:
#   Transport: ix, ox, ox2, iox
#   Data:      dfdtd6, dfdtd7, dfdtd8, dfdtd9, dfdtd10
sub test_DFDPROC_4 {
    my $self = shift;
    my $procID = "dfdtp4";
    my $procName = $procID;
    my $subID = $defaultID;
    my $localeID = $defaultID;
    my $localeSubID = $defaultID;
    my $instNum = "1";
    my $inXportID = "ix";
    my $outXportID = "ox";
    my $outXportID2 = "ox2";
    my $inoutXportID = "iox";
    my $testText = "%DFDPROC{id=\"$procID\" inxport=\"$inXportID\" inputs=\"dfdtd6, dfdtd7\" outxport=\"$outXportID\" outputs=\"dfdtd8#sub1##$outXportID2, dfdtd6##r\" inoutxport=\"$inoutXportID\" inouts=\"dfdtd9, dfdtd10\"}%";
    my $anchorName = $procTag . ucfirst($procID);
    my $url = Foswiki::Func::getViewUrl($self->{test_web}, $self->{test_topic})
        . "#" . $anchorName;
    # graphviz node names
    my $procGVNName = $self->getGVNName(
        $procID, $subID, $localeID, $localeSubID, $instNum);
    my $d6_1GVNName = $self->getGVNName(
        "dfdtd6", $defaultID, $defaultID, $defaultID, 1, $defaultID,
        $defaultID, undef, undef, $inXportID, $defaultID,
        undef, $inXportID, $defaultID);
    my $d6_2GVNName = $self->getGVNName(
        "dfdtd6", $defaultID, $defaultID, $defaultID, 2, $defaultID,
        $defaultID, undef, undef, $outXportID, $defaultID,
        undef, $outXportID, $defaultID);
    my $d7GVNName = $self->getGVNName(
        "dfdtd7", $defaultID, $defaultID, $defaultID, 1, $defaultID,
        $defaultID, undef, undef, $inXportID, $defaultID,
        undef, $inXportID, $defaultID);
    my $d8GVNName = $self->getGVNName(
        "dfdtd8", "sub1", $defaultID, $defaultID, 1, $defaultID,
        $defaultID, undef, undef, $outXportID2, $defaultID,
        undef, $outXportID2, $defaultID);
    my $d9GVNName = $self->getGVNName(
        "dfdtd9", $defaultID, $defaultID, $defaultID, 1, $defaultID,
        $defaultID, undef, undef, $inoutXportID, $defaultID,
        undef, $inoutXportID, $defaultID);
    my $d10GVNName = $self->getGVNName(
        "dfdtd10", $defaultID, $defaultID, $defaultID, 1, $defaultID,
        $defaultID, undef, undef, $inoutXportID, $defaultID,
        undef, $inoutXportID, $defaultID);
    my $expected =
        getGraphTop($anchorName, "$procFN$procID", "$procID $procLB")
        . getProcDotDef($procGVNName, $procDefaults, $url, $procName,
                        $procID, $subID, $defaultID)
        . getDataDotDef($d10GVNName, $dataDefaults, undef, "dfdtd10",
                        "dfdtd10", $defaultID, $defaultID)
        . getDataDotDef($d6_1GVNName, $dataDefaults, undef, "dfdtd6",
                        "dfdtd6", $defaultID, $defaultID)
        . getDataDotDef($d6_2GVNName, $dataDefaults, undef, "dfdtd6",
                        "dfdtd6", $defaultID, $defaultID)
        . getDataDotDef($d7GVNName, $dataDefaults, undef, "dfdtd7",
                        "dfdtd7", $defaultID, $defaultID)
        . getDataDotDef($d9GVNName, $dataDefaults, undef, "dfdtd9",
                        "dfdtd9", $defaultID, $defaultID)
        . getDataDotDef($d8GVNName, $dataDefaults, undef, "dfdtd8",
                        "dfdtd8", "sub1", $defaultID)
        . getEdge($procGVNName, $d10GVNName, "Transport", $inoutXportID,
                  $inoutXportID, $defaultID, $defaultID, 0, $bothExtra)
        . getEdge($procGVNName, $d9GVNName, "Transport", $inoutXportID,
                  $inoutXportID, $defaultID, $defaultID, 0, $bothExtra)
        . getEdge($procGVNName, $d8GVNName, "Transport", $outXportID2,
                  $outXportID2, $defaultID, $defaultID, 0)
        . getEdge($d6_1GVNName, $procGVNName, "Transport", $inXportID,
                  $inXportID, $defaultID, $defaultID, 0)
        . getEdge($d6_2GVNName, $procGVNName, "Transport", $outXportID,
                  $outXportID, $defaultID, $defaultID, 0, "", 1)
        . getEdge($d7GVNName, $procGVNName, "Transport", $inXportID,
                  $inXportID, $defaultID, $defaultID, 0)
        . getGraphBottom();
    $self->runAndCheck($testText, $expected);
}


# Test DFDDATA with group and transport and no associated processes
# Defined entities:
#   Data: dfdtd11
# Undefined entities:
#   Transport: dfdtx1
# Groups: dfdtg1
sub test_DFDDATA_1 {
    my $self = shift;
    my $dataID = "dfdtd11";
    my $dataName = $dataID;
    my $subID = $defaultID;
    my $xportID = "dfdtx1";
    my $xportSubID = $defaultID;
    my $localeID = $defaultID;
    my $localeSubID = $defaultID;
    my $group = "dfdtg1";
    my $instNum = "1";
    my $testText = "%DFDDATA{id=\"$dataID\" xport=\"$xportID\" groups=\"$group\"}%";
    my ($anchorName, $url, $gvnName) = $self->getEverything(
        $dataTag, $dataID, $subID, $localeID, $localeSubID, $instNum,
        $localeID, $localeSubID, undef, undef,
        undef, $xportID, $xportSubID,
        undef, $xportID, $xportSubID);
    my $expected =
        getGraphTop($anchorName, "$dataFN$dataID", "$dataID $dataLB")
        . getDataDotDef($gvnName, $dataDefaults, $url, $dataName,
                        $dataID, $subID, $group, 1)
        . getGraphBottom();
    $self->runAndCheck($testText, $expected);
}


# Test DFDPROC with a defined data type
# Defined entities:
#   Process:   dfdtp5
#   Data:      dfdtd12
#   Transport: dfdtx2
# Groups: dfdtg1
sub test_DFDPROC_5 {
    my $self = shift;
    my ($procID, $procName, $procSubID, $localeID, $localeSubID, $procInst,
        $procGroupID) =
            ("dfdtp5", "dfdtp5", $defaultID, $defaultID, $defaultID, "1",
             $defaultID);
    my ($dataID, $dataName, $dataSubID, $dataGroupID) =
        ("dfdtd12", "dfdtd12", $defaultID, "dfdtg1");
    my ($xportID, $xportName, $xportSubID, $xportGroupID) =
        ("dfdtx2", "dfdtx2", $defaultID, $defaultID);
    my $testText = "%DFDPROC{id=\"$procID\" outputs=\"$dataID\"}%\n"
        . "%DFDDATA{id=\"$dataID\" xport=\"$xportID\" groups=\"$dataGroupID\"}%\n"
        . "%DFDTRANSPORT{id=\"$xportID\"}%";
    my $procAnchor = $procTag . ucfirst($procID);
    my $dataAnchor = $dataTag . ucfirst($dataID);
    my $xportAnchor = $xportTag . ucfirst($xportID);
    my $procUrl = Foswiki::Func::getViewUrl(
        $self->{test_web}, $self->{test_topic}) . "#" . $procAnchor;
    my $dataUrl = Foswiki::Func::getViewUrl(
        $self->{test_web}, $self->{test_topic}) . "#" . $dataAnchor;
    my $xportUrl = Foswiki::Func::getViewUrl(
        $self->{test_web}, $self->{test_topic}) . "#" . $xportAnchor;
    # graphviz node names
    my $procGVNName = $self->getGVNName(
        $procID, $procSubID, $localeID, $localeSubID, $procInst);
    my $d12GVNName = $self->getGVNName(
        $dataID, $dataSubID, $localeID, $localeSubID, "1", $localeID,
        $localeSubID, undef, undef, $xportID, $xportSubID,
        undef, $xportID, $xportSubID);
    my $expected =
        getGraphTop($procAnchor, "$procFN$procID", "$procID $procLB")
        . getProcDotDef($procGVNName, $procDefaults, $procUrl,
                        $procName, $procID, $procSubID, $defaultID)
        . getDataDotDef($d12GVNName, $dataDefaults, $dataUrl, $dataName,
                        $dataID, $dataSubID, $dataGroupID, 1)
        . getEdge($procGVNName, $d12GVNName, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 1, "", 0,
                  $xportUrl)
        . getGraphBottom() . "\n"
        . getGraphTop($dataAnchor, "$dataFN$dataID", "$dataID $dataLB")
        . getProcDotDef($procGVNName, $procDefaults, $procUrl,
                        $procName, $procID, $procSubID, $defaultID)
        . getDataDotDef($d12GVNName, $dataDefaults, $dataUrl, $dataName,
                        $dataID, $dataSubID, $dataGroupID, 1)
        . getEdge($procGVNName, $d12GVNName, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 1, "", 0,
                  $xportUrl)
        . getGraphBottom() . "\n"
        . getAnchor($xportAnchor)
        ;
    $self->runAndCheck($testText, $expected);
}


# Test DFDLOCALE
# Defined entities:
#   Locale: dfdtl1
sub test_DFDLOCALE_1 {
    my $self = shift;
    my $localeID = "dfdtl1";
    my $localeName = "DFD Plugin Locale 1";
    my $testText = "%DFDLOCALE{id=\"$localeID\" name=\"$localeName\"}%";
    my $locAnchor = $locTag . ucfirst($localeID);
    my $locaUrl = Foswiki::Func::getViewUrl(
        $self->{test_web}, $self->{test_topic}) . "#" . $locAnchor;
    my $expected = getAnchor($locAnchor);
    $self->runAndCheck($testText, $expected);
}


# Test Data Types with Sub-IDs
# Defined entities:
#   Data:      dfdtd30
#   Process:   dfdtp25, dfdtp26, dfdtp27, dfdtp28 
# Undefined entites:
#   Transport: dfdtx10
sub test_DFDDATA_2 {
    my $self = shift;
    my $dataID = "dfdtd30";
    my $group = $defaultID;
    my $xportID = "dfdtx10";
    my ($p25, $p26, $p27, $p28) = ("dfdtp25", "dfdtp26", "dfdtp27", "dfdtp28");
    my $testText = "%DFDDATA{id=\"$dataID\" xport=\"$xportID\"}%\n"
        . "%DFDPROC{id=\"$p25\" outputs=\"$dataID#A0, $dataID#E5, $dataID#C0, $dataID#DB\"}%\n"
        . "%DFDPROC{id=\"$p26\" inputs=\"$dataID#A0\"}%\n"
        . "%DFDPROC{id=\"$p27\" inputs=\"$dataID#B0, $dataID#B1\"}%\n"
        . "%DFDPROC{id=\"$p28\" inputs=\"$dataID#E5\"}%"
        ;
    my ($dataAnchor, $dataURL, $dataGVN) = $self->getEverything(
        $dataTag, $dataID, $defaultID, $defaultID, $defaultID, 1,
        $defaultID, $defaultID, undef, undef,
        undef, $xportID, $defaultID,
        undef, $xportID, $defaultID);
    my $dataA0GVN = $self->getGVNName(
        $dataID, "A0", $defaultID, $defaultID, 1, $defaultID, $defaultID, undef,
        undef, $xportID, $defaultID,
        undef, $xportID, $defaultID);
    my $dataB0GVN = $self->getGVNName(
        $dataID, "B0", $defaultID, $defaultID, 1, $defaultID, $defaultID, undef,
        undef, $xportID, $defaultID,
        undef, $xportID, $defaultID);
    my $dataB1GVN = $self->getGVNName(
        $dataID, "B1", $defaultID, $defaultID, 1, $defaultID, $defaultID, undef,
        undef, $xportID, $defaultID,
        undef, $xportID, $defaultID);
    my $dataC0GVN = $self->getGVNName(
        $dataID, "C0", $defaultID, $defaultID, 1, $defaultID, $defaultID, undef,
        undef, $xportID, $defaultID,
        undef, $xportID, $defaultID);
    my $dataDBGVN = $self->getGVNName(
        $dataID, "DB", $defaultID, $defaultID, 1, $defaultID, $defaultID, undef,
        undef, $xportID, $defaultID,
        undef, $xportID, $defaultID);
    my $dataE5GVN = $self->getGVNName(
        $dataID, "E5", $defaultID, $defaultID, 1, $defaultID, $defaultID, undef,
        undef, $xportID, $defaultID,
        undef, $xportID, $defaultID);
    my ($p25Anchor, $p25Url, $p25GVN) = $self->getEverything($procTag, $p25);
    my ($p26Anchor, $p26Url, $p26GVN) = $self->getEverything($procTag, $p26);
    my ($p27Anchor, $p27Url, $p27GVN) = $self->getEverything($procTag, $p27);
    my ($p28Anchor, $p28Url, $p28GVN) = $self->getEverything($procTag, $p28);
    my $expected =
        getGraphTop($dataAnchor, "$dataFN$dataID", "$dataID $dataLB")
        . getProcDotDef($p25GVN, $procDefaults, $p25Url,
                        $p25, $p25, $defaultID, $defaultID)
        . getProcDotDef($p26GVN, $procDefaults, $p26Url,
                        $p26, $p26, $defaultID, $defaultID)
        . getProcDotDef($p27GVN, $procDefaults, $p27Url,
                        $p27, $p27, $defaultID, $defaultID)
        . getProcDotDef($p28GVN, $procDefaults, $p28Url,
                        $p28, $p28, $defaultID, $defaultID)
        . getDataDotDef($dataGVN, $dataDefaults, $dataURL, $dataID,
                        $dataID, $defaultID, $group, 1)
        . getEdge($p25GVN, $dataGVN, "Transport", $xportID, $xportID,
                  $defaultID, $group, 0)
        . getEdge($dataGVN, $p26GVN, "Transport", $xportID, $xportID,
                  $defaultID, $group, 0)
        . getEdge($dataGVN, $p27GVN, "Transport", $xportID, $xportID,
                  $defaultID, $group, 0)
        . getEdge($dataGVN, $p28GVN, "Transport", $xportID, $xportID,
                  $defaultID, $group, 0)
        . getGraphBottom() . "\n"
        . getGraphTop($p25Anchor, "$procFN$p25", "$p25 $procLB")
        . getProcDotDef($p25GVN, $procDefaults, $p25Url,
                        $p25, $p25, $defaultID, $defaultID)
        . getDataDotDef($dataA0GVN, $dataDefaults, $dataURL, $dataID,
                        $dataID, "A0", $group, 1)
        . getDataDotDef($dataC0GVN, $dataDefaults, $dataURL, $dataID,
                        $dataID, "C0", $group, 1)
        . getDataDotDef($dataDBGVN, $dataDefaults, $dataURL, $dataID,
                        $dataID, "DB", $group, 1)
        . getDataDotDef($dataE5GVN, $dataDefaults, $dataURL, $dataID,
                        $dataID, "E5", $group, 1)
        . getEdge($p25GVN, $dataA0GVN, "Transport", $xportID, $xportID,
                  $defaultID, $group, 0)
        . getEdge($p25GVN, $dataC0GVN, "Transport", $xportID, $xportID,
                  $defaultID, $group, 0)
        . getEdge($p25GVN, $dataDBGVN, "Transport", $xportID, $xportID,
                  $defaultID, $group, 0)
        . getEdge($p25GVN, $dataE5GVN, "Transport", $xportID, $xportID,
                  $defaultID, $group, 0)
        . getGraphBottom() . "\n"
        . getGraphTop($p26Anchor, "$procFN$p26", "$p26 $procLB")
        . getProcDotDef($p26GVN, $procDefaults, $p26Url,
                        $p26, $p26, $defaultID, $defaultID)
        . getDataDotDef($dataA0GVN, $dataDefaults, $dataURL, $dataID,
                        $dataID, "A0", $group, 1)
        . getEdge($dataA0GVN, $p26GVN, "Transport", $xportID, $xportID,
                  $defaultID, $group, 0)
        . getGraphBottom() . "\n"
        . getGraphTop($p27Anchor, "$procFN$p27", "$p27 $procLB")
        . getProcDotDef($p27GVN, $procDefaults, $p27Url,
                        $p27, $p27, $defaultID, $defaultID)
        . getDataDotDef($dataB0GVN, $dataDefaults, $dataURL, $dataID,
                        $dataID, "B0", $group, 1)
        . getDataDotDef($dataB1GVN, $dataDefaults, $dataURL, $dataID,
                        $dataID, "B1", $group, 1)
        . getEdge($dataB0GVN, $p27GVN, "Transport", $xportID, $xportID,
                  $defaultID, $group, 0)
        . getEdge($dataB1GVN, $p27GVN, "Transport", $xportID, $xportID,
                  $defaultID, $group, 0)
        . getGraphBottom() . "\n"
        . getGraphTop($p28Anchor, "$procFN$p28", "$p28 $procLB")
        . getProcDotDef($p28GVN, $procDefaults, $p28Url,
                        $p28, $p28, $defaultID, $defaultID)
        . getDataDotDef($dataE5GVN, $dataDefaults, $dataURL, $dataID,
                        $dataID, "E5", $group, 1)
        . getEdge($dataE5GVN, $p28GVN, "Transport", $xportID, $xportID,
                  $defaultID, $group, 0)
        . getGraphBottom()
        ;
    $self->runAndCheck($testText, $expected);
}


# Test Process with single defined data type as input and output
# Defined entities:
#   Data:    dfdtd31
#   Process: dfdtp29
sub test_DFDPROC_6 {
    my $self = shift;
    my ($procID, $procName, $procSubID, $localeID, $localeSubID, $procInst,
        $procGroupID) =
            ("dfdtp29", "dfdtp29", $defaultID, $defaultID, $defaultID, "1",
             $defaultID);
    my ($dataID, $dataName, $dataSubID, $dataGroupID) =
        ("dfdtd31", "dfdtd31", "E5", $defaultID);
    my ($xportID, $xportName, $xportSubID, $xportGroupID) =
        ("dfdtx10", "dfdtx10", $defaultID, $defaultID);
    my $testText = 
        "%DFDDATA{id=\"$dataID\" xport=\"$xportID\"}%\n" .
        "%DFDPROC{id=\"$procID\" inputs=\"$dataID#$dataSubID\" outputs=\"$dataID#$dataSubID\"}%";
    # these is for the definition, hence using DEFAULT for sub ID
    my ($procAnchor, $procUrl, $procGVN) = $self->getEverything(
        $procTag, $procID, $defaultID, $localeID, $localeSubID, "1");
    my ($dataAnchor, $dataUrl, $dataGVN) = $self->getEverything(
        $dataTag, $dataID, $defaultID, $localeID, $localeSubID, "1", $localeID,
        $localeSubID, undef, undef, undef, $xportID, $xportSubID,
        undef, $xportID, $xportSubID);
    # These are for use as non-defining nodes, i.e. nodes in
    # definition graphs that are not the entity being defined.
    my $procInGVN = $self->getGVNName(
        $procID, $procSubID, $localeID, $localeSubID, "1");
    my $procOutGVN = $self->getGVNName(
        $procID, $procSubID, $localeID, $localeSubID, "2");
    my $dataInGVN = $self->getGVNName(
        $dataID, $dataSubID, $localeID, $localeSubID, "1", $localeID,
        $localeSubID, undef, undef, $xportID, $xportSubID,
        undef, $xportID, $xportSubID);
    my $dataOutGVN = $self->getGVNName(
        $dataID, $dataSubID, $localeID, $localeSubID, "2", $localeID,
        $localeSubID, undef, undef, $xportID, $xportSubID,
        undef, $xportID, $xportSubID);
    my $expected =
        getGraphTop($dataAnchor, "$dataFN$dataID", "$dataID $dataLB")
        . getProcDotDef($procInGVN, $procDefaults, $procUrl,
                        $procName, $procID, $procSubID, $defaultID)
        . getProcDotDef($procOutGVN, $procDefaults, $procUrl,
                        $procName, $procID, $procSubID, $defaultID)
        . getDataDotDef($dataGVN, $dataDefaults, $dataUrl, $dataName,
                        $dataID, $defaultID, $dataGroupID, 1)
        . getEdge($procInGVN, $dataGVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 0)
        . getEdge($dataGVN, $procOutGVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 0)
        . getGraphBottom() . "\n"
        . getGraphTop($procAnchor, "$procFN$procID", "$procID $procLB")
        . getProcDotDef($procGVN, $procDefaults, $procUrl,
                        $procName, $procID, $procSubID, $defaultID)
        . getDataDotDef($dataOutGVN, $dataDefaults, $dataUrl, $dataName,
                        $dataID, $dataSubID, $dataGroupID, 1)
        . getDataDotDef($dataInGVN, $dataDefaults, $dataUrl,
                        $dataName, $dataID, $dataSubID, $dataGroupID,
                        1)
        . getEdge($procGVN, $dataOutGVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 0)
        . getEdge($dataInGVN, $procGVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 0)
        . getGraphBottom();
    $self->runAndCheck($testText, $expected);
}


# Test Process with single defined data type as input and output
# Defined entities:
#   Process: dfdtp30
# Undefined entities:
#   Locale:  dfdtl12, dfdtl13
#   Data:    dfdtd32, dfdtd33, dfdtd34
sub test_DFDPROC_7 {
    my $self = shift;
    my ($procID, $procName, $procSubID, $loc1ID, $loc2ID, $locSubID,
        $procInst, $procGroupID) =
            ("dfdtp30", "dfdtp30", $defaultID, "dfdtl12", "dfdtl13", $defaultID,
             "1", $defaultID);
    my ($d32ID, $d32Name, $d32SubID, $d32GroupID) =
        ("dfdtd32", "dfdtd32", $defaultID, $defaultID);
    my ($d33ID, $d33Name, $d33SubID, $d33GroupID) =
        ("dfdtd33", "dfdtd33", $defaultID, $defaultID);
    my ($d34ID, $d34Name, $d34SubID, $d34GroupID) =
        ("dfdtd34", "dfdtd34", $defaultID, $defaultID);
    my $testText = "%DFDPROC{id=\"$procID\" locales=\"$loc1ID, $loc2ID\" inputs=\"$d32ID, $d33ID\" outputs=\"$d34ID\"}%";
    my ($procAnchor, $procUrl, $procGVN) = $self->getEverything(
        $procTag, $procID, $defaultID, $loc1ID, $locSubID, "1");
    my ($d32Anchor, $d32Url, $d32GVN) = $self->getEverything(
        $dataTag, $d32ID, $defaultID, $loc1ID, $locSubID, "1", $loc1ID,
        $locSubID, undef, undef, undef, $defaultID, $defaultID,
        undef, $defaultID, $defaultID);
    my ($d33Anchor, $d33Url, $d33GVN) = $self->getEverything(
        $dataTag, $d33ID, $defaultID, $loc1ID, $locSubID, "1", $loc1ID,
        $locSubID, undef, undef, undef, $defaultID, $defaultID,
        undef, $defaultID, $defaultID);
    my ($d34Anchor, $d34Url, $d34GVN) = $self->getEverything(
        $dataTag, $d34ID, $defaultID, $loc1ID, $locSubID, "1", $loc1ID,
        $locSubID, undef, undef, undef, $defaultID, $defaultID,
        undef, $defaultID, $defaultID);
    # undefined data means undef URL
    my $expected =
        getGraphTop($procAnchor, "$procFN$procID", "$procID $procLB")
        . getProcDotDef($procGVN, $procDefaults, $procUrl,
                        $procName, $procID, $procSubID, $defaultID)
        . getDataDotDef($d32GVN, $dataDefaults, undef, $d32Name,
                        $d32ID, $defaultID, $defaultID, 0)
        . getDataDotDef($d33GVN, $dataDefaults, undef, $d33Name,
                        $d33ID, $defaultID, $defaultID, 0)
        . getDataDotDef($d34GVN, $dataDefaults, undef, $d34Name,
                        $d34ID, $defaultID, $defaultID, 0)
        . getEdge($procGVN, $d34GVN, "Transport", $defaultID,
                  $defaultID, $defaultID, $defaultID, 0)
        . getEdge($d32GVN, $procGVN, "Transport", $defaultID,
                  $defaultID, $defaultID, $defaultID, 0)
        . getEdge($d33GVN, $procGVN, "Transport", $defaultID,
                  $defaultID, $defaultID, $defaultID, 0)
        . getGraphBottom();
    $self->runAndCheck($testText, $expected);
}


# Test Process with single defined data type as input and output
# Defined entities:
#   Process:   dfdtp31
# Undefined entities:
#   Data:      dfdtd37
#   Transport: dfdtx11
sub test_DFDPROC_8 {
    my $self = shift;
    my ($procID, $procName, $procSubID, $procInst, $procGroupID) =
            ("dfdtp31", "dfdtp31", $defaultID, "1", $defaultID);
    my ($d37ID, $d37Name, $d37SubID, $d37GroupID) =
        ("dfdtd37", "dfdtd37", $defaultID, $defaultID);
    my ($xportID, $xportName, $xportSubID) = ("dfdtx11", "dfdtx11", "tx11sub");
    my $testText = "%DFDPROC{id=\"$procID\" inputs=\"$d37ID###$xportID#$xportSubID\"}%";
    my ($procAnchor, $procUrl, $procGVN) = $self->getEverything(
        $procTag, $procID, $procSubID, $defaultID, $defaultID, "1");
    my ($d37Anchor, $d37Url, $d37GVN) = $self->getEverything(
        $dataTag, $d37ID, $d37SubID, $defaultID, $defaultID, "1", $defaultID,
        $defaultID, undef, undef, undef, $xportID, $xportSubID,
        undef, $xportID, $xportSubID);
    # undefined data means undef URL
    my $expected =
        getGraphTop($procAnchor, "$procFN$procID", "$procID $procLB")
        . getProcDotDef($procGVN, $procDefaults, $procUrl,
                        $procName, $procID, $procSubID, $defaultID)
        . getDataDotDef($d37GVN, $dataDefaults, undef, $d37Name,
                        $d37ID, $defaultID, $defaultID, 0)
        . getEdge($d37GVN, $procGVN, "Transport", $xportName,
                  $xportID, $xportSubID, $defaultID, 0)
        . getGraphBottom();
    $self->runAndCheck($testText, $expected);
}


# Test connections with undefined data type, no locale and no transport
# Defined entities:
#   Process: dfdtp9, dfdtp10
# Undefined entities:
#   Data:    dfdtd18
sub test_DFDCONNECT_1 {
    my $self = shift;
    my ($p9ID, $p9Name, $p9SubID, $locID, $locSubID, $p9Inst, $p9GroupID) =
        ("dfdtp9", "dfdtp9", $defaultID, $defaultID, $defaultID,
         "1", $defaultID);
    my ($p10ID, $p10Name, $p10SubID, $p10Inst, $p10GroupID) =
        ("dfdtp10", "dfdtp10", $defaultID, "1", $defaultID);
    my ($d18ID, $d18Name, $d18SubID, $d18GroupID) =
        ("dfdtd18", "dfdtd18", $defaultID, $defaultID);
    my $testText =
        "%DFDPROC{id=\"$p9ID\" outputs=\"$d18ID\"}%\n" .
        "%DFDPROC{id=\"$p10ID\" inputs=\"$d18ID\"}%\n" .
        "%DFDCONNECT{id=\"$p9ID\" type=\"proc\" level=\"3\" nolocales=\"0\" datanodes=\"0\"}%\n" .
        "%DFDCONNECT{id=\"$p9ID\" type=\"proc\" level=\"3\" nolocales=\"0\" datanodes=\"1\"}%";
    my ($p9Anchor, $p9Url, $p9GVN) = $self->getEverything(
        $procTag, $p9ID, $defaultID, $locID, $locSubID, "1");
    my ($p10Anchor, $p10Url, $p10GVN) = $self->getEverything(
        $procTag, $p10ID, $defaultID, $locID, $locSubID, "1");
    my ($d18Anchor, $d18Url, $d18GVN) = $self->getEverything(
        $dataTag, $d18ID, $defaultID, $locID, $locSubID, "1", $locID,
        $locSubID, undef, undef, undef, $defaultID, $defaultID,
        undef, $defaultID, $defaultID);
    my $graphnum = 1;
    my $expected =
        getGraphTop($p9Anchor, "$procFN$p9ID", "$p9ID $procLB")
        . getProcDotDef($p9GVN, $procDefaults, $p9Url,
                        $p9Name, $p9ID, $p9SubID, $defaultID)
        . getDataDotDef($d18GVN, $dataDefaults, undef, $d18Name,
                        $d18ID, $defaultID, $defaultID, 0)
        . getEdge($p9GVN, $d18GVN, "Transport", $defaultID,
                  $defaultID, $defaultID, $defaultID, 0)
        . getGraphBottom() . "\n"
        . getGraphTop($p10Anchor, "$procFN$p10ID", "$p10ID $procLB")
        . getProcDotDef($p10GVN, $procDefaults, $p10Url,
                        $p10Name, $p10ID, $p10SubID, $defaultID)
        . getDataDotDef($d18GVN, $dataDefaults, undef, $d18Name,
                        $d18ID, $defaultID, $defaultID, 0)
        . getEdge($d18GVN, $p10GVN, "Transport", $defaultID,
                  $defaultID, $defaultID, $defaultID, 0)
        . getGraphBottom() . "\n"
        . getGraphTop(undef, sprintf("%s%s_%03d",$cnctFN,$p9ID,$graphnum++))
        # I keep making this mistake - p10 comes before p9 because ascii sort,
        # not numerical sort. Change it to p09 to get a "numeric" sort.
        . getProcDotDef($p10GVN, $procDefaults, $p10Url,
                        $p10Name, $p10ID, $p10SubID, $defaultID)
        . getProcDotDef($p9GVN, $procDefaults, $p9Url,
                        $p9Name, $p9ID, $p9SubID, $defaultID)
        . getEdge($p9GVN, $p10GVN, "Transport", $defaultID,
                  $defaultID, $defaultID, $defaultID, 0)
        . getGraphBottom() . "\n"
        . getGraphTop(undef, sprintf("%s%s_%03d",$cnctFN,$p9ID,$graphnum++))
        # I keep making this mistake - p10 comes before p9 because ascii sort,
        # not numerical sort. Change it to p09 to get a "numeric" sort.
        . getProcDotDef($p10GVN, $procDefaults, $p10Url,
                        $p10Name, $p10ID, $p10SubID, $defaultID)
        . getProcDotDef($p9GVN, $procDefaults, $p9Url,
                        $p9Name, $p9ID, $p9SubID, $defaultID)
        . getDataDotDef($d18GVN, $dataDefaults, undef, $d18Name,
                        $d18ID, $defaultID, $defaultID, 0)
        . getEdge($p9GVN, $d18GVN, "Transport", $defaultID,
                  $defaultID, $defaultID, $defaultID, 0)
        . getEdge($d18GVN, $p10GVN, "Transport", $defaultID,
                  $defaultID, $defaultID, $defaultID, 0)
        . getGraphBottom()
        ;
    $self->runAndCheck($testText, $expected);
}


# Test connections with undefined data type, undefined transport and no locale
# Defined entities:
#   Process:   dfdtp11, dfdtp12
# Undefined entities:
#   Data:      dfdtd19
#   Transport: dfdtx4
sub test_DFDCONNECT_2 {
    my $self = shift;
    my ($p11ID, $p11Name, $p11SubID, $locID, $locSubID, $p11Inst, $p11GroupID) =
        ("dfdtp11", "dfdtp11", $defaultID, $defaultID, $defaultID,
         "1", $defaultID);
    my ($p12ID, $p12Name, $p12SubID, $p12Inst, $p12GroupID) =
        ("dfdtp12", "dfdtp12", $defaultID, "1", $defaultID);
    my ($d19ID, $d19Name, $d19SubID, $d19GroupID) =
        ("dfdtd19", "dfdtd19", $defaultID, $defaultID);
    my ($xportID, $xportName, $xportSubID, $xportGroupID) =
        ("dfdtx4", "dfdtx4", $defaultID, $defaultID);
    my $testText =
        "%DFDPROC{id=\"$p11ID\" outxport=\"$xportID\" outputs=\"$d19ID\"}%\n" .
        "%DFDPROC{id=\"$p12ID\" inxport=\"$xportID\" inputs=\"$d19ID\"}%\n" .
        "%DFDCONNECT{id=\"$p11ID\" type=\"proc\" level=\"3\" nolocales=\"0\" datanodes=\"0\"}%\n" .
        "%DFDCONNECT{id=\"$p11ID\" type=\"proc\" level=\"3\" nolocales=\"0\" datanodes=\"1\"}%";
    my ($p11Anchor, $p11Url, $p11GVN) = $self->getEverything(
        $procTag, $p11ID, $defaultID, $locID, $locSubID, "1");
    my ($p12Anchor, $p12Url, $p12GVN) = $self->getEverything(
        $procTag, $p12ID, $defaultID, $locID, $locSubID, "1");
    my ($d19Anchor, $d19Url, $d19GVN) = $self->getEverything(
        $dataTag, $d19ID, $defaultID, $locID, $locSubID, "1", $locID,
        $locSubID, undef, undef, undef, $xportID, $xportSubID,
        undef, $xportID, $xportSubID);
    my $graphnum = 1;
    my $expected =
        getGraphTop($p11Anchor, "$procFN$p11ID", "$p11ID $procLB")
        . getProcDotDef($p11GVN, $procDefaults, $p11Url,
                        $p11Name, $p11ID, $p11SubID, $defaultID)
        . getDataDotDef($d19GVN, $dataDefaults, undef, $d19Name,
                        $d19ID, $defaultID, $defaultID, 0)
        . getEdge($p11GVN, $d19GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 0)
        . getGraphBottom() . "\n"
        . getGraphTop($p12Anchor, "$procFN$p12ID", "$p12ID $procLB")
        . getProcDotDef($p12GVN, $procDefaults, $p12Url,
                        $p12Name, $p12ID, $p12SubID, $defaultID)
        . getDataDotDef($d19GVN, $dataDefaults, undef, $d19Name,
                        $d19ID, $defaultID, $defaultID, 0)
        . getEdge($d19GVN, $p12GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 0)
        . getGraphBottom() . "\n"
        . getGraphTop(undef, sprintf("%s%s_%03d",$cnctFN,$p11ID,$graphnum++))
        . getProcDotDef($p11GVN, $procDefaults, $p11Url,
                        $p11Name, $p11ID, $p11SubID, $defaultID)
        . getProcDotDef($p12GVN, $procDefaults, $p12Url,
                        $p12Name, $p12ID, $p12SubID, $defaultID)
        . getEdge($p11GVN, $p12GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 0)
        . getGraphBottom() . "\n"
        . getGraphTop(undef, sprintf("%s%s_%03d",$cnctFN,$p11ID,$graphnum++))
        . getProcDotDef($p11GVN, $procDefaults, $p11Url,
                        $p11Name, $p11ID, $p11SubID, $defaultID)
        . getProcDotDef($p12GVN, $procDefaults, $p12Url,
                        $p12Name, $p12ID, $p12SubID, $defaultID)
        . getDataDotDef($d19GVN, $dataDefaults, undef, $d19Name,
                        $d19ID, $defaultID, $defaultID, 0)
        . getEdge($p11GVN, $d19GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 0)
        . getEdge($d19GVN, $p12GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 0)
        . getGraphBottom()
        ;
    $self->runAndCheck($testText, $expected);
}


# Test connections with undefined data type, undefined transport and
# undefined split locales.  Should be no connections between processes
# with named but undefined locales, as the connections between locales
# are defined with the locales themselves.
# Defined entities:
#   Process:   dfdtp13, dfdtp14
# Undefined entities:
#   Data:      dfdtd20
#   Transport: dfdtx4
#   Locale:    dfdtl3, dfdtl4
sub test_DFDCONNECT_3 {
    my $self = shift;
    my ($p13ID, $p13Name, $p13SubID, $p13Inst, $p13GroupID) =
        ("dfdtp13", "dfdtp13", $defaultID, "1", $defaultID);
    my ($p14ID, $p14Name, $p14SubID, $p14Inst, $p14GroupID) =
        ("dfdtp14", "dfdtp14", $defaultID, "1", $defaultID);
    my ($d20ID, $d20Name, $d20SubID, $d20GroupID) =
        ("dfdtd20", "dfdtd20", $defaultID, $defaultID);
    my ($l13ID, $l14ID) = ("dfdtl3", "dfdtl4");
    my ($xportID, $xportName, $xportSubID, $xportGroupID) =
        ("dfdtx4", "dfdtx4", $defaultID, $defaultID);
    my $testText =
        "%DFDPROC{id=\"$p13ID\" locales=\"$l13ID\" outxport=\"$xportID\" outputs=\"$d20ID\"}%\n" .
        "%DFDPROC{id=\"$p14ID\" locales=\"$l14ID\" inxport=\"$xportID\" inputs=\"$d20ID\"}%\n" .
        "%DFDCONNECT{id=\"$p13ID\" type=\"proc\" level=\"3\" nolocales=\"0\" datanodes=\"0\"}%\n" .
        "%DFDCONNECT{id=\"$p13ID\" type=\"proc\" level=\"3\" nolocales=\"0\" datanodes=\"1\"}%\n" .
        "%DFDCONNECT{id=\"$p14ID\" type=\"proc\" level=\"3\" nolocales=\"0\" datanodes=\"0\"}%\n" .
        "%DFDCONNECT{id=\"$p14ID\" type=\"proc\" level=\"3\" nolocales=\"0\" datanodes=\"1\"}%";
    my ($p13Anchor, $p13Url, $p13GVN) = $self->getEverything(
        $procTag, $p13ID, $defaultID, $l13ID, $defaultID, "1");
    my ($p14Anchor, $p14Url, $p14GVN) = $self->getEverything(
        $procTag, $p14ID, $defaultID, $l14ID, $defaultID, "1");
    my ($d20Anchor, $d20Url, $d20GVN) = $self->getEverything(
        $dataTag, $d20ID, $defaultID, $l13ID, $defaultID, "1", $l14ID,
        $defaultID);
    my $d20_13GVN = $self->getGVNName(
        $d20ID, $defaultID, $l13ID, $defaultID, "1", $l13ID, $defaultID,
        undef, undef, $xportID, $xportSubID, undef, $xportID, $xportSubID);
    my $d20_14GVN = $self->getGVNName(
        $d20ID, $defaultID, $l14ID, $defaultID, "1", $l14ID, $defaultID,
        undef, undef, $xportID, $xportSubID, undef, $xportID, $xportSubID);
    my $graphnum = 1;
    my $expected =
        getGraphTop($p13Anchor, "$procFN$p13ID", "$p13ID $procLB")
        . getProcDotDef($p13GVN, $procDefaults, $p13Url,
                        $p13Name, $p13ID, $p13SubID, $defaultID)
        . getDataDotDef($d20_13GVN, $dataDefaults, undef, $d20Name,
                        $d20ID, $defaultID, $defaultID, 0)
        . getEdge($p13GVN, $d20_13GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 0)
        . getGraphBottom() . "\n"
        . getGraphTop($p14Anchor, "$procFN$p14ID", "$p14ID $procLB")
        . getProcDotDef($p14GVN, $procDefaults, $p14Url,
                        $p14Name, $p14ID, $p14SubID, $defaultID)
        . getDataDotDef($d20_14GVN, $dataDefaults, undef, $d20Name,
                        $d20ID, $defaultID, $defaultID, 0)
        . getEdge($d20_14GVN, $p14GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 0)
        . getGraphBottom() . "\n"
        . getGraphTop(undef, sprintf("%s%s_%03d",$cnctFN,$p13ID,$graphnum++))
        . $self->getSubGraphTop($l13ID)
        . getProcDotDef($p13GVN, $procDefaults, $p13Url,
                        $p13Name, $p13ID, $p13SubID, $defaultID)
        . getSubGraphBottom()
        . getGraphBottom() . "\n"
        . getGraphTop(undef, sprintf("%s%s_%03d",$cnctFN,$p13ID,$graphnum--))
        . $self->getSubGraphTop($l13ID)
        . getProcDotDef($p13GVN, $procDefaults, $p13Url,
                        $p13Name, $p13ID, $p13SubID, $defaultID)
        . getSubGraphBottom()
        . getGraphBottom() . "\n"
        . getGraphTop(undef, sprintf("%s%s_%03d",$cnctFN,$p14ID,$graphnum++))
        . $self->getSubGraphTop($l14ID)
        . getProcDotDef($p14GVN, $procDefaults, $p14Url,
                        $p14Name, $p14ID, $p14SubID, $defaultID)
        . getSubGraphBottom()
        . getGraphBottom() . "\n"
        . getGraphTop(undef, sprintf("%s%s_%03d",$cnctFN,$p14ID,$graphnum--))
        . $self->getSubGraphTop($l14ID)
        . getProcDotDef($p14GVN, $procDefaults, $p14Url,
                        $p14Name, $p14ID, $p14SubID, $defaultID)
        . getSubGraphBottom()
        . getGraphBottom()
        ;
    $self->runAndCheck($testText, $expected);
}


# Test connections with undefined data type, defined transport and
# defined single UNCONNECTED locale.
# Defined entities:
#   Process:   dfdtp15, dfdtp16
#   Locale:    dfdtl5
#   Transport: dfdtx5
# Undefined entities:
#   Data:      dfdtd21
sub test_DFDCONNECT_4 {
    my $self = shift;
    my ($p15ID, $p15Name, $p15SubID, $p15Inst, $p15GroupID) =
        ("dfdtp15", "dfdtp15", $defaultID, "1", $defaultID);
    my ($p16ID, $p16Name, $p16SubID, $p16Inst, $p16GroupID) =
        ("dfdtp16", "dfdtp16", $defaultID, "1", $defaultID);
    my ($d21ID, $d21Name, $d21SubID, $d21GroupID) =
        ("dfdtd21", "dfdtd21", $defaultID, $defaultID);
    my ($locID, $locName) = ("dfdtl5", "DFD Plugin Locale 5");
    my ($xportID, $xportName, $xportSubID, $xportGroupID) =
        ("dfdtx5", "TX5", $defaultID, $defaultID);
    my $testText =
        "%DFDLOCALE{id=\"$locID\" name=\"$locName\"}%\n" .
        "%DFDTRANSPORT{id=\"$xportID\" name=\"TX5\"}%\n" .
        "%DFDPROC{id=\"$p15ID\" locales=\"$locID\" outxport=\"$xportID\" outputs=\"$d21ID\"}%\n" .
        "%DFDPROC{id=\"$p16ID\" locales=\"$locID\" inxport=\"$xportID\" inputs=\"$d21ID\"}%\n" .
        "%DFDCONNECT{id=\"$p15ID\" type=\"proc\" level=\"3\" nolocales=\"0\" datanodes=\"0\"}%\n" .
        "%DFDCONNECT{id=\"$p15ID\" type=\"proc\" level=\"3\" nolocales=\"0\" datanodes=\"1\"}%\n" .
        "%DFDCONNECT{id=\"$p16ID\" type=\"proc\" level=\"3\" nolocales=\"0\" datanodes=\"0\"}%\n" .
        "%DFDCONNECT{id=\"$p16ID\" type=\"proc\" level=\"3\" nolocales=\"0\" datanodes=\"1\"}%";
    my ($locAnchor, $locUrl, $dummy1) = $self->getEverything(
        $locTag, $locID, $defaultID);
    my ($xportAnchor, $xportUrl, $dummy2) = $self->getEverything(
        $xportTag, $xportID, $defaultID);
    my ($p15Anchor, $p15Url, $p15GVN) = $self->getEverything(
        $procTag, $p15ID, $defaultID, $locID, $defaultID, "1");
    my ($p16Anchor, $p16Url, $p16GVN) = $self->getEverything(
        $procTag, $p16ID, $defaultID, $locID, $defaultID, "1");
    my ($d21Anchor, $d21Url, $d21GVN) = $self->getEverything(
        $dataTag, $d21ID, $defaultID, $locID, $defaultID, "1", $locID,
        $defaultID, undef, undef, undef, $xportID, $xportSubID,
        undef, $xportID, $xportSubID);
    my $d21_15GVN = $self->getGVNName(
        $d21ID, $defaultID, $locID, $defaultID, "1", $locID, $defaultID, undef,
        undef, $xportID, $xportSubID, undef, $xportID, $xportSubID);
    my $d21_16GVN = $self->getGVNName(
        $d21ID, $defaultID, $locID, $defaultID, "1", $locID, $defaultID, undef,
        undef, $xportID, $xportSubID, undef, $xportID, $xportSubID);
    my $graphnum = 1;
    my $expected =
        getAnchor($locAnchor) . "\n"
        . getAnchor($xportAnchor) . "\n"
        . getGraphTop($p15Anchor, "$procFN$p15ID", "$p15ID $procLB")
        . getProcDotDef($p15GVN, $procDefaults, $p15Url,
                        $p15Name, $p15ID, $p15SubID, $defaultID)
        . getDataDotDef($d21_15GVN, $dataDefaults, undef, $d21Name,
                        $d21ID, $defaultID, $defaultID, 0)
        . getEdge($p15GVN, $d21_15GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 1, "", 0,
                  $xportUrl)
        . getGraphBottom() . "\n"
        . getGraphTop($p16Anchor, "$procFN$p16ID", "$p16ID $procLB")
        . getProcDotDef($p16GVN, $procDefaults, $p16Url,
                        $p16Name, $p16ID, $p16SubID, $defaultID)
        . getDataDotDef($d21_16GVN, $dataDefaults, undef, $d21Name,
                        $d21ID, $defaultID, $defaultID, 0)
        . getEdge($d21_16GVN, $p16GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 1, "", 0,
                  $xportUrl)
        . getGraphBottom() . "\n"
        . getGraphTop(undef, sprintf("%s%s_%03d",$cnctFN,$p15ID,$graphnum++))
        . $self->getSubGraphTop($locID, $locName)
        . getProcDotDef($p15GVN, $procDefaults, $p15Url,
                        $p15Name, $p15ID, $p15SubID, $defaultID)
        . getSubGraphBottom()
        . getGraphBottom() . "\n"
        . getGraphTop(undef, sprintf("%s%s_%03d",$cnctFN,$p15ID,$graphnum--))
        . $self->getSubGraphTop($locID, $locName)
        . getProcDotDef($p15GVN, $procDefaults, $p15Url,
                        $p15Name, $p15ID, $p15SubID, $defaultID)
        . getSubGraphBottom()
        . getGraphBottom() . "\n"
        . getGraphTop(undef, sprintf("%s%s_%03d",$cnctFN,$p16ID,$graphnum++))
        . $self->getSubGraphTop($locID, $locName)
        . getProcDotDef($p16GVN, $procDefaults, $p16Url,
                        $p16Name, $p16ID, $p16SubID, $defaultID)
        . getSubGraphBottom()
        . getGraphBottom() . "\n"
        . getGraphTop(undef, sprintf("%s%s_%03d",$cnctFN,$p16ID,$graphnum--))
        . $self->getSubGraphTop($locID, $locName)
        . getProcDotDef($p16GVN, $procDefaults, $p16Url,
                        $p16Name, $p16ID, $p16SubID, $defaultID)
        . getSubGraphBottom()
        . getGraphBottom()
        ;
    $self->runAndCheck($testText, $expected);
}


# Test connections with undefined data type, defined transport and
# defined single CONNECTED locale.
# Defined entities:
#   Process:   dfdtp17, dfdtp18
#   Locale:    dfdtl6
#   Transport: dfdtx6
# Undefined entities:
#   Data:      dfdtd22
sub test_DFDCONNECT_5 {
    my $self = shift;
    my ($p17ID, $p17Name, $p17SubID, $p17Inst, $p17GroupID) =
        ("dfdtp17", "dfdtp17", $defaultID, "1", $defaultID);
    my ($p18ID, $p18Name, $p18SubID, $p18Inst, $p18GroupID) =
        ("dfdtp18", "dfdtp18", $defaultID, "1", $defaultID);
    my ($d22ID, $d22Name, $d22SubID, $d22GroupID) =
        ("dfdtd22", "dfdtd22", $defaultID, $defaultID);
    my ($locID, $locName) = ("dfdtl6", "DFD Plugin Locale 6");
    my ($xportID, $xportName, $xportSubID, $xportGroupID) =
        ("dfdtx6", "TX6", $defaultID, $defaultID);
    my $testText =
        "%DFDLOCALE{id=\"$locID\" name=\"$locName\" connect=\"$locID|$xportID\"}%\n" .
        "%DFDTRANSPORT{id=\"$xportID\" name=\"$xportName\"}%\n" .
        "%DFDPROC{id=\"$p17ID\" locales=\"$locID\" outxport=\"$xportID\" outputs=\"$d22ID\"}%\n" .
        "%DFDPROC{id=\"$p18ID\" locales=\"$locID\" inxport=\"$xportID\" inputs=\"$d22ID\"}%\n" .
        "%DFDCONNECT{id=\"$p17ID\" type=\"proc\" level=\"3\" nolocales=\"0\" datanodes=\"0\"}%\n" .
        "%DFDCONNECT{id=\"$p17ID\" type=\"proc\" level=\"3\" nolocales=\"0\" datanodes=\"1\"}%\n" .
        "%DFDCONNECT{id=\"$p18ID\" type=\"proc\" level=\"3\" nolocales=\"0\" datanodes=\"0\"}%\n" .
        "%DFDCONNECT{id=\"$p18ID\" type=\"proc\" level=\"3\" nolocales=\"0\" datanodes=\"1\"}%";
    my ($locAnchor, $locUrl, $dummy1) = $self->getEverything(
        $locTag, $locID, $defaultID);
    my ($xportAnchor, $xportUrl, $dummy2) = $self->getEverything(
        $xportTag, $xportID, $defaultID);
    my ($p17Anchor, $p17Url, $p17GVN) = $self->getEverything(
        $procTag, $p17ID, $defaultID, $locID, $defaultID, "1");
    my ($p18Anchor, $p18Url, $p18GVN) = $self->getEverything(
        $procTag, $p18ID, $defaultID, $locID, $defaultID, "1");
    my ($d22Anchor, $d22Url, $d22GVN) = $self->getEverything(
        $dataTag, $d22ID, $defaultID, $locID, $defaultID, "1", $locID,
        $defaultID, undef, undef, undef, $xportID, $xportSubID,
        undef, $xportID, $xportSubID);
    my $d22_17GVN = $self->getGVNName(
        $d22ID, $defaultID, $locID, $defaultID, "1", $locID, $defaultID, undef,
        undef, $xportID, $xportSubID, undef, $xportID, $xportSubID);
    my $d22_18GVN = $self->getGVNName(
        $d22ID, $defaultID, $locID, $defaultID, "1", $locID, $defaultID, undef,
        undef, $xportID, $xportSubID, undef, $xportID, $xportSubID);
    my $graphnum = 1;
    my $expected =
        # DFDLOCALE
        getAnchor($locAnchor) . "\n"
        # DFDTRANSPORT
        . getAnchor($xportAnchor) . "\n"
        # DFDPROC
        . getGraphTop($p17Anchor, "$procFN$p17ID", "$p17ID $procLB")
        . getProcDotDef($p17GVN, $procDefaults, $p17Url,
                        $p17Name, $p17ID, $p17SubID, $defaultID)
        . getDataDotDef($d22_17GVN, $dataDefaults, undef, $d22Name,
                        $d22ID, $defaultID, $defaultID, 0)
        . getEdge($p17GVN, $d22_17GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 1, "", 0,
                  $xportUrl)
        . getGraphBottom() . "\n"
        # DFDPROC
        . getGraphTop($p18Anchor, "$procFN$p18ID", "$p18ID $procLB")
        . getProcDotDef($p18GVN, $procDefaults, $p18Url,
                        $p18Name, $p18ID, $p18SubID, $defaultID)
        . getDataDotDef($d22_18GVN, $dataDefaults, undef, $d22Name,
                        $d22ID, $defaultID, $defaultID, 0)
        . getEdge($d22_18GVN, $p18GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 1, "", 0,
                  $xportUrl)
        . getGraphBottom() . "\n"
        # DFDCONNECT
        . getGraphTop(undef, sprintf("%s%s_%03d",$cnctFN,$p17ID,$graphnum++))
        . $self->getSubGraphTop($locID, $locName)
        . getProcDotDef($p17GVN, $procDefaults, $p17Url,
                        $p17Name, $p17ID, $p17SubID, $defaultID)
        . getProcDotDef($p18GVN, $procDefaults, $p18Url,
                        $p18Name, $p18ID, $p18SubID, $defaultID)
        . getSubGraphBottom()
        . getEdge($p17GVN, $p18GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 1, "", 0,
                  $xportUrl)
        . getGraphBottom() . "\n"
        # DFDCONNECT
        . getGraphTop(undef, sprintf("%s%s_%03d",$cnctFN,$p17ID,$graphnum--))
        . $self->getSubGraphTop($locID, $locName)
        . getDataDotDef($d22_18GVN, $dataDefaults, undef, $d22Name,
                        $d22ID, $defaultID, $defaultID, 0)
        . getProcDotDef($p17GVN, $procDefaults, $p17Url,
                        $p17Name, $p17ID, $p17SubID, $defaultID)
        . getProcDotDef($p18GVN, $procDefaults, $p18Url,
                        $p18Name, $p18ID, $p18SubID, $defaultID)
        . getSubGraphBottom()
        . getEdge($p17GVN, $d22_18GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 1, "", 0,
                  $xportUrl)
        . getEdge($d22_18GVN, $p18GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 1, "", 0,
                  $xportUrl)
        . getGraphBottom() . "\n"
        # DFDCONNECT
        . getGraphTop(undef, sprintf("%s%s_%03d",$cnctFN,$p18ID,$graphnum++))
        . $self->getSubGraphTop($locID, $locName)
        . getProcDotDef($p17GVN, $procDefaults, $p17Url,
                        $p17Name, $p17ID, $p17SubID, $defaultID)
        . getProcDotDef($p18GVN, $procDefaults, $p18Url,
                        $p18Name, $p18ID, $p18SubID, $defaultID)
        . getSubGraphBottom()
        . getEdge($p17GVN, $p18GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 1, "", 0,
                  $xportUrl)
        . getGraphBottom() . "\n"
        # DFDCONNECT
        . getGraphTop(undef, sprintf("%s%s_%03d",$cnctFN,$p18ID,$graphnum--))
        . $self->getSubGraphTop($locID, $locName)
        . getDataDotDef($d22_18GVN, $dataDefaults, undef, $d22Name,
                        $d22ID, $defaultID, $defaultID, 0)
        . getProcDotDef($p17GVN, $procDefaults, $p17Url,
                        $p17Name, $p17ID, $p17SubID, $defaultID)
        . getProcDotDef($p18GVN, $procDefaults, $p18Url,
                        $p18Name, $p18ID, $p18SubID, $defaultID)
        . getSubGraphBottom()
        . getEdge($p17GVN, $d22_18GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 1, "", 0,
                  $xportUrl)
        . getEdge($d22_18GVN, $p18GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 1, "", 0,
                  $xportUrl)
        . getGraphBottom()
        ;
    $self->runAndCheck($testText, $expected);
}


# Test connections with undefined data type, undefined transport and
# undefined split locales.  Should be no connections between processes
# with named but undefined locales, as the connections between locales
# are defined with the locales themselves.
# Defined entities:
#   Process:   dfdtp19, dfdtp20
#   Locale:    dfdtl7, dfdtl8
#   Transport: dfdtx7
# Undefined entities:
#   Data:      dfdtd23
sub test_DFDCONNECT_6 {
    my $self = shift;
    my ($p19ID, $p19Name, $p19SubID, $p19Inst, $p19GroupID) =
        ("dfdtp19", "dfdtp19", $defaultID, "1", $defaultID);
    my ($p20ID, $p20Name, $p20SubID, $p20Inst, $p20GroupID) =
        ("dfdtp20", "dfdtp20", $defaultID, "1", $defaultID);
    my ($d23ID, $d23Name, $d23SubID, $d23GroupID) =
        ("dfdtd23", "dfdtd23", $defaultID, $defaultID);
    my ($l19ID, $l19Name) = ("dfdtl7", "DFD Plugin Locale 7");
    my ($l20ID, $l20Name) = ("dfdtl8", "DFD Plugin Locale 8");
    my ($xportID, $xportName, $xportSubID, $xportGroupID) =
        ("dfdtx7", "TX7", $defaultID, $defaultID);
    my $testText =
        "%DFDLOCALE{id=\"$l19ID\" name=\"$l19Name\" connect=\"$l20ID|$xportID\"}%\n" .
        "%DFDLOCALE{id=\"$l20ID\" name=\"$l20Name\" connect=\"$l19ID|$xportID\"}%\n" .
        "%DFDTRANSPORT{id=\"$xportID\" name=\"$xportName\"}%\n" .
        "%DFDPROC{id=\"$p19ID\" locales=\"$l19ID\" outxport=\"$xportID\" outputs=\"$d23ID\"}%\n" .
        "%DFDPROC{id=\"$p20ID\" locales=\"$l20ID\" inxport=\"$xportID\" inputs=\"$d23ID\"}%\n" .
        "%DFDCONNECT{id=\"$p19ID\" type=\"proc\" level=\"3\" nolocales=\"0\" datanodes=\"0\"}%\n" .
        "%DFDCONNECT{id=\"$p19ID\" type=\"proc\" level=\"3\" nolocales=\"0\" datanodes=\"1\"}%\n" .
        "%DFDCONNECT{id=\"$p20ID\" type=\"proc\" level=\"3\" nolocales=\"0\" datanodes=\"0\"}%\n" .
        "%DFDCONNECT{id=\"$p20ID\" type=\"proc\" level=\"3\" nolocales=\"0\" datanodes=\"1\"}%";
    my ($l19Anchor, $l19Url, $dummy1) = $self->getEverything(
        $locTag, $l19ID, $defaultID);
    my ($l20Anchor, $l20Url, $dummy2) = $self->getEverything(
        $locTag, $l20ID, $defaultID);
    my ($xportAnchor, $xportUrl, $dummy3) = $self->getEverything(
        $xportTag, $xportID, $defaultID);
    my ($p19Anchor, $p19Url, $p19GVN) = $self->getEverything(
        $procTag, $p19ID, $defaultID, $l19ID, $defaultID, "1");
    my ($p20Anchor, $p20Url, $p20GVN) = $self->getEverything(
        $procTag, $p20ID, $defaultID, $l20ID, $defaultID, "1");
    my ($d23Anchor, $d23Url, $d23GVN) = $self->getEverything(
        $dataTag, $d23ID, $defaultID, $l19ID, $defaultID, "1", $l20ID,
        $defaultID, undef, undef, undef, $xportID, $xportSubID,
        undef, $xportID, $xportSubID);
    my $d23_19GVN = $self->getGVNName(
        $d23ID, $defaultID, $l19ID, $defaultID, "1", $l19ID, $defaultID, undef,
        undef, $xportID, $xportSubID, undef, $xportID, $xportSubID);
    my $d23_20GVN = $self->getGVNName(
        $d23ID, $defaultID, $l20ID, $defaultID, "1", $l20ID, $defaultID, undef,
        undef, $xportID, $xportSubID, undef, $xportID, $xportSubID);
    my $graphnum = 1;
    my $expected =
        # DFDLOCALE
        getAnchor($l19Anchor) . "\n"
        # DFDLOCALE
        . getAnchor($l20Anchor) . "\n"
        # DFDTRANSPORT
        . getAnchor($xportAnchor) . "\n"
        # DFDPROC
        . getGraphTop($p19Anchor, "$procFN$p19ID", "$p19ID $procLB")
        . getProcDotDef($p19GVN, $procDefaults, $p19Url,
                        $p19Name, $p19ID, $p19SubID, $defaultID)
        . getDataDotDef($d23_19GVN, $dataDefaults, undef, $d23Name,
                        $d23ID, $defaultID, $defaultID, 0)
        . getEdge($p19GVN, $d23_19GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 1, "", 0,
                  $xportUrl)
        . getGraphBottom() . "\n"
        # DFDPROC
        . getGraphTop($p20Anchor, "$procFN$p20ID", "$p20ID $procLB")
        . getProcDotDef($p20GVN, $procDefaults, $p20Url,
                        $p20Name, $p20ID, $p20SubID, $defaultID)
        . getDataDotDef($d23_20GVN, $dataDefaults, undef, $d23Name,
                        $d23ID, $defaultID, $defaultID, 0)
        . getEdge($d23_20GVN, $p20GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 1, "", 0,
                  $xportUrl)
        . getGraphBottom() . "\n"
        # DFDCONNECT
        . getGraphTop(undef, sprintf("%s%s_%03d",$cnctFN,$p19ID,$graphnum++))
        . $self->getSubGraphTop($l19ID, $l19Name)
        . getProcDotDef($p19GVN, $procDefaults, $p19Url,
                        $p19Name, $p19ID, $p19SubID, $defaultID)
        . getSubGraphBottom()
        . $self->getSubGraphTop($l20ID, $l20Name)
        . getProcDotDef($p20GVN, $procDefaults, $p20Url,
                        $p20Name, $p20ID, $p20SubID, $defaultID)
        . getSubGraphBottom()
        . getEdge($p19GVN, $p20GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 1, "", 0,
                  $xportUrl)
        . getGraphBottom() . "\n"
        # DFDCONNECT
        . getGraphTop(undef, sprintf("%s%s_%03d",$cnctFN,$p19ID,$graphnum--))
        . $self->getSubGraphTop($l19ID, $l19Name)
        . getProcDotDef($p19GVN, $procDefaults, $p19Url,
                        $p19Name, $p19ID, $p19SubID, $defaultID)
        . getSubGraphBottom()
        . $self->getSubGraphTop($l20ID, $l20Name)
        . getProcDotDef($p20GVN, $procDefaults, $p20Url,
                        $p20Name, $p20ID, $p20SubID, $defaultID)
        . getSubGraphBottom()
        . getDataDotDef($d23GVN, $dataDefaults, undef, $d23Name,
                        $d23ID, $defaultID, $defaultID, 0)
        . getEdge($p19GVN, $d23GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 1, "", 0,
                  $xportUrl)
        . getEdge($d23GVN, $p20GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 1, "", 0,
                  $xportUrl)
        . getGraphBottom() . "\n"
        # DFDCONNECT
        . getGraphTop(undef, sprintf("%s%s_%03d",$cnctFN,$p20ID,$graphnum++))
        . $self->getSubGraphTop($l19ID, $l19Name)
        . getProcDotDef($p19GVN, $procDefaults, $p19Url,
                        $p19Name, $p19ID, $p19SubID, $defaultID)
        . getSubGraphBottom()
        . $self->getSubGraphTop($l20ID, $l20Name)
        . getProcDotDef($p20GVN, $procDefaults, $p20Url,
                        $p20Name, $p20ID, $p20SubID, $defaultID)
        . getSubGraphBottom()
        . getEdge($p19GVN, $p20GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 1, "", 0,
                  $xportUrl)
        . getGraphBottom() . "\n"
        # DFDCONNECT
        . getGraphTop(undef, sprintf("%s%s_%03d",$cnctFN,$p20ID,$graphnum--))
        . $self->getSubGraphTop($l19ID, $l19Name)
        . getProcDotDef($p19GVN, $procDefaults, $p19Url,
                        $p19Name, $p19ID, $p19SubID, $defaultID)
        . getSubGraphBottom()
        . $self->getSubGraphTop($l20ID, $l20Name)
        . getProcDotDef($p20GVN, $procDefaults, $p20Url,
                        $p20Name, $p20ID, $p20SubID, $defaultID)
        . getSubGraphBottom()
        . getDataDotDef($d23GVN, $dataDefaults, undef, $d23Name,
                        $d23ID, $defaultID, $defaultID, 0)
        . getEdge($p19GVN, $d23GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 1, "", 0,
                  $xportUrl)
        . getEdge($d23GVN, $p20GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 1, "", 0,
                  $xportUrl)
        . getGraphBottom()
        ;
    $self->runAndCheck($testText, $expected);
}


# Test DFDSEARCH for data types by group
# Defined entities:
#   Data: dfdtd11, dfdtd12, dfdtd00
sub test_DFDSEARCH_1 {
    my $self = shift;
    my $group = "dfdtg1";
    my ($d11ID, $d11Name, $x11ID, $d12ID, $d12Name, $x12ID,
        $d00ID, $d00Name, $x00ID) =
        ("dfdtd11", "dfdtd11", "dfdtx1", "dfdtd12", "dfdtd12", "dfdtx2",
         "dfdtd00", "dfdtd00", "dfdtx2");
    # each test case gets the database wiped out so we have to define
    # our data types again here.
    my $testText =
        # two that match
        "%DFDDATA{id=\"$d11ID\" xport=\"$x11ID\" groups=\"$group\"}%\n" .
        "%DFDDATA{id=\"$d12ID\" xport=\"$x12ID\" groups=\"$group\"}%\n" .
        # and one that should not match
        "%DFDDATA{id=\"$d00ID\" xport=\"$x00ID\"}%\n" .
        "%DFDSEARCH{\"/datacrossref/data[group/\@id='$group' and group/\@web='" . $self->{test_web} . "' and \@web='" . $self->{test_web} . "']\" header=\"| *ID* | *Name/Label* | *Group* | *Web* | *Topic* | *Page Link* |\" format=\"| ~\@id~ | ~\@name~ | ~group~ | ~\@web~ | ~\@topic~ | ~self::node()~ |\"}%";
    my ($d11Anchor, $d11Url, $d11GVN) = $self->getEverything(
        $dataTag, $d11ID, $defaultID, $defaultID, $defaultID, "1", $defaultID,
        $defaultID, undef, undef, undef, $x11ID, $defaultID,
        undef, $x11ID, $defaultID);
    my ($d12Anchor, $d12Url, $d12GVN) = $self->getEverything(
        $dataTag, $d12ID, $defaultID, $defaultID, $defaultID, "1", $defaultID,
        $defaultID, undef, undef, undef, $x12ID, $defaultID,
        undef, $x12ID, $defaultID);
    my ($d00Anchor, $d00Url, $d00GVN) = $self->getEverything(
        $dataTag, $d00ID, $defaultID, $defaultID, $defaultID, "1", $defaultID,
        $defaultID, undef, undef, undef, $x00ID, $defaultID,
        undef, $x00ID, $defaultID);
    my $expected = 
        getGraphTop($d11Anchor, "$dataFN$d11ID", "$d11ID $dataLB")
        . getDataDotDef($d11GVN, $dataDefaults, $d11Url, $d11Name, $d11ID,
                        $defaultID, $group, 1)
        . getGraphBottom() . "\n"
        . getGraphTop($d12Anchor, "$dataFN$d12ID", "$d12ID $dataLB")
        . getDataDotDef($d12GVN, $dataDefaults, $d12Url, $d12Name, $d12ID,
                        $defaultID, $group, 1)
        . getGraphBottom() . "\n"
        . getGraphTop($d00Anchor, "$dataFN$d00ID", "$d00ID $dataLB")
        . getDataDotDef($d00GVN, $dataDefaults, $d00Url, $d00Name, $d00ID,
                        $defaultID, $defaultID, 1)
        . getGraphBottom() . "\n"
        . "| *ID* | *Name/Label* | *Group* | *Web* | *Topic* | *Page Link* |\n"
        . "| $d11ID | $d11Name | $group | " . $self->{test_web} . " | " . $self->{test_topic} . " | [[" . $d11Url . "][$d11Name]] |\n"
        . "| $d12ID | $d12Name | $group | " . $self->{test_web} . " | " . $self->{test_topic} . " | [[" . $d12Url . "][$d12Name]] |\n";
    $self->runAndCheck($testText, $expected);
}


# Test DFDSEARCH to get a list of locales for a process
# Defined entities:
#   Process: dfdtp21
sub test_DFDSEARCH_2 {
    my $self = shift;
    my $procID = "dfdtp21";
    my $procName = $procID;
    my $subID = $defaultID;
    my ($l1ID, $l2ID, $l3ID) = ("dfdtl9", "dfdtl10", "dfdtl11");
    my $localeSubID = $defaultID;
    my $instNum = "1";
    my $testText = "%DFDPROC{id=\"$procID\" locales=\"$l1ID, $l2ID, $l3ID\"}%\n"
        . "%DFDSEARCH{\"/proccrossref/proc[\@id='dfdtp21']/locale\" format=\"   * ~self::node()~\"}%";
    # $l2ID is first alphabetically
    my ($anchorName, $url, $gvnName) = $self->getEverything(
        $procTag, $procID, $subID, $l2ID, $localeSubID, $instNum);
    my $expected =
        getGraphTop($anchorName, "$procFN$procID", "$procID $procLB")
        . getProcDotDef($gvnName, $procDefaults, $url, $procName,
                        $procID, $subID, $defaultID)
        . getGraphBottom() . "\n"
        # Should I just sort and join?
        . "   * $l2ID\n"
        . "   * $l3ID\n"
        . "   * $l1ID\n";
    $self->runAndCheck($testText, $expected);
}


# Test DFDCONNECT to get text output of a list of connected processes
# (downstream then upstream).
# Defined entities:
#   Process: dfdtp22, dfdtp23
# Undefined entities:
#   Data:    dfdtd24, dfdtd25, dfdtd26
sub test_DFDCONNECT_7 {
    my $self = shift;
    my ($p22ID, $p22Name, $p22SubID, $p22Inst, $p22GroupID) =
        ("dfdtp22", "dfdtp22", $defaultID, "1", $defaultID);
    my ($p23ID, $p23Name, $p23SubID, $p23Inst, $p23GroupID) =
        ("dfdtp23", "dfdtp23", $defaultID, "1", $defaultID);
    my ($d24ID, $d24Name, $d24SubID, $d24GroupID) =
        ("dfdtd24", "dfdtd24", $defaultID, $defaultID);
    my ($d25ID, $d25Name, $d25SubID, $d25GroupID) =
        ("dfdtd25", "dfdtd25", $defaultID, $defaultID);
    my ($d26ID, $d26Name, $d26SubID, $d26GroupID) =
        ("dfdtd26", "dfdtd26", $defaultID, $defaultID);
    my ($l22ID, $l23ID) = ($defaultID, $defaultID);
    my ($xportID, $xportSubID, $xportGroupID, $xportName) =
        ($defaultID, $defaultID, $defaultID, $defaultID);
    my $testText =
        "%DFDPROC{id=\"$p22ID\" outputs=\"$d24ID, $d25ID\"}%\n" .
        "%DFDPROC{id=\"$p23ID\" inputs=\"$d26ID, $d25ID\"}%\n" .
        "%DFDCONNECT{id=\"$p22ID\" type=\"proc\" level=\"1\"}%\n" .
        "%DFDCONNECT{id=\"$p22ID\" type=\"proc\" header=\"| *Name* | *ID* | *App Diagram Link* | *Inputs* | *In/Outputs* |\" format=\"| ~\@name~ | ~\@id~ | ~self::node()~ | ~matchedinput~ | ~matchedinout~ |\" printself=\"0\" dir=\"1\" alldata=\"0\" level=\"1\"}%\n" .
        "%DFDCONNECT{id=\"dfdtp23\" type=\"proc\" header=\"| *Name* | *ID* | *App Diagram Link* | *Outputs* | *In/Outputs* |\" format=\"| ~\@name~ | ~\@id~ | ~self::node()~ | ~matchedoutput~ | ~matchedinout~ |\" printself=\"0\" dir=\"2\" alldata=\"0\" level=\"1\"}%";
    my ($p22Anchor, $p22Url, $p22GVN) = $self->getEverything(
        $procTag, $p22ID, $defaultID, $l22ID, $defaultID, "1");
    my ($p23Anchor, $p23Url, $p23GVN) = $self->getEverything(
        $procTag, $p23ID, $defaultID, $l23ID, $defaultID, "1");
    my ($d24Anchor, $d24Url, $d24GVN) = $self->getEverything(
        $dataTag, $d24ID, $defaultID, $l22ID, $defaultID, "1", $l22ID,
        $defaultID, undef, undef, undef, $xportID, $xportSubID,
        undef, $xportID, $xportSubID);
    my ($d25Anchor, $d25Url, $d25GVN) = $self->getEverything(
        $dataTag, $d25ID, $defaultID, $l22ID, $defaultID, "1", $l23ID,
        $defaultID, undef, undef, undef, $xportID, $xportSubID,
        undef, $xportID, $xportSubID);
    my ($d26Anchor, $d26Url, $d26GVN) = $self->getEverything(
        $dataTag, $d26ID, $defaultID, $l22ID, $defaultID, "1", $l22ID,
        $defaultID, undef, undef, undef, $xportID, $xportSubID,
        undef, $xportID, $xportSubID);
    my $d25_22GVN = $self->getGVNName(
        $d25ID, $defaultID, $l22ID, $defaultID, "1", $l22ID, $defaultID, undef,
        undef, $xportID, $xportSubID, undef, $xportID, $xportSubID);
    my $d25_23GVN = $self->getGVNName(
        $d25ID, $defaultID, $l23ID, $defaultID, "1", $l23ID, $defaultID, undef,
        undef, $xportID, $xportSubID, undef, $xportID, $xportSubID);
    my $expected =
        # DFDPROC
        getGraphTop($p22Anchor, "$procFN$p22ID", "$p22ID $procLB")
        . getProcDotDef($p22GVN, $procDefaults, $p22Url,
                        $p22Name, $p22ID, $p22SubID, $defaultID)
        . getDataDotDef($d24GVN, $dataDefaults, undef, $d24Name,
                        $d24ID, $defaultID, $defaultID, 0)
        . getDataDotDef($d25_22GVN, $dataDefaults, undef, $d25Name,
                        $d25ID, $defaultID, $defaultID, 0)
        . getEdge($p22GVN, $d24GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 0)
        . getEdge($p22GVN, $d25_22GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 0)
        . getGraphBottom() . "\n"
        # DFDPROC
        . getGraphTop($p23Anchor, "$procFN$p23ID", "$p23ID $procLB")
        . getProcDotDef($p23GVN, $procDefaults, $p23Url,
                        $p23Name, $p23ID, $p23SubID, $defaultID)
        . getDataDotDef($d25_23GVN, $dataDefaults, undef, $d25Name,
                        $d25ID, $defaultID, $defaultID, 0)
        . getDataDotDef($d26GVN, $dataDefaults, undef, $d26Name,
                        $d26ID, $defaultID, $defaultID, 0)
        . getEdge($d25_23GVN, $p23GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 0)
        . getEdge($d26GVN, $p23GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 0)
        . getGraphBottom() . "\n"
        # DFDCONNECT
        . getGraphTop(undef, sprintf("%s%s_%03d",$cnctFN,$p22ID,1))
        . getProcDotDef($p22GVN, $procDefaults, $p22Url,
                        $p22Name, $p22ID, $p22SubID, $defaultID)
        . getProcDotDef($p23GVN, $procDefaults, $p23Url,
                        $p23Name, $p23ID, $p23SubID, $defaultID)
        . getDataDotDef($d25GVN, $dataDefaults, undef, $d25Name,
                        $d25ID, $defaultID, $defaultID, 0)
        . getEdge($p22GVN, $d25GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 0)
        . getEdge($d25GVN, $p23GVN, "Transport", $xportName,
                  $xportID, $xportSubID, $xportGroupID, 0)
        . getGraphBottom() . "\n"
        . "| *Name* | *ID* | *App Diagram Link* | *Inputs* | *In/Outputs* |\n"
        . "| $p23Name | $p23ID | [[$p23Url][$p23Name]] | $d25ID |  |\n\n"
        . "| *Name* | *ID* | *App Diagram Link* | *Outputs* | *In/Outputs* |\n"
        . "| $p22Name | $p22ID | [[$p22Url][$p22Name]] | $d25ID |  |\n"
        ;
    $self->runAndCheck($testText, $expected);
}


# Test DFDSEARCH searching for data types used by an application where
# a specific transport is utilized.
# Defined entities:
#   Transport: dfdtx8, dfdtx9
#   Data:      dfdtd27, dfdtd28, dfdtd29
#   Process:   dfdtp24
sub test_DFDSEARCH_3 {
    my $self = shift;
    my ($group, $loc, $locSub) = ("dfdtg2", $defaultID, $defaultID);
    my ($x8, $x8Name, $x9, $x9Name) = ("dfdtx8", "TX8", "dfdtx9", "TX9");
    my ($x8Sub, $x8Group, $x9Sub, $x9Group) =
        ($defaultID, $defaultID, $defaultID, $defaultID);
    my ($d27, $d27Name, $d27Sub, $d27Group) =
        ("dfdtd27", "dfdtd27", $defaultID, $group);
    my ($d28, $d28Name, $d28Sub, $d28Group) =
        ("dfdtd28", "dfdtd28", $defaultID, $group);
    my ($d29, $d29Name, $d29Sub, $d29Group) =
        ("dfdtd29", "dfdtd29", $defaultID, $group);
    my ($p24, $p24Name, $p24Sub, $p24Inst, $p24Group) =
        ("dfdtp24", "dfdtp24", $defaultID, "1", $defaultID);
    my ($x8Anchor, $x8Url, $dummy1) = $self->getEverything(
        $xportTag, $x8, $x8Sub);
    my ($x9Anchor, $x9Url, $dummy2) = $self->getEverything(
        $xportTag, $x9, $x9Sub);
    my ($d27Anchor, $d27Url, $d27GVN) = $self->getEverything(
        $dataTag, $d27, $d27Sub, $loc, $locSub, "1", $loc, $locSub, undef,
        undef, undef, $x8, $x8Sub, undef, $x8, $x8Sub);
    my ($d28Anchor, $d28Url, $d28GVN) = $self->getEverything(
        $dataTag, $d28, $d28Sub, $loc, $locSub, "1", $loc, $locSub, undef,
        undef, undef, $x9, $x9Sub, undef, $x9, $x9Sub);
    my ($d29Anchor, $d29Url, $d29GVN) = $self->getEverything(
        $dataTag, $d29, $d29Sub, $loc, $locSub, "1", $loc, $locSub, undef,
        undef, undef, $x8, $x8Sub, undef, $x8, $x8Sub);
    my ($p24Anchor, $p24Url, $p24GVN) = $self->getEverything(
        $procTag, $p24, $p24Sub, $loc, $locSub, $p24Inst);
    my $testText =
        "%DFDTRANSPORT{id=\"$x8\" name=\"$x8Name\"}%\n" .
        "%DFDTRANSPORT{id=\"$x9\" name=\"$x9Name\"}%\n" .
        "%DFDDATA{id=\"$d27\" xport=\"$x8\" groups=\"$d27Group\"}%\n" .
        "%DFDDATA{id=\"$d28\" xport=\"$x9\" groups=\"$d28Group\"}%\n" .
        "%DFDDATA{id=\"$d29\" xport=\"$x8\" groups=\"$d29Group\"}%\n" .
        "%DFDPROC{id=\"$p24\" inputs=\"$d27, $d28\" outputs=\"$d29\"}%\n" .
        "%DFDSEARCH{\"/proccrossref/proc[\@id='$p24']/*[(name()='input' or name()='output' or name()='inout') and xport/\@id='$x8' and xport/\@web='" . $self->{test_web} . "']\" format=\"   * ~self::node()~\"}%";
    my $expected =
        # DFDTRANSPORT
        getAnchor($x8Anchor) . "\n"
        # DFDTRANSPORT
        . getAnchor($x9Anchor) . "\n"
        # DFDDATA
        . getGraphTop($d27Anchor, "$dataFN$d27", "$d27 $dataLB")
        . getProcDotDef($p24GVN, $procDefaults, $p24Url, $p24Name, $p24,
                        $p24Sub, $p24Group)
        . getDataDotDef($d27GVN, $dataDefaults, $d27Url, $d27Name, $d27,
                        $d27Sub, $d27Group, 1)
        . getEdge($d27GVN, $p24GVN, "Transport", $x8Name, $x8, $x8Sub, $x8Group,
                  1, "", 0, $x8Url)
        . getGraphBottom() . "\n"
        # DFDDATA
        . getGraphTop($d28Anchor, "$dataFN$d28", "$d28 $dataLB")
        . getProcDotDef($p24GVN, $procDefaults, $p24Url, $p24Name, $p24,
                        $p24Sub, $p24Group)
        . getDataDotDef($d28GVN, $dataDefaults, $d28Url, $d28Name, $d28,
                        $d28Sub, $d28Group, 1)
        . getEdge($d28GVN, $p24GVN, "Transport", $x9Name, $x9, $x9Sub, $x9Group,
                  1, "", 0, $x9Url)
        . getGraphBottom() . "\n"
        # DFDDATA
        . getGraphTop($d29Anchor, "$dataFN$d29", "$d29 $dataLB")
        . getProcDotDef($p24GVN, $procDefaults, $p24Url, $p24Name, $p24,
                        $p24Sub, $p24Group)
        . getDataDotDef($d29GVN, $dataDefaults, $d29Url, $d29Name, $d29,
                        $d29Sub, $d29Group, 1)
        . getEdge($p24GVN, $d29GVN, "Transport", $x8Name, $x8, $x8Sub, $x8Group,
                  1, "", 0, $x8Url)
        . getGraphBottom() . "\n"
        # DFDPROC
        . getGraphTop($p24Anchor, "$procFN$p24", "$p24 $procLB")
        . getProcDotDef($p24GVN, $procDefaults, $p24Url, $p24Name, $p24,
                        $p24Sub, $p24Group)
        . getDataDotDef($d27GVN, $dataDefaults, $d27Url, $d27Name, $d27,
                        $d27Sub, $d27Group, 1)
        . getDataDotDef($d28GVN, $dataDefaults, $d28Url, $d28Name, $d28,
                        $d28Sub, $d28Group, 1)
        . getDataDotDef($d29GVN, $dataDefaults, $d29Url, $d29Name, $d29,
                        $d29Sub, $d29Group, 1)
        . getEdge($p24GVN, $d29GVN, "Transport", $x8Name, $x8, $x8Sub, $x8Group,
                  1, "", 0, $x8Url)
        . getEdge($d27GVN, $p24GVN, "Transport", $x8Name, $x8, $x8Sub, $x8Group,
                  1, "", 0, $x8Url)
        . getEdge($d28GVN, $p24GVN, "Transport", $x9Name, $x9, $x9Sub, $x9Group,
                  1, "", 0, $x9Url)
        . getGraphBottom() . "\n"
        . "   * [[$d27Url][$d27Name]]\n"
        . "   * [[$d29Url][$d29Name]]\n"
        ;
    $self->runAndCheck($testText, $expected);
}


# Test the generation of errors when an object is multiply
# defined. Different WEB, success is expected.
# Defined entities:
#   Data: dfdtd35
sub test_error_redef_1 {
    my $self = shift;
    my $dataID = "dfdtd35";
    my $dataName = $dataID;
    my ($subID, $group, $locID, $locSub, $inst) =
        ($defaultID, $defaultID, $defaultID, $defaultID, 1);
    my $testText = "%DFDDATA{id=\"$dataID\"}%";
    my ($anchor1, $url1, $gvn1) = $self->getEverything(
        $dataTag, $dataID, $subID, $locID, $locSub, $inst, $locID, $locSub,
        undef, undef, undef, $defaultID, $defaultID,
        undef, $defaultID, $defaultID);
    my ($anchor2, $url2, $gvn2) = $self->getEverything(
        $dataTag, $dataID, $subID, $locID, $locSub, $inst, $locID, $locSub,
        $self->{'secondweb'}, $self->{'secondtopic'},
        $self->{'secondweb'}, $defaultID, $defaultID,
        $self->{'secondweb'}, $defaultID, $defaultID);
    # expected on supplied test web
    my $expected1 = 
        getGraphTop($anchor1, "$dataFN$dataID", "$dataID $dataLB")
        . getDataDotDef($gvn1, $dataDefaults, $url1, $dataName, $dataID, $subID,
                        $group, 1)
        . getGraphBottom();
    # expected on created test web
    my $expected2 =
        getGraphTop($anchor2, "$dataFN$dataID", "$dataID $dataLB")
        . getDataDotDef($gvn2, $dataDefaults, $url2, $dataName, $dataID, $subID,
                        $group, 1)
        . getGraphBottom();

    $self->runAndCheck($testText, $expected1);
    $self->runAndCheck(
        $testText, $expected2, $self->{'secondweb'}, $self->{'secondtopic'});
}


# Test the generation of errors when an object is multiply
# defined. SAME WEB, FAILURE is expected.
# Defined entities:
#   Data: dfdtd36
sub test_error_redef_2 {
    my $self = shift;
    my $dataID = "dfdtd36";
    my $dataName = $dataID;
    my ($subID, $group, $locID, $locSub, $inst) =
        ($defaultID, $defaultID, $defaultID, $defaultID, 1);
    my $testText = "%DFDDATA{id=\"$dataID\"}%";
    my ($anchor1, $url1, $gvn1) = $self->getEverything(
        $dataTag, $dataID, $subID, $locID, $locSub, $inst, $locID, $locSub,
        undef, undef, undef, $defaultID, $defaultID,
        undef, $defaultID, $defaultID);
    # expected on supplied test web
    my $expected1 = 
        getGraphTop($anchor1, "$dataFN$dataID", "$dataID $dataLB")
        . getDataDotDef($gvn1, $dataDefaults, $url1, $dataName, $dataID, $subID,
                        $group, 1)
        . getGraphBottom();
    # expected on supplied test web, secondary topic
    # SMELL this is not the most maintainable with hard-coded text strings
    my $expected2 = Foswiki::Plugins::DataFlowDiaPlugin::Util::macroError(
        "DATA Entity \"<nop>$dataID\" is already defined here: [[$url1][$dataID]].  Please remove one of the definitions.");

    $self->runAndCheck($testText, $expected1);
    $self->runAndCheck(
        $testText, $expected2, $self->{test_web}, $self->{'secondtopic'});
}

1;
