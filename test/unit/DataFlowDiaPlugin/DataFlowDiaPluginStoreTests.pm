# $Id: //foswiki-dfd/rel2_0_1/test/unit/DataFlowDiaPlugin/DataFlowDiaPluginRenderTests.pm#1 $

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

package DataFlowDiaPluginStoreTests;

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
use Foswiki::Plugins::DataFlowDiaPlugin::PackageConsts qw(:xml :etypes);

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

    #$Foswiki::Plugins::DataFlowDiaPlugin::debugUnitTests = 1;
}


sub tear_down {
    my $self = shift;
    # Remove the store files as we don't want anything carrying
    # over between tests.
    my $workArea = Foswiki::Func::getWorkArea("DataFlowDiaPlugin");
    my $path;
    foreach my $et (@ENTITY_PROC_ORDER) {
        $path = File::Spec->catfile($workArea, $et . ".xml");
        unlink $path;
    }
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
        $entityType,
        $testText,
        $expected,
        $web,
        $topic) = @_;
    use File::Copy;
    use File::Spec;
    $self->{'success'} = 0;
    Foswiki::Plugins::DataFlowDiaPlugin::commonTagsHandler(
        $testText, $topic || $self->{test_topic}, $web || $self->{test_web}, 0,
        undef);
    # WARNING this might not be ideal.  There currently is no direct
    # access to DocManager::saveDocs from DataFlowDiaPlugin, so we use
    # finishPlugin() instead.  As a result, it is possible that some
    # time in the future, finishPlugin() will do something that will
    # break this test, though if that happens hopefully the test will
    # fail, this message will be found, and an appropriate action can
    # be taken.
    Foswiki::Plugins::DataFlowDiaPlugin::finishPlugin();
    $self->saveData("expected.txt", $expected);
    my $workArea = Foswiki::Func::getWorkArea("DataFlowDiaPlugin");
    my $path = File::Spec->catfile($workArea, $entityType . ".xml");
    my $newPath = File::Spec->catfile($self->{'tempdir'}, "got.txt");
    copy($path, $newPath);
    # read the XML store into a string
    my $contents = "";
    open(my $in, "<", $path) or die("Unable to open $path: $!\n");
    local $/ = undef;
    $contents = <$in>;
    close($in);
    $self->assert_str_equals($expected, $contents);
    $self->{'success'} = 1;
}


# Test to make sure that an entity definition is stored in .xml and
# removed from the .xml when it is removed from the topic.
# Defined entities:
#   Process: dfdtp1
sub test_EntityRemoval {
    my $self = shift;
    my $procID = "dfdtp1";
    my $procName = $procID;
    my $testText = "%DFDPROC{id=\"$procID\"}%";
    my $expected = "";

    Foswiki::Plugins::DataFlowDiaPlugin::initPlugin(
        $self->{test_web},  $self->{test_topic},
        $self->{test_user}, $Foswiki::cfg{SystemWebName}
        );

    # add a definition and check the XML store
    my $xmlDoc = XML::LibXML::Document->new("1.0", "UTF-8");
    my $rootElem = XML::LibXML::Element->new($ROOTNAME_PROC);
    $xmlDoc->setDocumentElement($rootElem);
    my $xmlElem = XML::LibXML::Element->new($NODENAME_PROC);
    $xmlElem->setAttribute("id", $procID);
    $xmlElem->setAttribute("name", $procName);
    $xmlElem->setAttribute("web", $self->{test_web});
    $xmlElem->setAttribute("topic", $self->{test_topic});
    $xmlElem->setAttribute("deprecated", "0");
    $rootElem->addChild($xmlElem);
    $expected = $xmlDoc->toString(2);
    $self->runAndCheck($ENTITYTYPE_PROC, $testText, $expected);

    # re-initialize to load the XML
    Foswiki::Plugins::DataFlowDiaPlugin::initPlugin(
        $self->{test_web},  $self->{test_topic},
        $self->{test_user}, $Foswiki::cfg{SystemWebName}
        );

    # remove the definition and check again
    $testText = "";
    $xmlDoc = XML::LibXML::Document->new("1.0", "UTF-8");
    $rootElem = XML::LibXML::Element->new($ROOTNAME_PROC);
    $xmlDoc->setDocumentElement($rootElem);
    $expected = $xmlDoc->toString(2);
    $self->runAndCheck($ENTITYTYPE_PROC, $testText, $expected);
}


# Test to verify proper storage of transport specs.
sub test_DataTransport_1 {
    my $self = shift;
    my $procID = "dfdtp1";
    my $procName = $procID;
    my $dataID = "dfdtd1";
    my $xportID1 = "dfdtx1";
    my $xportID2 = "dfdtx2";
    my $testText = "%DFDPROC{id=\"$procID\" inputs=\"$dataID###$xportID1\" outputs=\"$dataID###$xportID2\"}%";
    my $expected = "";

    Foswiki::Plugins::DataFlowDiaPlugin::initPlugin(
        $self->{test_web},  $self->{test_topic},
        $self->{test_user}, $Foswiki::cfg{SystemWebName}
        );
    # add a definition and check the XML store
    my $xmlDoc = XML::LibXML::Document->new("1.0", "UTF-8");
    my $rootElem = XML::LibXML::Element->new($ROOTNAME_PROC);
    $xmlDoc->setDocumentElement($rootElem);
    my $xportElem1 = XML::LibXML::Element->new($NODENAME_XPORT);
    $xportElem1->setAttribute("id", $xportID1);
    $xportElem1->setAttribute("web", $self->{test_web});
    my $xportElem2 = XML::LibXML::Element->new($NODENAME_XPORT);
    $xportElem2->setAttribute("id", $xportID2);
    $xportElem2->setAttribute("web", $self->{test_web});
    my $inpDataElem = XML::LibXML::Element->new("input");
    $inpDataElem->setAttribute("id", $dataID);
    $inpDataElem->setAttribute("web", $self->{test_web});
    $inpDataElem->addChild($xportElem1);
    my $outDataElem = XML::LibXML::Element->new("output");
    $outDataElem->setAttribute("id", $dataID);
    $outDataElem->setAttribute("web", $self->{test_web});
    $outDataElem->addChild($xportElem2);
    my $procElem = XML::LibXML::Element->new($NODENAME_PROC);
    $procElem->setAttribute("id", $procID);
    $procElem->setAttribute("name", $procName);
    $procElem->setAttribute("web", $self->{test_web});
    $procElem->setAttribute("topic", $self->{test_topic});
    $procElem->setAttribute("deprecated", "0");
    $procElem->addChild($inpDataElem);
    $procElem->addChild($outDataElem);
    $rootElem->addChild($procElem);
    $expected = $xmlDoc->toString(2);
    $self->runAndCheck($ENTITYTYPE_PROC, $testText, $expected);
}


# Test to verify proper storage of transport specs.
# DATA and PROC definitions on separate topics.  DATA has associated
# transport.  PROC overrides transport on input, uses default on
# output.
sub test_DataTransport_2 {
    my $self = shift;
    my $procID = "dfdtp1";
    my $procName = $procID;
    my $dataID = "dfdtd1";
    my $dataName = $dataID;
    my $xportID1 = "dfdtx1";
    my $xportID2 = "dfdtx2";
    my $testText1 = "%DFDDATA{id=\"$dataID\" xport=\"$xportID2\"}%";
    my $testText2 = "%DFDPROC{id=\"$procID\" inputs=\"$dataID###$xportID1\" outputs=\"$dataID\"}%";
    my $expected = "";

    my $secondTopic = $self->{test_topic} . "Second";
    Foswiki::Plugins::DataFlowDiaPlugin::initPlugin(
        $self->{test_web},  $secondTopic,
        $self->{test_user}, $Foswiki::cfg{SystemWebName}
        );
    # add a definition and check the XML store
    my $xmlDoc = XML::LibXML::Document->new("1.0", "UTF-8");
    my $rootElem = XML::LibXML::Element->new($ROOTNAME_DATA);
    $xmlDoc->setDocumentElement($rootElem);
    my $dataElem = XML::LibXML::Element->new($NODENAME_DATA);
    $dataElem->setAttribute("id", $dataID);
    $dataElem->setAttribute("name", $dataName);
    $dataElem->setAttribute("web", $self->{test_web});
    $dataElem->setAttribute("topic", $secondTopic);
    $dataElem->setAttribute("deprecated", "0");
    my $xportElem2 = XML::LibXML::Element->new($NODENAME_XPORT);
    $xportElem2->setAttribute("id", $xportID2);
    $xportElem2->setAttribute("web", $self->{test_web});
    $dataElem->addChild($xportElem2);
    $rootElem->addChild($dataElem);
    $expected = $xmlDoc->toString(2);
    $self->runAndCheck(
        $ENTITYTYPE_DATA, $testText1, $expected, undef, $secondTopic);
    undef $xmlDoc;
    undef $rootElem;
    undef $dataElem;
    undef $xportElem2;

    Foswiki::Plugins::DataFlowDiaPlugin::initPlugin(
        $self->{test_web},  $self->{test_topic},
        $self->{test_user}, $Foswiki::cfg{SystemWebName}
        );
    # add a definition and check the XML store
    $xmlDoc = XML::LibXML::Document->new("1.0", "UTF-8");
    $rootElem = XML::LibXML::Element->new($ROOTNAME_PROC);
    $xmlDoc->setDocumentElement($rootElem);
    my $xportElem1 = XML::LibXML::Element->new($NODENAME_XPORT);
    $xportElem1->setAttribute("id", $xportID1);
    $xportElem1->setAttribute("web", $self->{test_web});
    my $inpDataElem = XML::LibXML::Element->new("input");
    $inpDataElem->setAttribute("id", $dataID);
    $inpDataElem->setAttribute("web", $self->{test_web});
    $inpDataElem->addChild($xportElem1);
    my $outDataElem = XML::LibXML::Element->new("output");
    $outDataElem->setAttribute("id", $dataID);
    $outDataElem->setAttribute("web", $self->{test_web});
    my $procElem = XML::LibXML::Element->new($NODENAME_PROC);
    $procElem->setAttribute("id", $procID);
    $procElem->setAttribute("name", $procName);
    $procElem->setAttribute("web", $self->{test_web});
    $procElem->setAttribute("topic", $self->{test_topic});
    $procElem->setAttribute("deprecated", "0");
    $procElem->addChild($inpDataElem);
    $procElem->addChild($outDataElem);
    $rootElem->addChild($procElem);
    $expected = $xmlDoc->toString(2);
    $self->runAndCheck($ENTITYTYPE_PROC, $testText2, $expected);
}


# Test to verify proper storage of transport specs.
# PROC with undefined data type, undefined transport with sub-id
sub test_DataTransport_3 {
    my $self = shift;
    my $procID = "dfdtp1";
    my $procName = $procID;
    my $dataID = "dfdtd1";
    my $xportID = "dfdtx1";
    my $xportSub = "xsub";
    my $testText = "%DFDPROC{id=\"$procID\" inputs=\"$dataID###$xportID#$xportSub\"}%";
    my $expected = "";

    Foswiki::Plugins::DataFlowDiaPlugin::initPlugin(
        $self->{test_web},  $self->{test_topic},
        $self->{test_user}, $Foswiki::cfg{SystemWebName}
        );
    # add a definition and check the XML store
    my $xmlDoc = XML::LibXML::Document->new("1.0", "UTF-8");
    my $rootElem = XML::LibXML::Element->new($ROOTNAME_PROC);
    $xmlDoc->setDocumentElement($rootElem);
    my $xportElem = XML::LibXML::Element->new($NODENAME_XPORT);
    $xportElem->setAttribute("id", $xportID);
    $xportElem->setAttribute("subid", $xportSub);
    $xportElem->setAttribute("web", $self->{test_web});
    my $dataElem = XML::LibXML::Element->new("input");
    $dataElem->setAttribute("id", $dataID);
    $dataElem->setAttribute("web", $self->{test_web});
    $dataElem->addChild($xportElem);
    my $procElem = XML::LibXML::Element->new($NODENAME_PROC);
    $procElem->setAttribute("id", $procID);
    $procElem->setAttribute("name", $procName);
    $procElem->setAttribute("web", $self->{test_web});
    $procElem->setAttribute("topic", $self->{test_topic});
    $procElem->setAttribute("deprecated", "0");
    $procElem->addChild($dataElem);
    $rootElem->addChild($procElem);
    $expected = $xmlDoc->toString(2);
    $self->runAndCheck($ENTITYTYPE_PROC, $testText, $expected);
}


1;
