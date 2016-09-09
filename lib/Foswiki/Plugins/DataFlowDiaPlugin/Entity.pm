# $Id: //foswiki-dfd/rel2_0_1/lib/Foswiki/Plugins/DataFlowDiaPlugin/Entity.pm#1 $

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

---+ package Foswiki::Plugins::DataFlowDiaPlugin::Entity

Defines a base class for objects containing defined meta-data for
DataFlowDiaPlugin.

=cut

package Foswiki::Plugins::DataFlowDiaPlugin::Entity;

# Always use strict to enforce variable scoping
use strict;
use warnings;
use vars qw(@EXPORT_OK);

require Exporter;
*import = \&Exporter::import;
@EXPORT_OK = qw(macroToList getRef getRefFromXML derefHash);

use Foswiki::Plugins::DataFlowDiaPlugin::Util qw(:error :graphviz :set :debug);
use Foswiki::Plugins::DataFlowDiaPlugin::PackageConsts qw(:etypes :class);

################################
# CONSTRUCTOR
################################

# Create a new Entity object.
#
# @param[in] $class The name of the class being instantiated
# @param[in] $web the wiki web name containing the entity definitions
# @param[in] $id the web-unique identifier for this Entity
# @param[in] $docManager DocManager object reference (for building
#   cross-references)
#
# @return a reference to an Entity object
sub new {
    my ($class,
        $web,
        $id,
        $docManager) = @_;
    my $self = {
        'id'          => $id,
        'subid'       => "DEFAULT",
        'instance'    => '',
        'instanceNum' => 1,
        'name'        => $id,
        'web'         => $web || '',
        'topic'       => '',
        'url'         => '',
        'deprecated'  => 0,
        'flags'       => '',
        # non-zero if this entity was defined by a macro or XML
        'defined'     => 0,
        'docMgr'      => $docManager
    };
    # Hash to Group object references
    my $blessed = bless ($self, $class);
    # never ever do this for groups, or you'll get into infinite recursion
    if (!$class->isa($CLASS_GROUP)) {
        $blessed->fromMacroXref(
            $ENTITYTYPE_GROUP,
            'groups', $web, { 'groups' => "DEFAULT" }, 0,
            Foswiki::Plugins::DataFlowDiaPlugin::Group::getRevParam($class));
    }
    return $blessed;
}


################################
# MACRO PROCESSING
################################

# Pre-process entity definition macros, storing the subroutine
# parameters and hash values into $self.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Entity
#   object reference (implicit using -> syntax).
# @param[in] $web the name of the web containing the definition for this Entity.
# @param[in] $topic the name of the topic containing the definition
#   for this Entity.
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
    # set all the fields from the macro to make sure no cruft is left over
    $self->{'id'} = $macroAttrs->{'id'};
    # fromMacro is used to process definitions, not cross-references,
    # therefore 'subid' must be DEFAULT.
    $self->{'subid'} = "DEFAULT";
    $self->{'instance'} = '';
    $self->{'instanceNum'} = 1;
    $self->{'name'} = $macroAttrs->{'name'} || $self->{'id'};
    $self->{'web'} = $web;
    $self->{'topic'} = $topic;
    $self->{'url'} = $macroAttrs->{'url'} || '';
    $self->{'deprecated'} = Foswiki::Func::isTrue(
        $macroAttrs->{'deprecated'}, 0);
    $self->{'flags'} = $macroAttrs->{'flags'} || '';
    $self->{'defined'} = 1;

    # never ever do this for groups, or you'll get into infinite recursion
    if (!$self->isa($CLASS_GROUP)) {
        my $revp = Foswiki::Plugins::DataFlowDiaPlugin::Group::getRevParam(
            $self);
        $self->fromMacroXref(
            $ENTITYTYPE_GROUP, 'groups', $web, $macroAttrs, 0, $revp);
        if (!%{ $self->{'groups'} }) {
            # no group specified, use default
            $self->fromMacroXref(
                $ENTITYTYPE_GROUP, 'groups', $web, { 'groups' => "DEFAULT" }, 0,
                $revp);
        }
    }
}


# Process cross-references and store them internally.  This is used
# for cross-references that are stored as Entity references.  Other
# cross-references that involve paired data such as DataTransport is
# implemented elsewhere.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Entity
#   object reference (implicit using -> syntax).
# @param[in] $entityType a string indicating the type of Entity being
#   referred to. (see "Entity Types" in DocManager.pm)
# @param[in] $paramName a string naming the internal hash key where
#   these cross-references are stored.
# @param[in] $web the name of the web where the desired entity is defined.
# @param[in] $macroAttrs a Foswiki::Attrs object reference containing
#   the parameters for the macro being processed.
# @param[in] $single if non-zero, restrict this cross-reference to a
#   single value.
# @param[in] $reverseParamName a string naming the internal hash key
#   where in the cross-referenced Entity to store a back-reference to
#   $self.
sub fromMacroXref {
    my ($self,
        $entityType,
        $paramName,
        $web,
        $macroAttrs,
        $single,
        $reverseParamName) = @_;

    # clear out any existing data so old information is not retained,
    # but make sure that the field is set to at least an empty hash ref.
    $self->purgeHash($paramName, $reverseParamName);

    if (defined($macroAttrs->{$paramName})) {
        my @xrefList = macroToList($macroAttrs->{$paramName});
        FAIL("Too many $paramName values, only one allowed")
            if ($single && scalar(@xrefList) > 1);
        foreach my $macroSpec (@xrefList) {
            my ($entitySpec, $entity) =
                $self->docMgr()->getEntityFromMacroSpec(
                    $entityType,
                    $web,
                    $macroSpec);
            my $hashKey = $entitySpec->spec();
            $self->hashValue($paramName, $hashKey, $entity);
            if ($reverseParamName) {
                $hashKey = $self->getMacroSpec();
                $entity->hashValue($reverseParamName, $hashKey, $self);
            }
        }
    }
}


# Convert a text-based list from a wiki macro parameter to a Perl list.
# @param[in] $macroParam a string containing a comma-separated list of
#   values for a macro attribute.
sub macroToList {
    my ($macroParam) = @_;
    return split(/\s*,\s*/, $macroParam);
}


# Return a macro spec string constructed for this entity.
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Entity
#   object reference (implicit using -> syntax).
sub getMacroSpec {
    my ($self) = @_;
    my $rv = $self->web() . "." . $self->id() . "#" . $self->subid();
    return $rv;
}


# Return an abbreviated macro spec (hiding web and sub-ID if default)
# string constructed for this entity.
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Entity
#   object reference (implicit using -> syntax).
sub getAbbrevMacroSpec {
    my ($self) = @_;
    my $rv = $self->id();
    $rv .= "#" . $self->subid()
        if ($self->subid() ne "DEFAULT");
    return $rv;
}


################################
# XML PROCESSING
################################

# Update the hash values in this Entity using the attributes of an
# XML::LibXML::Element.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Entity
#   object reference (implicit using -> syntax).
# @param[in] $xmlElem an XML::LibXML::Element object containing an
#   Entity definition.
#
# @pre "id", "name", "web" and "topic" attributes are set in $xmlElem
# @post $self->{'defined'} == 1, and the remaining hash values are also set
sub fromXML {
    my ($self,
        $xmlElem) = @_;
    FAIL("required id attribute missing from XML\n")
        unless $xmlElem->hasAttribute("id");
    $self->{'id'} = $xmlElem->getAttribute("id");
    # fromXML is used to process definitions, not cross-references,
    # therefore 'subid' must be DEFAULT.
    $self->{'subid'} = "DEFAULT";
    $self->{'instance'} = '';
    $self->{'instanceNum'} = 1;
    $self->{'name'} = $xmlElem->getAttribute("name");
    $self->{'web'} = $xmlElem->getAttribute("web");
    $self->{'topic'} = $xmlElem->getAttribute("topic");
    $self->{'url'} = $xmlElem->getAttribute("url")
        if ($xmlElem->hasAttribute("url"));
    if ($xmlElem->hasAttribute("deprecated")) {
        $self->{'deprecated'} = int($xmlElem->getAttribute("deprecated"));
    } else {
        $self->{'deprecated'} = 0;
    }
    if ($xmlElem->hasAttribute("flags")) {
        $self->{'flags'} = $xmlElem->getAttribute("flags");
    } else {
        $self->{'flags'} = '';
    }
    # never ever do this for groups, or you'll get into infinite recursion
    if (!$self->isa($CLASS_GROUP)) {
        my $revp = Foswiki::Plugins::DataFlowDiaPlugin::Group::getRevParam(
            $self);
        $self->fromXMLXref(
            $ENTITYTYPE_GROUP, 'groups', $xmlElem, "group", $revp);
        if (!%{ $self->{'groups'} }) {
            # no group specified, use default
            $self->fromMacroXref(
                $ENTITYTYPE_GROUP, 'groups', $self->{'web'},
                { 'groups' => "DEFAULT" }, 0, $revp);
        }
    }
    # fromXML() should only be used for parsing objects defined in XML source
    $self->{'defined'} = 1;
}


# Process cross-references and store them internally.  This is used
# for cross-references that are stored as Entity references.  Other
# cross-references that involve paired data such as DataTransport is
# implemented elsewhere.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Entity
#   object reference (implicit using -> syntax).
# @param[in] $entityType a string indicating the type of Entity being
#   referred to. (see "Entity Types" in DocManager.pm)
# @param[in] $paramName a string naming the internal hash key where
#   these cross-references are stored.
# @param[in] $xmlElem an XML::LibXML::Element object containing a
#   Entity definition.
# @param[in] $nodename the name of the XML child node containing
#   cross-references.
# @param[in] $reverseParamName a string naming the internal hash key
#   where in the cross-referenced Entity to store a back-reference to
#   $self.
sub fromXMLXref {
    my ($self,
        $entityType,
        $paramName,
        $xmlElem,
        $nodename,
        $reverseParamName) = @_;

    my @nodelist = $xmlElem->findnodes($nodename);
    FAIL("Error in XML::LibXML::Element->findnodes: " . $@->message())
        if (ref($@));
    FAIL("Error in XML::LibXML::Element->findnodes: " . $@)
        if ($@);

    # clear out any existing data so old information is not retained,
    # but make sure that the field is set to at least an empty hash ref.
    $self->purgeHash($paramName, $reverseParamName);

    foreach my $xmlNode (@nodelist) {
        my ($entitySpec, $entity) = $self->docMgr()->getEntityFromXML(
            $entityType,
            $xmlNode);
        my $hashKey = $entitySpec->spec();
        $self->hashValue($paramName, $hashKey, $entity);
        if ($reverseParamName) {
            $hashKey = $self->getMacroSpec();
            $entity->hashValue($reverseParamName, $hashKey, $self);
        }
    }
}


# Create and return a new XML::LibXML::Element with attributes set
# according to the hash values in this Entity.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Entity
#   object reference (implicit using -> syntax).
# @param[in] $elementName the name of the XML element representing this Entity.
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
    my $rv = XML::LibXML::Element->new($elementName);
    $rv->setAttribute("id", $self->id());
    # should not be storing subid in XML via this method
    $rv->setAttribute("name", $self->name());
    $rv->setAttribute("web", $self->web());
    $rv->setAttribute("topic", $self->topic());
    $rv->setAttribute("url", $self->url())
        if ($self->url());
    $rv->setAttribute("deprecated", $self->isDeprecated())
        if (defined($self->isDeprecated()));
    $rv->setAttribute("flags", $self->flags())
        if ($self->flags());
    if ($inclInh) {
        $rv->setAttribute("defined", $self->isDefined());
        # This is a kludge to work around the fact that you can't
        # select the node name in XPath 1.0
        $rv->setAttribute("nodename", $elementName);
    }
    # never ever do this for groups, or you'll get into infinite recursion
    if (!$self->isa($CLASS_GROUP)) {    
        $self->toXMLXref('groups', 'group', $rv, $inclInh);
    }
    # subid, instance, and instanceNum are used only during rendering
    # and do not have fixed values in this context.
    # docMgr is only used for call-backs
    return $rv;
}


# Create and return a new XML::LibXML::Element with "id" and "web"
# attributes set for a basic XML reference element.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Entity
#   object reference (implicit using -> syntax).
# @param[in] $elementName the name of the XML element representing a
#   reference to this Entity.
# @param[in] $refKey a string of the format ID#subID, which provides
#   the subID for the data type, which is not stored with the data
#   type itself.  See getRef().
# @param[in] $inclInh when saving data to disk, inherited elements
#   (e.g. data transport) are intentionally not saved.  For searches,
#   the inherited information is desired.  Set $inclInh to a
#   non-zero value when the inherited information is desired.
#
# @pre "id" and "web" hash values are set in $self
# @return an XML::LibXML::Element object reference, or undef if id is DEFAULT
sub toXMLRef {
    my ($self,
        $elementName,
        $refKey,
        $inclInh) = @_;
    my $entitySpec = Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->new(
        $refKey, $self->web());
    if ($entitySpec->id() eq "DEFAULT") {
        return undef;
    }
    my $rv = XML::LibXML::Element->new($elementName);
    $rv->setAttribute("id", $entitySpec->id());
    $rv->setAttribute("subid", $entitySpec->subid())
        unless ($entitySpec->subid() eq "DEFAULT");
    $rv->setAttribute("web", $entitySpec->web());
    if ($inclInh) {
        $rv->setAttribute("defined", $self->isDefined());
        $rv->setAttribute("deprecated", $self->isDeprecated() || 0);
        # This is a kludge to work around the fact that you can't
        # select the node name in XPath 1.0
        $rv->setAttribute("nodename", $elementName);
        # never ever do this for groups, or you'll get into infinite recursion
        if (!$self->isa($CLASS_GROUP)) {    
            $self->toXMLXref('groups', 'group', $rv, $inclInh);
        }
    }
    return $rv;
}


# Add child nodes to XML::LibXML::Element for I/O cross-references
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Entity
#   object reference (implicit using -> syntax).
# @param[in] $paramName the name of the hash element in $self
#   containing a hash reference to Entity object references,
#   i.e. $self->{$paramName}->{SOME_KEY}->ref(Entity).
# @param[in] $xmlChildName the name of the child node in the XML store
#   representing the data types stored in $paramName.
# @param[in] $xmlElem the XML::LibXML::Element of which the new nodes
#   will be children.
# @param[in] $inclInh when saving data to disk, inherited elements
#   (e.g. data transport) are intentionally not saved.  For searches,
#   the inherited information is desired.  Set $inclInh to a
#   non-zero value when the inherited information is desired.
sub toXMLXref {
    my ($self,
        $paramName,
        $xmlChildName,
        $xmlElem,
        $inclInh) = @_;

    foreach my $key (sort keys %{ $self->{$paramName} }) {
        my $child = $self->{$paramName}->{$key}->toXMLRef(
            $xmlChildName, $key, $inclInh);
        $xmlElem->addChild($child)
            if (defined($child));
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
    return undef;
}


################################
# ACCESSORS
################################

sub groups       { return $_[0]->{'groups'}; }
sub id           { return $_[0]->{'id'}; }
sub subid        { return $_[0]->{'subid'}; }
sub setSubID     { $_[0]->{'subid'} = $_[1]; }
sub instance     { return $_[0]->{'instance'}; }
sub setInstance  { $_[0]->{'instance'} = $_[1]; }
sub instanceNum  { return $_[0]->{'instanceNum'}; }
sub name         { return $_[0]->{'name'}; }
sub web          { return $_[0]->{'web'}; }
sub topic        { return $_[0]->{'topic'}; }
sub url          { return $_[0]->{'url'}; }
sub isDeprecated { return $_[0]->{'deprecated'}; }
sub flags        { return $_[0]->{'flags'}; }
sub setFlags     { $_[0]->{'flags'} = $_[1]; }
sub isDefined    { return $_[0]->{'defined'}; }
sub docMgr       { return $_[0]->{'docMgr'}; }

sub addInstanceNum   { return ++$_[0]->{'instanceNum'}; }
sub setInstanceNum   { $_[0]->{'instanceNum'} = $_[1]; }
sub resetInstanceNum { $_[0]->{'instanceNum'} = 1; }


################################
# DATA MANAGEMENT
################################


# Store a value in a named hash key.  This is a hash of a hash.  The
# top-level hash key is $paramName and the second-level hash key is
# $hashKey.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Entity
#   object reference (implicit using -> syntax).
# @param[in] $paramName a string naming the internal hash key where
#   $value is to be stored.
# @param[in] $hashKey the second-level key of the hash where $value is
#   to be stored.
# @param[in] $value the value to be stored in the hash.
sub hashValue {
    my ($self,
        $paramName,
        $hashKey,
        $value) = @_;
    $self->{$paramName}->{$hashKey} = $value;
}


# Remove a value in a named hash by key.  This is the opposite of hashValue.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Entity
#   object reference (implicit using -> syntax).
# @param[in] $paramName a string naming the internal hash key whose
#   value is to be removed.
# @param[in] $hashKey the second-level key of the hash whose value is
#   to be removed.
sub purgeHashValue {
    my ($self,
        $paramName,
        $hashKey) = @_;
    delete $self->{$paramName}->{$hashKey};
}


# Remove all values from a named hash key, including reverse cross-references.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Entity
#   object reference (implicit using -> syntax).
# @param[in] $paramName a string naming the internal hash key whose
#   value is to be removed.
# @param[in] $reverseParamName a string naming the internal hash key
#   of the cross-referenced Entity whose value is to be removed.  That
#   is, reverse cross-references to this Entity will be removed from
#   the Entity objects being purged from this Entity.
sub purgeHash {
    my ($self,
        $paramName,
        $reverseParamName) = @_;
    if ($reverseParamName) {
        my $reverseHashKey = $self->getMacroSpec();
        foreach my $hashKey (keys %{ $self->{$paramName} }) {
            $self->{$paramName}->{$hashKey}->purgeHashValue(
                $reverseParamName, $reverseHashKey);
        }
    }
    $self->{$paramName} = {};
}


# Construct Entity connections (data flow) and store them in $graphCollection.
# This method should be implemented as appropriate in child classes.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Entity
#   object reference (implicit using -> syntax).
# @param[in] $macroAttrs a Foswiki::Attrs object reference containing
#   the parameters for the macro being processed.
# @param[in,out] $graphCollection a GraphCollection object reference to
#   store the results of the connection-building.
# @param[in] $groupHash an optional reference to a hash of DataType
#   entities which, if specified, will only match connections that
#   involve DataTypes contained within.
sub connect {
    my ($self,
        $macroAttrs,
        $graphCollection,
        $groupHash) = @_;
}


# Clear any internal storage used strictly for XML XPath queries.
sub clearSearchMeta {
    my ($self) = @_;
}


# Get an abbreviated ID for this Entity, where web is removed if it
# matches the specified web, and any DEFAULT values are left blank,
# and trailing '#' symbols are removed.
sub getShortID {
    my ($self,
        $web) = @_;
    my $rv = "";
    $rv .= $self->web() . "."
        if ($self->web() ne $web);
    $rv .= $self->id();
    $rv .= "#" . $self->subid()
        if ($self->subid() ne "DEFAULT");
    return $rv;
}


################################
# GRAPHVIZ PROCESSING
################################

# Render this entity as a Graphviz node.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Entity
#   object reference (implicit using -> syntax).
# @param[in] $macroAttrs a Foswiki::Attrs object reference containing
#   the parameters for the macro being processed.
# @return this entity rendered as Graphviz text describing a node.
sub renderGraph {
    my ($self,
        $macroAttrs) = @_;
    my $url = $self->getURL();
    my $rv = $self->getDotNodeName()
        . " [ "
        . $self->getDotNodeOptions();
    $rv .= ",URL=\"$url\""
        if defined $url;
    $rv .= ",label=\""
        . $self->getDotLabel()
        . "\",tooltip=\""
        . $self->getDotTooltip()
        . "\" ]";
    return $rv;
}


# graphviz options to use when rendering this Entity as a node
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Entity
#   object reference (implicit using -> syntax).
sub getDotNodeOptions {
    my $self = shift;
    return "shape=\"point\"";
}


# Returns a type string to be used in tooltips
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Entity
#   object reference (implicit using -> syntax).
sub getDotNodeType {
    my $self = shift;
    my $type = ref($self);
    $type =~ s/^.*:://;
    return $type;
}


# Similar to labels, but a more readable presentation for tooltip or
# "hover text".
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Entity
#   object reference (implicit using -> syntax).
sub getDotTooltip {
    my $self = shift;
    my $rv = "";
    my $nodetype = $self->getDotNodeType();

    $rv .= "type: $nodetype&#10;"
        if ($nodetype);
    $rv .= "id: " . $self->id() . "&#10;";
    $rv .= "subid: " . $self->subid() . "&#10;"
        if ($self->subid());
    $rv .= "name: " . $self->name() . "&#10;"
        if ($self->name());
    foreach my $key (keys %{ $self->{'groups'} }) {
        $rv .= "group: " . $self->{'groups'}->{$key}->getShortID($self->web())
            . "&#10;";
    }
    $rv .= "(undefined)&#10;"
        unless ($self->isDefined());
    return $rv;
}


# graphviz node name
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Entity
#   object reference (implicit using -> syntax).
sub getDotNodeName {
    my $self = shift;
    my $rv = $self->getGraphvizInstance();
    $rv .= "_" . $self->instance() . "_" . $self->instanceNum();
    return $rv;
}


# graphviz label, for edges and nodes
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Entity
#   object reference (implicit using -> syntax).
sub getDotLabel {
    my $self = shift;
    my $rv = "";
    return "" if ($self->name() eq "DEFAULT");
    my @groupKeys = sort keys %{ $self->{'groups'} };
    if ((scalar(@groupKeys) == 1) &&
        ($self->{'groups'}->{$groupKeys[0]}->id() ne "DEFAULT")) {
        # label using the single, non-default group ID
        $rv .= $self->{'groups'}->{$groupKeys[0]}->getShortID($self->web())
            . "\\n";
    } elsif (scalar(@groupKeys) > 1) {
        # label using the first group ID and elipses to indicate more
        $rv .= $self->{'groups'}->{$groupKeys[0]}->getShortID($self->web())
            . ", ...\\n";
    }
    $rv .= $self->{'name'};
    $rv .= ("\\n" . $self->{'subid'})
        if ($self->{'subid'} ne "DEFAULT");
    return $rv;
}


# graphviz edge between two Entity nodes
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Entity
#   object reference (implicit using -> syntax).
# @param[in] $fromEntity a Foswiki::Plugins::DataFlowDiaPlugin::Entity
#   object reference representing the source node for the Graphviz edge.
# @param[in] $toEntity a Foswiki::Plugins::DataFlowDiaPlugin::Entity
#   object reference representing the target node for the Graphviz edge.
# @param[in] $reverse if non-zero, the arrowhead of the edge will be
#   pointing at $fromEntity instead of $toEntity.
# @param[in] $addorn additional Graphviz edge attributes for this edge.
sub getDotEdge {
    my ($self,
        $fromEntity,
        $toEntity,
        $reverse,
        $addorn) = @_;
    my $realFrom = $fromEntity;
    my $realTo = $toEntity;
    my $extra = "";

    if ($reverse) {
        $extra .= ", dir=back";
    }

    my $url = $self->getURL();
    $extra .= ", URL=\"$url\"" if defined $url;
    $extra .= ", tooltip=\"" . $self->getDotTooltip() . "\"";
    $extra .= ", labeltooltip=\"" . $self->getDotTooltip() . "\"";
    my $rv = $realFrom->getDotNodeName()
        . " -> "
        . $realTo->getDotNodeName()
        . " [ label=\""
        . $self->getDotLabel()
        . "\"$extra";
    $rv .= ", $addorn" if defined $addorn;
    $rv .= " ]";
    return $rv;
}


# Return an Graphviz-friendly macro spec string constructed for this entity.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Entity
#   object reference (implicit using -> syntax).
sub getGraphvizInstance {
    my ($self) = @_;
    my $rv = $self->web() . "_" . $self->id() . "_" . $self->subid();
    # turn all characters that are invalid for graphviz names into _
    $rv =~ s/[^A-Za-z0-9_]/_/g;
    return $rv;
}


################################
# WIKI/WEB PROCESSING
################################

# use this for inserting anchors into an HTML document
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Entity
#   object reference (implicit using -> syntax).
sub getAnchorName {
    my $self = shift;
    my $ctype = ucfirst $self->id();
    my $tag = $self->getAnchorTag();
    return "" unless $tag;
    # Use HTML instead of wiki syntax because it removes a layer of
    # processing and also because the wiki rejects characters in
    # anchor names that are valid.
    return "<a name=\"$tag$ctype\"></a>";
}


# use this for providing links to anchors via URL
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Entity
#   object reference (implicit using -> syntax).
sub getAnchorRef {
    my $self = shift;
    my $ctype = ucfirst $self->id();
    my $tag = $self->getAnchorTag();
    return "" unless $tag;
    return "#$tag$ctype";
}


# This should be overridden by child classes/packages
sub getAnchorTag() { return "IAmBroken"; }


# Get a fully-specified URL linking to this object.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Entity
#   object reference (implicit using -> syntax).
# @return undef if this Entity is not explicitly defined via macro/XML,
#   the macro-defined URL if it exists,
#   or the wiki page where this object was defined
sub getURL {
    my $self = shift;
    # if this Entity isn't actually defined, we shouldn't have a URL
    return undef
        unless ($self->isDefined());
    return ($self->url())
        if ($self->url());
    return Foswiki::Func::getViewUrl($self->web(), $self->topic()) .
        $self->getAnchorRef();
}


# Get a formatted wiki link for this Entity
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::Entity
#   object reference (implicit using -> syntax).
# @param[in] $macroAttrs a Foswiki::Attrs object reference containing
#   the parameters for the macro being processed.
sub getWikiLink {
    my ($self,
        $macroAttrs,
        $entitySpec) = @_;
    my $label = $self->name();
    my $savedSubID = $self->subid();
    # set the sub ID for rendering, if desired
    $self->setSubID($entitySpec->subid())
        if (defined($entitySpec));
    if (defined($macroAttrs->{'label'})) {
        if ($macroAttrs->{'label'} eq "id") {
            $label = $self->id();
        } elsif ($macroAttrs->{'label'} eq "spec") {
            $label = $self->getMacroSpec();
        } elsif ($macroAttrs->{'label'} eq "aspec") {
            $label = $self->getAbbrevMacroSpec();
        } elsif ($macroAttrs->{'label'} eq "topic") {
            $label = $self->topic();
        }
    }
    # restore original sub-id
    $self->setSubID($savedSubID);
    return $label unless ($self->isDefined());
    return "[[" . $self->getURL() . "][" . $label . "]]";
}


1;
