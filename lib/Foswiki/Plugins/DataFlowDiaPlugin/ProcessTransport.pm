# $Id: //foswiki-dfd/rel2_0_1/lib/Foswiki/Plugins/DataFlowDiaPlugin/ProcessTransport.pm#1 $

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

---+ package Foswiki::Plugins::DataFlowDiaPlugin::ProcessTransport

Class for storing information about associated process and transport
pairs.  Used by Process, which stores instances of this class in
DataType objects.

=cut

package Foswiki::Plugins::DataFlowDiaPlugin::ProcessTransport;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec;
use Foswiki::Plugins::DataFlowDiaPlugin::Util qw(:error :debug);


################################
# CONSTRUCTORS
################################

# Create a new ProcessTransport object.
#
# @param[in] $class The name of the class being instantiated.
# @param[in] $processEntity The Process Entity object reference for
#   this reverse cross-reference, i.e. the Process using the
#   DataType/Transport forming this reverse cross-reference.
# @param[in] $dataTransport The DataType/Transport cross-reference
#   that will store this reverse cross-reference.
#
# @return a reference to a ProcessTransport object.
sub new {
    my ($class,
        $processEntity,
        $dataTransport) = @_;

    my $processMacroSpec  = $processEntity->getMacroSpec();
    my $xportEntity       = $dataTransport->xportEntity();
    my $xportMacroSpec    = $dataTransport->xportMacroSpec();
    my $inherited         = $dataTransport->isXportInherited();

    my $self = {
        'process'          => $processEntity,
        'processMacroSpec' => $processMacroSpec,
        'xport'            => $xportEntity,
        'xportMacroSpec'   => $xportMacroSpec,
        'xportInherited'   => $inherited,
        'dataTransport'    => $dataTransport
    };

    return bless ($self, $class);
}


################################
# XML PROCESSING
################################


# Add child nodes to XML::LibXML::Element for I/O cross-references.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::ProcessTransport
#   object reference (implicit using -> syntax).
# @param[in] $elementName the name of the XML element representing the
#   ProcessTransport.
# @param[in] $inclInh when saving data to disk, inherited elements
#   (e.g. data transport) are intentionally not saved.  For searches,
#   the inherited information is desired.  Set $inclInh to a non-zero
#   value when the inherited information is desired.
#
# @return an XML::LibXML::Element representing this ProcessTransport.
sub toXML {
    my ($self,
        $elementName,
        $inclInh) = @_;
    # This structure is never saved to disk
    return undef unless($inclInh);
    my $rv = $self->{'process'}->toXMLRef(
        $elementName, $self->{'processMacroSpec'}, $inclInh);
    my $xportXMLElem = $self->{'xport'}->toXMLRef(
        "xport", $self->{'xportMacroSpec'}, $inclInh);
    if (!defined($xportXMLElem)) {
        my $fakeMacroSpec = $self->{'xport'}->getMacroSpec();
        # _debugWrite(" trying fake macro spec $fakeMacroSpec");
        $xportXMLElem = $self->{'xport'}->toXMLRef(
            "xport", $fakeMacroSpec, $inclInh);
        # _debugWrite(" ... still no good") unless $xportXMLElem;
    }
    eval {
        if (defined($xportXMLElem)) {
            $rv->addChild($xportXMLElem);
        }
    };
    FAIL("error adding child: " . $@->message()) if (ref($@));
    FAIL("error adding child: " . $@) if ($@);
    return $rv;
}

################################
# ACCESSORS
################################

sub processEntity    { return $_[0]->{'process'}; }
sub processMacroSpec { return $_[0]->{'processMacroSpec'}; }
sub xportEntity      { return $_[0]->{'xport'}; }
sub xportMacroSpec   { return $_[0]->{'xportMacroSpec'}; }
sub isXportInherited { return $_[0]->{'xportInherited'}; }
sub dataTransport    { return $_[0]->{'dataTransport'}; }
# Return true if the transport is unspecified
sub isDefaultTransport { return ($_[0]->{'xport'}->{'id'} eq "DEFAULT"); }

# Set the transport associated with this ProcessTransport.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::ProcessTransport
#   object reference (implicit using -> syntax).
# @param[in] $xportMacroSpec The macro spec used in the DFDPROC
#   definition, or a generated macro spec if not otherwise specified.
# @param[in] $xportEntitySpec The entity spec matching (constructed
#   from) $xportMacroSpec.
# @param[in] $xportEntity The Transport Entity object reference for
#   this cross-reference.
sub setTransport {
    my ($self,
        $xportMacroSpec,
        $xportEntitySpec,
        $xportEntity) = @_;

    $self->{'xport'} = $xportEntity;
    $self->{'xportMacroSpec'} = $xportMacroSpec;
    # it is assumed that this sub will only be used when the transport
    # is inherited
    $self->{'xportInherited'} = 1;
    # propagate changes to DataTransport
    $self->{'dataTransport'}->setTransport(
        $xportMacroSpec, $xportEntitySpec, $xportEntity);
}


################################
# DATA MANAGEMENT
################################


# Determine if the DataTransport associated with this ProcessTransport
# matches another EntitySpec.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::ProcessTransport
#   object reference (implicit using -> syntax).
# @param[in] $dtEntitySpec a Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec
#   for another DataTransport to match against.
#
# @return true if the DataTransports match (includes checking against DEFAULT).
sub matchDataTransport {
    my ($self,
        $dtEntitySpec) = @_;
    return $self->dataTransport()->matchDataTransport($dtEntitySpec);
}


sub matchLocales {
    my ($self,
        $localeHash) = @_;
    my $procLocales = $self->processEntity()->locales();
    _debugFuncStart("ProcessTransport::matchLocales");
    _debugWrite("MINE:");
    if (defined($procLocales)) {
        _debugWrite($_) foreach (keys %{ $procLocales });
    }
    _debugWrite("THEIRS:");
    if (defined($localeHash)) {
        _debugWrite($_) foreach (keys %{ $localeHash });
    }
    _debugWrite("  ---");
    my $matchingLocales = {};
    foreach my $mykey (keys %{ $procLocales }) {
        foreach my $yourkey (keys %{ $localeHash }) {
            my $ples =
                Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->newEntity(
                    $procLocales->{$mykey});
            my $lhes = $localeHash->{$yourkey}->localeEntitySpec();
            if ($ples->matchID($lhes)) {
                # _debugWrite("$mykey matches $yourkey (inclusive)");
                $matchingLocales->{$mykey} = $procLocales->{$mykey};
            }
            undef $ples;
        }
    }
    _debugFuncEnd("ProcessTransport::matchLocales");
    return $matchingLocales;
}


1;
