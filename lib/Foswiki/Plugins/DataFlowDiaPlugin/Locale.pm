# $Id: //foswiki-dfd/rel2_0_1/lib/Foswiki/Plugins/DataFlowDiaPlugin/Locale.pm#1 $

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

---+ package Foswiki::Plugins::DataFlowDiaPlugin::Locale

Entity class for DataFlowDiaPlugin locales (for processes).

=cut

package Foswiki::Plugins::DataFlowDiaPlugin::Locale;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use Foswiki::Plugins::DataFlowDiaPlugin::LocaleTransport;
use Foswiki::Plugins::DataFlowDiaPlugin::Entity qw(macroToList getRef getRefFromXML);
use Foswiki::Plugins::DataFlowDiaPlugin::Util qw(:error :set :debug);
use Foswiki::Plugins::DataFlowDiaPlugin::PackageConsts qw(:etypes :dirs);

use vars qw(@ISA);
@ISA = ('Foswiki::Plugins::DataFlowDiaPlugin::Entity');

################################
# CONSTRUCTORS
################################

# Create a new Locale object.
#
# @param[in] $class The name of the class being instantiated
# @param[in] $web the wiki web name containing the Locale definitions
# @param[in] $id the web-unique identifier for this Locale
# @param[in] $docManager DocManager object reference (for building
#   cross-references)
#
#  @return a reference to a Locale object
sub new {
    my ($class,
        $web,
        $id,
        $docManager) = @_;
    my $self = $class->SUPER::new($web, $id, $docManager);

    # key = locale macro spec "|" xport macro spec
    # value = LocaleTransport Entity
    $self->{'connectedTo'} = {};
    $self->{'connectedFrom'} = {};
    # set in Process.pm,
    # key = Process Entity macro spec
    # value = Process Entity
    $self->{'processes'} = {};

    return bless ($self, $class);
}


################################
# MACRO PROCESSING
################################

# Pre-process Locale definition macros, storing the subroutine
# parameters and hash values into $self.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Locale
#   object reference (implicit using -> syntax).
# @param[in] $web the name of the web containing the definition for
#   this Locale.
# @param[in] $topic the name of the topic containing the definition
#   for this Locale.
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

    $self->purgeConnections();

    # connections have a unique syntax
    $self->fromMacroConnection($web, $macroAttrs);
}


# Process LocaleTransport definitions and store them internally.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Locale
#   object reference (implicit using -> syntax).
# @param[in] $web the name of the web where the desired entity is defined.
# @param[in] $macroAttrs a Foswiki::Attrs object reference containing
#   the parameters for the macro being processed.
sub fromMacroConnection {
    my ($self,
        $web,
        $macroAttrs) = @_;

    # clear out any existing data so old information is not retained,
    # but make sure that the field is set to at least an empty hash ref.
    $self->purgeConnections();

    if (defined($macroAttrs->{'connect'})) {
        my @connectionList = macroToList($macroAttrs->{'connect'});
        foreach my $cnctSpec (@connectionList) {
            my $lt = Foswiki::Plugins::DataFlowDiaPlugin::LocaleTransport->new(
                $web,
                $cnctSpec,
                $self->{'docMgr'});
            my $hashKey = $lt->macroSpec();
            $self->hashValue('connectedTo', $hashKey, $lt);
            $lt->reverseReferences($self);
        }
    }
}


################################
# XML PROCESSING
################################

# Update the hash values in this Locale using the attributes of an
# XML::LibXML::Element.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Locale
#   object reference (implicit using -> syntax).
# @param[in] $xmlElem an XML::LibXML::Element object containing an
#   Locale definition.
#
# @pre "id", "name", "web" and "topic" attributes are set in $xmlElem
# @post $self->{'defined'} == 1, and the remaining hash values are also set
sub fromXML {
    my ($self,
        $xmlElem) = @_;
    $self->SUPER::fromXML($xmlElem);

    $self->purgeConnections();

    # connections have a unique syntax
    $self->fromXMLConnection($xmlElem);
}


# Process LocaleTransport definitions and store them internally.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Locale
#   object reference (implicit using -> syntax).
# @param[in] $xmlElem an XML::LibXML::Element object containing a
#   Locale definition.
sub fromXMLConnection {
    my ($self,
        $xmlElem) = @_;

    my @nodelist = $xmlElem->findnodes("connection");
    FAIL("Error in XML::LibXML::Element->findnodes: " . $@->message())
        if (ref($@));
    FAIL("Error in XML::LibXML::Element->findnodes: " . $@)
        if ($@);

    foreach my $xmlNode (@nodelist) {
        my $lt = Foswiki::Plugins::DataFlowDiaPlugin::LocaleTransport->newXML(
            $xmlNode, $self->{'docMgr'});
        my $hashKey = $lt->macroSpec();
        $self->{'connectedTo'}->{$hashKey} = $lt;
        $lt->reverseReferences($self);
    }
}


# Create and return a new XML::LibXML::Element with attributes set
# according to the hash values in this Locale.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Locale
#   object reference (implicit using -> syntax).
# @param[in] $elementName the name of the XML element representing this Locale.
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

    $self->toXMLConnection($rv, $inclInh);

    if ($inclInh) {
        $self->toXMLXref('processes', 'process', $rv, $inclInh);
    }

    return $rv;
}


# Add child nodes to XML::LibXML::Element for inter-Locale connections
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Locale
#   object reference (implicit using -> syntax).
# @param[in] $xmlElem the parent XML::LibXML::Element of the new nodes.
# @param[in] $inclInh when saving data to disk, inherited elements
#   (e.g. data transport) are intentionally not saved.  For searches,
#   the inherited information is desired.  Set $inclInh to a
#   non-zero value when the inherited information is desired.
sub toXMLConnection {
    my ($self,
        $xmlElem,
        $inclInh) = @_;

    foreach my $key (sort keys %{ $self->{'connectedTo'} }) {
        my $cnctXMLElem = $self->{'connectedTo'}->{$key}->toXML(
            "connection", $inclInh);
        $xmlElem->addChild($cnctXMLElem);
    }
    if ($inclInh) {
        foreach my $key (sort keys %{ $self->{'connectedFrom'} }) {
            my $cnctXMLElem = $self->{'connectedFrom'}->{$key}->toXML(
                "connectionfrom", $inclInh);
            $xmlElem->addChild($cnctXMLElem);
        }
    }
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
    if ($xmlElem->nodeName eq "connection") {
        return $ENTITYTYPE_LOCALE;
    }
    if ($xmlElem->nodeName eq "xport") {
        return $ENTITYTYPE_XPORT;
    }
    # only appear in search documents, not on disk
    if ($xmlElem->nodeName eq "process") {
        return $ENTITYTYPE_PROC;
    }
    if ($xmlElem->nodeName eq "connectionfrom") {
        return $ENTITYTYPE_LOCALE;
    }
    return undef;
}


################################
# ACCESSORS
################################

# @return all processes associated with this Locale.
sub processes { return $_[0]->{'processes'}; }


################################
# DATA MANAGEMENT
################################

# Remove all cross references between this Locale and other Locales
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Locale
#   object reference (implicit using -> syntax).
sub purgeConnections {
    my ($self) = @_;
    foreach my $hashKey (keys %{ $self->{'connectedTo'} }) {
        $self->{'connectedTo'}->{$hashKey}->purgeReverse($self);
    }
    $self->{'connectedTo'} = {};
}


# Add a cross reference to this Locale indicating another Locale that
# connects to it unidirectionally, i.e. a Locale that can feed data to
# this Locale.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Locale
#   object reference (implicit using -> syntax).
# @param[in] $localeTransport The LocaleTransport object reference
#   defining the connecting Locale.
sub connectFrom {
    my ($self,
        $localeTransport) = @_;
    my $hashKey = $localeTransport->macroSpec();
    $self->{'connectedFrom'}->{$hashKey} = $localeTransport;
}


# Remove a cross reference to this Locale for a specific connecting Locale.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Locale
#   object reference (implicit using -> syntax).
# @param[in] $localeTransport The LocaleTransport object reference
#   defining the connecting Locale to be removed.
sub disconnectFrom {
    my ($self,
        $localeTransport) = @_;
    my $hashKey = $localeTransport->macroSpec();
    delete $self->{'connectedFrom'}->{$hashKey};
}


# Update a hash of LocaleTransport references matching a transport macro spec.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Locale
#   object reference (implicit using -> syntax).
# @param[in] $xportMacroSpec The transport macro spec used to
#   determine which connected Locales should be in the results.
# @param[out] $locXportHash A hash reference where matching
#   LocaleTransport object references will be stored.
# @param[in] $dir Determine whether to look at Locale entities this
#   Locale is connected to (dirFwd) or Locale entities that connect to
#   this one (dirBack).
sub hashConByXport {
    my ($self,
        $xportMacroSpec,
        $locXportHash,
        $dir,
        $macroAttrs) = @_;
    my $myLTcnct;
    # Use the hash of connected Locale Entity objects appropriate for
    # the connection direction.
    if ($dir == $DIR_BACK) {
        $myLTcnct = $self->{'connectedFrom'};
    } else {
        $myLTcnct = $self->{'connectedTo'};
    }
    my %matchedLocales = filterLocales($myLTcnct, $macroAttrs);
    foreach my $localeKey (keys %matchedLocales) {
        my $lt = $matchedLocales{$localeKey};
        my $ltXportMacroSpec = $lt->xportMacroSpec();
        if ($ltXportMacroSpec eq $xportMacroSpec) {
            $locXportHash->{$localeKey} = $matchedLocales{$localeKey};
        }
    }
    if ($dir == $DIR_BOTH) {
        # already filled with connectedTo, add connectedFrom
        $self->hashConByXport(
            $xportMacroSpec, $locXportHash,
            $DIR_BACK);
    }
    # make certain that the DEFAULT locale is always connected
    my $defLocale = $self->docMgr()->getEntity(
        $ENTITYTYPE_LOCALE,
        $self->web(),
        "DEFAULT");
    my $defLocMacroSpec = $defLocale->getMacroSpec();
    if (!defined($locXportHash->{$defLocMacroSpec})) {
        # only add it once, though.
        my $defLT = Foswiki::Plugins::DataFlowDiaPlugin::LocaleTransport->new(
            $self->web(),
            "$defLocMacroSpec|$xportMacroSpec",
            $self->docMgr());
        $locXportHash->{$defLocMacroSpec} = $defLT;
    }
}


# Match a list of locales with the locales requested/excluded by the
# user in the macro attributes.
#
# @param[in] $localeHash a hash reference of Locale entities, macro spec as key.
# @param[in] $macroAttrs a Foswiki::Attrs object reference containing
#   the parameters for the macro being processed.
# @return a filtered hash containing those key/value pairs
#   of $localeHash that match the filter settings in $macroAttrs.
sub filterLocales {
    my ($localeHash,
        $macroAttrs) = @_;
    my %matchingLocales = ();

    # TODO This is terrible, I really don't like the performance of
    # this method.  I would love to have something better here.

    # "BROKEN" meaning that it should never be used
    # This statement takes all of the Locale|Transport macro spec strings,
    # pulls off just the Locale macro spec, converts it into an EntitySpec,
    # and adds it to %localeEntitySpecs
    # Use $_ as the key which preserves the original key whether it
    # includes the transport or not.
    my %localeEntitySpecs =
        map { my ($locMacroSpec) = split(/\|/, $_);
              $_ =>
                  Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->new(
                      $locMacroSpec, "BROKEN") } keys %{ $localeHash };

    if (defined($macroAttrs->{'locales_hash'})) {
        my %macroEntitySpecs =
            map { my ($locMacroSpec) = split(/\|/, $_);
                  $_ =>
                      Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->new(
                          $locMacroSpec, "BROKEN") } keys %{ $macroAttrs->{'locales_hash'} };
        foreach my $mykey (keys %localeEntitySpecs) {
            foreach my $yourkey (keys %macroEntitySpecs) {
                # this WILL match DEFAULT
                if ($localeEntitySpecs{$mykey}->match(
                        $macroEntitySpecs{$yourkey})) {
                    $matchingLocales{$mykey} = $localeHash->{$mykey};
                    # This inner loop doesn't need to be executed any
                    # further as we'd just be adding the same item again.
                    last;
                }
            }
        }
    } elsif (defined($macroAttrs->{'exclocales_hash'})) {
        my %macroEntitySpecs =
            map { my ($locMacroSpec) = split(/\|/, $_);
                  $_ =>
                      Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->new(
                          $locMacroSpec, "BROKEN") } keys %{ $macroAttrs->{'exclocales_hash'} };
        # First make a copy of the entire hash, then remove matching
        # (excluded) locales.
        %matchingLocales = %{ $localeHash };
        foreach my $mykey (keys %localeEntitySpecs) {
            foreach my $yourkey (keys %macroEntitySpecs) {
                # this will NOT MATCH DEFAULT
                if ($localeEntitySpecs{$mykey}->matchID(
                        $macroEntitySpecs{$yourkey})) {
                    delete $matchingLocales{$mykey};
                    # This inner loop shouldn't be executed any
                    # further as we've just erased the item it would
                    # be using.
                    last;
                }
            }
        }
    } else {
        %matchingLocales = %{ $localeHash };
    }
    return %matchingLocales;
}


################################
# GRAPHVIZ PROCESSING
################################

# Generate the nodes and edges representing the simple graph
# representing only the basic definition of this Locale.
#
# Which is to say, do nothing, because Locales aren't graphed.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Process
#   object reference (implicit using -> syntax).
# @param[in] $macroAttrs a Foswiki::Attrs object reference containing
#   the parameters for the macro being processed.
# @param[in,out] $graphCollection a GraphCollection object reference to
#   store the results of the connection-building.
sub defnGraph {
    my ($self,
        $macroAttrs,
        $graphCollection) = @_;
    # Nothing to do - locales do not get rendered graphically
}


################################
# WIKI/WEB PROCESSING
################################

# @return the beginning of the anchor name for all Process anchors.
sub getAnchorTag {
    return "DfdLocale";
}

1;
