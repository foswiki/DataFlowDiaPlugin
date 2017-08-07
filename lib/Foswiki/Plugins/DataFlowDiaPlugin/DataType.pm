# $Id: //foswiki-dfd/rel2_0_1/lib/Foswiki/Plugins/DataFlowDiaPlugin/DataType.pm#1 $

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

---+ package Foswiki::Plugins::DataFlowDiaPlugin::DataType

Entity class for DataFlowDiaPlugin data types.

=cut

package Foswiki::Plugins::DataFlowDiaPlugin::DataType;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use Foswiki::Plugins::DataFlowDiaPlugin::Entity qw(getRef);
use Foswiki::Plugins::DataFlowDiaPlugin::Util qw(:error :graphviz :set :debug);
use Foswiki::Plugins::DataFlowDiaPlugin::PackageConsts qw(:etypes :dirs);

use vars qw(@ISA);
@ISA = ('Foswiki::Plugins::DataFlowDiaPlugin::Entity');

################################
# CONSTRUCTORS
################################

# Create a new DataType object.
#
# @param[in] $class The name of the class being instantiated
# @param[in] $web the wiki web name containing the DataType definitions
# @param[in] $id the web-unique identifier for this DataType
# @param[in] $docManager DocManager object reference (for building
#   cross-references)
#
# @return a reference to a DataType object
sub new {
    my ($class,
        $web,
        $id,
        $docManager) = @_;
    my $self = $class->SUPER::new($web, $id, $docManager);

    # filled by addProcess via DataTransport.pm
    # key = Process Entity macro spec
    # value = ProcessTransport
    $self->{'producers'} = {};
    $self->{'consumers'} = {};
    $self->{'loopers'} = {};
    # filled by Process.pm with DataTranslation references...or something
    $self->{'to'} = {};
    $self->{'from'} = {};

    $self->fromMacroXref(
        $ENTITYTYPE_XPORT,
        'xport', $web, { 'xport' => "DEFAULT" }, 1);

    return bless ($self, $class);
}


################################
# MACRO PROCESSING
################################

# Pre-process DataType definition macros, storing the subroutine
# parameters and hash values into $self.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DataType
#   object reference (implicit using -> syntax).
# @param[in] $web the name of the web containing the definition for
#   this DataType.
# @param[in] $topic the name of the topic containing the definition
#   for this DataType.
# @param[in] $macroAttrs the parameters for the macro being processed,
#   mapping attribute id to value.
#
# @pre $macroAttrs->{'id'} is valid
# @post $self->{'defined'} == 1, and the remaining hash values are also set
sub fromMacro {
    my ($self,
        $web,
        $topic,
        $macroAttrs) = @_;
    $self->SUPER::fromMacro($web, $topic, $macroAttrs);

    $self->fromMacroXref(
        $ENTITYTYPE_XPORT,
        'xport', $web, $macroAttrs, 1, "data");
    unless (%{ $self->{'xport'} }) {
    # force a default if a transport wasn't defined in the macro
        $self->fromMacroXref(
            $ENTITYTYPE_XPORT,
            'xport', $web, { 'xport' => "DEFAULT" }, 1);
    }

    # It's likely that there are processes that have already had their
    # definition loaded, including their transport definitions.  If
    # those processes use the default transport, they would have no
    # information because it hasn't been defined yet.  Fix that here.
    $self->fixTransports("producers");
    $self->fixTransports("consumers");
    $self->fixTransports("loopers");
}


################################
# XML PROCESSING
################################

# Update the hash values in this DataType using the attributes of an
# XML::LibXML::Element.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DataType
#   object reference (implicit using -> syntax).
# @param[in] $xmlElem an XML::LibXML::Element object containing a
#   DataType definition.
#
# @pre "id", "name", "web" and "topic" attributes are set in $xmlElem
# @post $self->{'defined'} == 1, and the remaining hash values are also set
sub fromXML {
    my ($self, $xmlElem) = @_;
    $self->SUPER::fromXML($xmlElem);

    $self->fromXMLXref(
        $ENTITYTYPE_XPORT,
        'xport', $xmlElem, "xport", "data");
    # force a default if a transport wasn't defined in the XML
    unless (%{ $self->{'xport'} }) {
        $self->fromMacroXref(
            $ENTITYTYPE_XPORT,
            'xport', $self->{'web'}, { 'xport' => "DEFAULT" }, 1);
    }
}


# Create and return a new XML::LibXML::Element with attributes set
# according to the hash values in this DataType.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DataType
#   object reference (implicit using -> syntax).
# @param[in] $elementName the name of the XML element representing
#   this DataType.
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

    $self->toXMLProcXref("producers",    "producer",    $rv, $inclInh);
    $self->toXMLProcXref("consumers",    "consumer",    $rv, $inclInh);
    $self->toXMLProcXref("loopers",      "looper",      $rv, $inclInh);
    if ($inclInh) {
        $self->toXMLXref("from", "from", $rv, $inclInh);
        $self->toXMLXref("to",   "to",   $rv, $inclInh);
    }
    $self->toXMLXref('xport', 'xport', $rv, $inclInh);

    return $rv;
}


# Add child nodes to XML::LibXML::Element for Process
# cross-references.  This is only relevant to XML documents with
# redundant cross-references, i.e. "search documents".
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DataType
#   object reference (implicit using -> syntax).
# @param[in] $paramName the name of the hash element in $self
#   containing a hash reference to ProcessTransport object references,
#   i.e. $self->{$paramName}->{SOME_KEY}->ref(ProcessTransport).
# @param[in] $xmlChildName the name of the child node in the XML store
#   representing the processes stored in $paramName.
# @param[in] $xmlElem the parent XML::LibXML::Element of the new nodes.
# @param[in] $inclInh when saving data to disk, inherited elements
#   (e.g. data transport) are intentionally not saved.  For searches,
#   the inherited information is desired.  Set $inclInh to a non-zero
#   value when the inherited information is desired.
sub toXMLProcXref {
    my ($self,
        $paramName,
        $xmlChildName,
        $xmlElem,
        $inclInh) = @_;

    # This structure is never saved to disk
    return unless($inclInh);

    foreach my $key (sort keys %{ $self->{$paramName} }) {
        my $pt = $self->{$paramName}->{$key};
        my $procChild = $pt->toXML($xmlChildName, $inclInh);
        $xmlElem->addChild($procChild)
            if (defined($procChild));
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
    my ($class, $xmlElem) = @_;
    # SMELL surely there's a better way to do this...
    if ($xmlElem->nodeName eq "xport") {
        return $ENTITYTYPE_XPORT;
    }
    # only appear in search documents, not on disk
    if (($xmlElem->nodeName eq "producer") ||
        ($xmlElem->nodeName eq "consumer") ||
        ($xmlElem->nodeName eq "looper") ||
        ($xmlElem->nodeName eq "to") ||
        ($xmlElem->nodeName eq "from")) {
        return $ENTITYTYPE_PROC;
    }
    return undef;
}


################################
# ACCESSORS
################################

sub producers { return $_[0]->{'producers'}; }
sub consumers { return $_[0]->{'consumers'}; }
sub loopers   { return $_[0]->{'loopers'}; }
sub to        { return $_[0]->{'to'}; }
sub from      { return $_[0]->{'from'}; }

# Get the transport defined as the default used for this DataType
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DataType
#   object reference (implicit using -> syntax).
#
# @return list: (transport macro spec, transport entity) 
sub getTransport {
    my $self = shift;
    # 'xport' hash key is always defined and is a reference to a Transport
    # and there can be only one.
    my $xportKey = (keys %{ $self->{'xport'} })[0];
    my $xportEntity = $self->{'xport'}->{$xportKey};
    my $xportEntitySpec =
        Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->newEntity(
            $xportEntity);
    return ($xportEntitySpec, $xportEntity);
}


################################
# DATA MANAGEMENT
################################

# Get a hash reference containing processes using this data type.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DataType
#   object reference (implicit using -> syntax).
# @param[in] $dir The direction of interest for the propagation of
#   data (see DocManager).
# @param[in] $dtEntitySpec the EntitySpec of the DataTransport
#   used by the matching processes.  Processes not using this DataType
#   (including sub-ID) and Transport will not be returned.
#
# @return a hash reference containing matching ProcessTransport objects.
sub getConProc {
    my ($self,
        $dir,
        $dtEntitySpec) = @_;

    _debugFuncStart("getConProc");
    my $rv = {};
    my $procHash;
    if ($dir == $DIR_BACK) {
        $procHash = $self->{'producers'};
    } elsif ($dir == $DIR_FWD) {
        $procHash = $self->{'consumers'};
    } else {
        # TODO this probably should be done as a second run through
        # the loop below as long as $dir is non-zero
        $procHash = $self->{'loopers'};
    }
    # Match all ProcessTransport definitions from $procHash with $dtEntitySpec.
    if (defined($procHash)) {
        _debugWrite("procHash is defined");
        foreach my $key (keys %{ $procHash }) {
            _debugWrite("key=$key");
            if ($procHash->{$key}->matchDataTransport($dtEntitySpec)) {
                _debugWrite("adding process with matched transport");
                $rv->{$key} = $procHash->{$key};
            }
        }
    } else {
        _debugWrite("procHash is NOT defined");
    }
    undef $dtEntitySpec;
    _debugFuncEnd("getConProc");
    return $rv;
}


# Associate a process with this data type (i.e. provide a reverse
# cross-reference) for I/O.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DataType
#   object reference (implicit using -> syntax).
# @param[in] $pt a Foswiki::Plugins::DataFlowDiaPlugin::ProcessTransport
#   object reference utilizing this DataType.
# @param[in] $dataParamName the internal hash key storing the cross
#   reference (e.g. "consumers").
sub addProcess {
    my ($self,
        $pt,
        $dataParamName) = @_;
    my $hashKey = $pt->processMacroSpec();
    $self->{$dataParamName}->{$hashKey} = $pt;
}


# Associate a process with this data type (i.e. provide a reverse
# cross-reference) for type translations.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DataType
#   object reference (implicit using -> syntax).
# @param[in] $procEntity a Foswiki::Plugins::DataFlowDiaPlugin::Process
#   object reference utilizing this DataType.
# @param[in] $dataParamName the internal hash key storing the translation
#   (e.g. "to").
sub addTranslator {
    my ($self,
        $procEntity,
        $dataParamName) = @_;
    my $hashKey = $procEntity->getMacroSpec();
    $self->{$dataParamName}->{$hashKey} = $procEntity;
}


# Fix the definitions of Process entities that use this DataType
# without specifying a transport override, to make sure the Process
# has the proper transport defined.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DataType
#   object reference (implicit using -> syntax).
# @param[in] $paramName the internal hash key storing the cross
#   reference (e.g. "consumers").
sub fixTransports {
    my ($self,
        $paramName) = @_;
    foreach my $key (keys %{ $self->{$paramName} }) {
        if ($self->{$paramName}->{$key}->isDefaultTransport()) {
            $self->{$paramName}->{$key}->setTransport(
                $key, $self->getTransport());
        }
    }    
}


# Construct Entity connections (data flow) and store them in $graphCollection.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Entity
#   object reference (implicit using -> syntax).
# @param[in] $macroAttrs a Foswiki::Attrs object reference containing
#   the parameters for the macro being processed.
# @param[in,out] $graphCollection a GraphCollection object reference to
#   store the results of the connection-building.
# @param[in] $specHash an optional reference to a hash of EntitySpec
#   object references which, if specified, will be used to filter
#   DataTypes that do not match.
sub connect {
    my ($self,
        $macroAttrs,
        $graphCollection,
        $specHash) = @_;
    my $numProcs = 0;

    # check our termination condition
    return unless ($macroAttrs->{'level'});
    return if ($macroAttrs->{'hidedeprecated'} && $self->isDeprecated());

    my %macroAttrsCopy = %{ $macroAttrs };
    $macroAttrsCopy{'level'}--;
    if ($macroAttrs->{'dir'} & $DIR_BACK) {
        $macroAttrsCopy{'dir'} = $DIR_BACK;
        $numProcs += $self->connectProcess(
            $self->producers(),
            $macroAttrs,
            $graphCollection,
            $specHash);
    }
    if ($macroAttrs->{'dir'} & $DIR_FWD) {
        $macroAttrsCopy{'dir'} = $DIR_FWD;
        $numProcs += $self->connectProcess(
            $self->consumers(),
            $macroAttrs,
            $graphCollection,
            $specHash);
    }

    unless ($numProcs) {
        # create an "island" data node since this DataType has no
        # associated process.
        my $fakeLoc = Foswiki::Plugins::DataFlowDiaPlugin::Locale->new(
            $self->web(), "DEFAULT", $self->docMgr());
        my $fakeDT = Foswiki::Plugins::DataFlowDiaPlugin::DataTransport->new(
            $self->web(), $self->getMacroSpec(), undef, 0, $self->docMgr());
        $graphCollection->addDataLeaf($fakeLoc, undef, $fakeDT, 1);
    }
}


sub connectProcess {
    my ($self,
        $processes,
        $macroAttrs,
        $graphCollection,
        $specHash) = @_;
    my $rv = 0;
    foreach my $ptkey (sort keys %{ $processes }) {
        $processes->{$ptkey}->processEntity()->connect(
            $macroAttrs, $graphCollection, $specHash);
        $rv++;
    }
    return $rv;
}


################################
# GRAPHVIZ PROCESSING
################################

# Generate the nodes and edges representing the simple graph
# representing only the basic definition of this DataType.
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
    my $gotProcs = 0;
    my $loc = Foswiki::Plugins::DataFlowDiaPlugin::Locale->new(
        $self->web(), "DEFAULT", $self->docMgr());
    my $locMacroSpec = $loc->getMacroSpec();
    my $fakeDT = Foswiki::Plugins::DataFlowDiaPlugin::DataTransport->new(
        $self->web(), $self->getMacroSpec(), undef, 0, $self->docMgr());
    foreach my $procIOParam ('producers', 'consumers', 'loopers') {
        foreach my $ptkey (sort keys %{ $self->{$procIOParam} }) {
            my $pt = $self->{$procIOParam}->{$ptkey};
            my $dt = $pt->dataTransport();
            my $proc = $pt->processEntity();
            $graphCollection->addProcess($locMacroSpec, $loc, $proc, 1);
            $graphCollection->addDataLeaf($loc, $proc, $dt, 1);
            $gotProcs = 1;
        }
    }
    unless ($gotProcs) {
        # create an "island" data node since this DataType has no
        # associated process.
        $graphCollection->addDataLeaf($loc, undef, $fakeDT, 1);
    }
}


# graphviz options to use when rendering this Process as a node
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Process
#   object reference (implicit using -> syntax).
sub getDotNodeOptions {
    my $self = shift;
    return $Foswiki::Plugins::DataFlowDiaPlugin::dataNodeDepDefault
        if ($self->{'deprecated'});
    return $Foswiki::Plugins::DataFlowDiaPlugin::dataNodeDefault;
}


################################
# WIKI/WEB PROCESSING
################################

# @return the beginning of the anchor name for all DataType anchors.
sub getAnchorTag {
    return "DfdData";
}

1;
