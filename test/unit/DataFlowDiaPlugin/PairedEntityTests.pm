# $Id: //foswiki-dfd/rel2_0_1/test/unit/DataFlowDiaPlugin/PairedEntityTests.pm#1 $

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

package PairedEntityTests;

use FoswikiFnTestCase;
our @ISA = qw( FoswikiFnTestCase );

use strict;
use warnings;
use Foswiki;
use CGI;

use Foswiki::Plugins::DataFlowDiaPlugin::DocManager;
use Foswiki::Plugins::DataFlowDiaPlugin::DataTransport;

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
    #$Foswiki::Plugins::DataFlowDiaPlugin::debugUnitTests = 1;
}

sub tear_down {
    my $self = shift;
    $self->SUPER::tear_down();
}

sub test_DataTransport {
    my $self = shift;
    my $entityID = "dutuh";
    my $dataFullMacroSpec  = $self->{test_web} . ".$entityID#DEFAULT";
    my $xportFullMacroSpec = $self->{test_web} . ".DEFAULT#DEFAULT";
    my $dtFullMacroSpec = $dataFullMacroSpec . "##" . $xportFullMacroSpec;

    # $Foswiki::Plugins::DataFlowDiaPlugin::debugUnitTests = 1;
    my $docManager = Foswiki::Plugins::DataFlowDiaPlugin::DocManager->new();
    $docManager->loadDocs();

    my $ref_dt1xml = "<test id=\"$entityID\" web=\"" . $self->{test_web} .
        "\"/>";
    my $ref_dt1xmlInh = "<test id=\"$entityID\" web=\"" . $self->{test_web} .
        "\" defined=\"0\" deprecated=\"0\" nodename=\"test\"/>";

    my $dt1 = Foswiki::Plugins::DataFlowDiaPlugin::DataTransport->new(
        $self->{test_web},
        $entityID,
        undef,
        $Foswiki::Plugins::DataFlowDiaPlugin::DocManager::dirFwd,
        $docManager);
    $self->common_checks_DataTransport($dt1);
    $self->assert_equals(
        $dt1->dir(), $Foswiki::Plugins::DataFlowDiaPlugin::DocManager::dirFwd);
    $self->assert_str_equals($dataFullMacroSpec, $dt1->dataMacroSpec());
    $self->assert_str_equals($xportFullMacroSpec, $dt1->xportMacroSpec());
    $self->assert_str_equals($dtFullMacroSpec, $dt1->macroSpec());
    $self->assert(
        !$dt1->isReverse(), "DataTransport 1 is incorrectly marked reverse");
    my $dt1xmlElem = $dt1->toXML("test", 0);
    my $dt1xmlElemInh = $dt1->toXML("test", 1);
    $self->assert_str_equals($ref_dt1xml, $dt1xmlElem->toString(0));
    $self->assert_str_equals($ref_dt1xmlInh, $dt1xmlElemInh->toString(0));

    undef $dt1;
    undef $docManager;
}

sub common_checks_DataTransport {
    my ($self,
        $dt) = @_;
    $self->assert_not_null(
        $dt->dataEntity(), "DataTransport DataType entity is undefined");
    $self->assert_not_null(
        $dt->xportEntity(), "DataTransport Transport entity is undefined");
    $self->assert(
        $dt->dataEntity()->isa(
            "Foswiki::Plugins::DataFlowDiaPlugin::DataType"),
        "DataTransport data entity is not the expected type");
    $self->assert(
        $dt->xportEntity()->isa(
            "Foswiki::Plugins::DataFlowDiaPlugin::Transport"),
        "DataTransport transport entity is not the expected type");
    $self->assert(
        $dt->dataEntitySpec()->isa(
            "Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec"),
        "DataTransport data entity spec is not the expected type");
    $self->assert(
        $dt->xportEntitySpec()->isa(
            "Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec"),
        "DataTransport transport entity spec is not the expected type");
}

1;
