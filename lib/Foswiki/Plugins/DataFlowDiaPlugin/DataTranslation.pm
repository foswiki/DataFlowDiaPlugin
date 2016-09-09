# $Id: //foswiki-dfd/rel2_0_1/lib/Foswiki/Plugins/DataFlowDiaPlugin/DataTranslation.pm#1 $

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

---+ package Foswiki::Plugins::DataFlowDiaPlugin::DataTranslation

Class for storing information about associated data type and translation
pairs.  Used by Process.

=cut

package Foswiki::Plugins::DataFlowDiaPlugin::DataTranslation;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec;
use Foswiki::Plugins::DataFlowDiaPlugin::Util qw(:error :debug);
use Foswiki::Plugins::DataFlowDiaPlugin::PackageConsts qw(:etypes);

################################
# CONSTRUCTORS
################################

# Create a new DataTranslation object from wiki macro text.
#
# @param[in] $class The name of the class being instantiated
# @param[in] $defaultWeb The Wiki web to use if one is not explicitly
#   specified in the data macro specs.
# @param[in] $xlateMacroSpec a translation spec of the form
#   fromDataMacroSpec ">" toDataMacroSpec
# @param[in] $docManager DocManager object reference (for building
#   cross-references)
#
# @return a reference to a DataTranslation object.
sub new {
    my ($class,
        $defaultWeb,
        $xlateMacroSpec,
        $docManager) = @_;

    die("invalid translation specification \"$xlateMacroSpec\"\n")
        if ($xlateMacroSpec !~ /^[^>]+>[^>]+$/);
    my ($fromDataMacroSpec, $toDataMacroSpec) = split(/>/,$xlateMacroSpec);

    my ($fromDataEntitySpec, $fromDataEntity) =
        $docManager->getEntityFromMacroSpec(
            $ENTITYTYPE_DATA,
            $defaultWeb,
            $fromDataMacroSpec);

    my ($toDataEntitySpec, $toDataEntity) =
        $docManager->getEntityFromMacroSpec(
            $ENTITYTYPE_DATA,
            $defaultWeb,
            $toDataMacroSpec);

    my $self = {
        'from'           => $fromDataEntity,
        'fromEntitySpec' => $fromDataEntitySpec,
        'fromMacroSpec'  => $fromDataEntitySpec->spec(),
        'to'             => $toDataEntity,
        'toEntitySpec'   => $toDataEntitySpec,
        'toMacroSpec'    => $toDataEntitySpec->spec(),
        'macroSpec'      => $fromDataEntitySpec->spec() . ">" .
            $toDataEntitySpec->spec()
    };

    return bless ($self, $class);
}


# Create a new DataTranslation object from an XML::LibXML::Element.
#
# @param[in] $class The name of the class being instantiated
# @param[in] $xmlElem an XML::LibXML::Element object containing a
#   DataTranslation definition.
# @param[in] $docManager DocManager object reference (for building
#   cross-references)
#
# @return a reference to a DataTranslation object.
sub newXML {
    my ($class,
        $xmlElem,
        $docManager) = @_;
    my @fromnodelist = $xmlElem->findnodes("from");
    FAIL("Error in XML::LibXML::Element->findnodes: " . $@->message())
        if (ref($@));
    FAIL("Error in XML::LibXML::Element->findnodes: " . $@)
        if ($@);
    FAIL("Invalid number of \"from\" child nodes of translation")
        unless (scalar(@fromnodelist) == 1);
    my ($fromEntitySpec, $fromEntity) = $docManager->getEntityFromXML(
        $ENTITYTYPE_DATA,
        $fromnodelist[0]);

    my @tonodelist = $xmlElem->findnodes("to");
    FAIL("Error in XML::LibXML::Element->findnodes: " . $@->message())
        if (ref($@));
    FAIL("Error in XML::LibXML::Element->findnodes: " . $@)
        if ($@);
    FAIL("Invalid number of \"to\" child nodes of translation")
        unless (scalar(@tonodelist) == 1);
    my ($toEntitySpec, $toEntity) = $docManager->getEntityFromXML(
        $ENTITYTYPE_DATA,
        $tonodelist[0]);

    my $self = {
        'from'           => $fromEntity,
        'fromEntitySpec' => $fromEntitySpec,
        'fromMacroSpec'  => $fromEntitySpec->spec(),
        'to'             => $toEntity,
        'toEntitySpec'   => $toEntitySpec,
        'toMacroSpec'    => $toEntitySpec->spec(),
        'macroSpec'      => $fromEntitySpec->spec() . ">" .
            $toEntitySpec->spec()
    };

    return bless ($self, $class);
}


################################
# XML PROCESSING
################################

# Create an XML::LibXML::Element representing this DataTranslation.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DataTranslation
#   object reference (implicit using -> syntax).
# @param[in] $inclInh when saving data to disk, inherited elements
#   (e.g. data transport) are intentionally not saved.  For searches,
#   the inherited information is desired.  Set $inclInh to a non-zero
#   value when the inherited information is desired.
#
# @return an XML::LibXML::Element representing this DataTranslation.
sub toXML {
    my ($self,
        $inclInh) = @_;
    my $rv = XML::LibXML::Element->new("translation");
    $rv->addChild($self->fromAsXML($inclInh));
    $rv->addChild($self->toAsXML($inclInh));
    return $rv;
}


# Create an XML::LibXML::Element representing the source data type for
# this DataTranslation.
#
# @param[in] $inclInh when saving data to disk, inherited elements
#   (e.g. data transport) are intentionally not saved.  For searches,
#   the inherited information is desired.  Set $inclInh to a non-zero
#   value when the inherited information is desired.
#
# @return an XML::LibXML::Element representing the source data type
#   for this DataTranslation.
sub fromAsXML {
    my ($self,
        $inclInh) = @_;
    return $self->fromDataEntity()->toXMLRef(
        "from",
        $self->fromDataMacroSpec(),
        $inclInh);
}


# Create an XML::LibXML::Element representing the target data type for
# this DataTranslation.
#
# @param[in] $inclInh when saving data to disk, inherited elements
#   (e.g. data transport) are intentionally not saved.  For searches,
#   the inherited information is desired.  Set $inclInh to a non-zero
#   value when the inherited information is desired.
#
# @return an XML::LibXML::Element representing the target data type
#   for this DataTranslation.
sub toAsXML {
    my ($self,
        $inclInh) = @_;
    return $self->toDataEntity()->toXMLRef(
        "to",
        $self->toDataMacroSpec(),
        $inclInh);
}


################################
# ACCESSORS
################################

sub macroSpec          { return $_[0]->{'macroSpec'}; }
sub fromDataEntity     { return $_[0]->{'from'}; }
sub fromDataEntitySpec { return $_[0]->{'fromEntitySpec'}; }
sub fromDataMacroSpec  { return $_[0]->{'fromMacroSpec'}; }
sub toDataEntity       { return $_[0]->{'to'}; }
sub toDataEntitySpec   { return $_[0]->{'toEntitySpec'}; }
sub toDataMacroSpec    { return $_[0]->{'toMacroSpec'}; }


1;
