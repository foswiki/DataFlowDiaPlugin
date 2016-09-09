# $Id: //foswiki-dfd/rel2_0_1/lib/Foswiki/Plugins/DataFlowDiaPlugin/Transport.pm#1 $

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

---+ package Foswiki::Plugins::DataFlowDiaPlugin::Transport

Entity class for DataFlowDiaPlugin data transports.

=cut

package Foswiki::Plugins::DataFlowDiaPlugin::Transport;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use Foswiki::Plugins::DataFlowDiaPlugin::Entity;
use Foswiki::Plugins::DataFlowDiaPlugin::Util qw(:debug);
use Foswiki::Plugins::DataFlowDiaPlugin::PackageConsts qw(:etypes);

use vars qw(@ISA);
@ISA = ('Foswiki::Plugins::DataFlowDiaPlugin::Entity');

################################
# CONSTRUCTOR
################################

# Create a new Transport object.
#
# @param[in] $class The name of the class being instantiated
# @param[in] $web the wiki web name containing the entity definitions
# @param[in] $id the web-unique identifier for this Transport
# @param[in] $docManager DocManager object reference (for building
#   cross-references)
#
# @return a reference to a Transport object.
sub new {
    my ($class,
        $web,
        $id,
        $docManager) = @_;
    my $self = $class->SUPER::new($web, $id, $docManager);
    $self->{'broadcast'} = 0;
    # filled by Process.pm, DataType.pm, Locale.pm
    $self->{'processes'} = {};
    $self->{'data'} = {};
    $self->{'locales'} = {};
    return bless ($self, $class);
}


################################
# MACRO PROCESSING
################################

# Pre-process entity definition macros, storing the subroutine
# parameters and hash values into $self.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Transport
#   object reference (implicit using -> syntax).
# @param[in] $web the name of the web containing the definition for
#   this Transport.
# @param[in] $topic the name of the topic containing the definition
#   for this Transport.
# @param[in] $macroAttrs a Foswiki::Attrs object reference containing
#   the parameters for the macro being processed.
#
# @pre $macroAttrs->{'id'} is valid
# @pre $self->{'docMgr'} is set to a DocManager reference
# @post $self->{'defined'} == 1, and the remaining hash values are also set
sub fromMacro {
    my ($self,
        $web,
        $topic,
        $macroAttrs) = @_;
    $self->SUPER::fromMacro($web, $topic, $macroAttrs);

    $self->{'broadcast'} = Foswiki::Func::isTrue(
        $macroAttrs->{'broadcast'}, 0);
}


################################
# XML PROCESSING
################################

# Update the hash values in this Transport using the attributes of an
# XML::LibXML::Element.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Transport
#   object reference (implicit using -> syntax).
# @param[in] $xmlElem an XML::LibXML::Element object containing an
#   Transport definition.
#
# @pre "id", "name", "web" and "topic" attributes are set in $xmlElem
# @post $self->{'defined'} == 1, and the remaining hash values are also set
sub fromXML {
    my ($self,
        $xmlElem) = @_;
    $self->SUPER::fromXML($xmlElem);
    $self->{'broadcast'} = int($xmlElem->getAttribute("broadcast"));
}


# Create and return a new XML::LibXML::Element with attributes set
# according to the hash values in this Transport.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Transport
#   object reference (implicit using -> syntax).
# @param[in] $elementName the name of the XML element representing
#   this Transport.
# @param[in] $inclInh when saving data to disk, inherited elements
#   (e.g. data transport) are intentionally not saved.  For searches,
#   the inherited information is desired.  Set $inclInh to a
#   non-zero value when the inherited information is desired.
#
# @pre "id", "name", "web" and "topic" hash values are set in $self
sub toXML {
    my ($self,
        $elementName,
        $inclInh) = @_;
    my $rv = $self->SUPER::toXML($elementName, $inclInh);

    $rv->setAttribute("broadcast", $self->{'broadcast'});
    if ($inclInh) {
        $self->toXMLXref('processes', 'process', $rv, $inclInh);
        $self->toXMLXref('data',      'data',    $rv, $inclInh);
        $self->toXMLXref('locales',   'locale',  $rv, $inclInh);
    }

    return $rv;
}


# Each Entity structure has an XML representation and within that
# representation are cross-references to other data types.  In order
# to determine how to handle those cross-references, child classes
# must implement this method to map $xmlElem to an Entity Type (see
# DocManager).
#
# @param[in] $xmlElem an XML::LibXML::Element object reference
#   containing a cross-reference.
#
# @return either an Entity Type string or undef if the XML element
#   does not contain a known cross-reference node.
sub getEntityTypeFromXML {
    my ($class,
        $xmlElem) = @_;
    # SMELL surely there's a better way to do this...
    # only appear in search documents, not on disk
    if ($xmlElem->nodeName eq "process") {
        return $ENTITYTYPE_PROC;
    }
    if ($xmlElem->nodeName eq "locale") {
        return $ENTITYTYPE_LOCALE;
    }
    if ($xmlElem->nodeName eq "data") {
        return $ENTITYTYPE_DATA;
    }
    return undef;
}


################################
# DATA MANAGEMENT
################################


# Add a back-reference to this transport by the given Locale.
sub addLocale {
    my ($self,
        $localeEntity) = @_;
    my $hashKey = $localeEntity->getMacroSpec();
    $self->{'locales'}->{$hashKey} = $localeEntity;
}


# Remove a back-reference to this transport by the given Locale.
sub purgeLocale {
    my ($self,
        $localeEntity) = @_;
    my $hashKey = $localeEntity->getMacroSpec();
    delete $self->{'locales'}->{$hashKey};
}


# Add a back-reference to this transport by the given Process.
sub addProcess {
    my ($self,
        $procEntity) = @_;
    my $hashKey = $procEntity->getMacroSpec();
    $self->{'processes'}->{$hashKey} = $procEntity;
}


# Add a back-reference to this transport by the given DataType.
sub addData {
    my ($self,
        $dataEntity) = @_;
    my $hashKey = $dataEntity->getMacroSpec();
    $self->{'data'}->{$hashKey} = $dataEntity;
}



################################
# GRAPHVIZ PROCESSING
################################

# Generate the nodes and edges representing the simple graph
# representing only the basic definition of this Transport.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DataType
#   object reference (implicit using -> syntax).
# @param[in] $macroAttrs a Foswiki::Attrs object reference containing
#   the parameters for the macro being processed.
# @param[in,out] $graphCollection a GraphCollection object reference to
#   store the results of the connection-building.
sub defnGraph {
    my ($self,
        $macroAttrs,
        $graphCollection) = @_;
    # Nothing to do - transports do not get rendered graphically
}


################################
# WIKI/WEB PROCESSING
################################

# @return the beginning of the anchor name for all Transport anchors.
sub getAnchorTag {
    return "DfdTransport";
}

1;
