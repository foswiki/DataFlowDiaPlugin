# $Id: //foswiki-dfd/rel2_0_1/lib/Foswiki/Plugins/DataFlowDiaPlugin/DataTransport.pm#4 $

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

---+ package Foswiki::Plugins::DataFlowDiaPlugin::DataTransport

Class for storing information about associated data type and transport
pairs.  Used by Process.

=cut

package Foswiki::Plugins::DataFlowDiaPlugin::DataTransport;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec;
use Foswiki::Plugins::DataFlowDiaPlugin::ProcessTransport;
use Foswiki::Plugins::DataFlowDiaPlugin::Util qw(:error :debug);
use Foswiki::Plugins::DataFlowDiaPlugin::PackageConsts qw(:etypes :dirs);

################################
# CONSTRUCTORS
################################

# Create a new DataTransport object from wiki macro text.
#
# @param[in] $class The name of the class being instantiated.
# @param[in] $defaultWeb The Wiki web to use if one is not explicitly
#   specified in the data or transport macro specs.
# @param[in] $dataMacroSpec a DataType macro spec (may include transport).
# @param[in] $xportMacroVal the value for a transport over-ride
#   specified in the DFDPROC macro (e.g. value of inxport).
# @param[in] $dir the direction of the edge from the process to this
#   data type (see DocManager).
# @param[in] $docManager DocManager object reference (for building
#   cross-references)
#
# @return a reference to a DataTransport object.
sub new {
    my ($class,
        $defaultWeb,
        $dataMacroSpec,
        $xportMacroVal,
        $dir,
        $docManager) = @_;

    # We start out with $dataMacroSpec, which will have as a bare
    # minimum the name of the DataType.
    # Optional additional information:
    #   Transport macro spec as part of the DataType macro spec.
    #   Transport macro spec specified as inxport/outxport/inoutxport for the
    #     PROC definition ($xportMacroVal, may be undef)
    my ($dataEntitySpec, $dataEntity) = $docManager->getEntityFromMacroSpec(
        $ENTITYTYPE_DATA,
        $defaultWeb, $dataMacroSpec);
    # $dataEntitySpec and $dataEntity are both defined at this point

    # Now get our transport.
    # This may be either
    #   1) The transport sepcified as part of the DataType macro spec, which
    #      at this point will be stored in $dataEntitySpec.
    #   2) The PROC-level transport macro spec as stored in $xportMacroVal.
    #   3) The transport used by the DataType itself, stored in $dataEntity.
    my ($xportEntitySpec, $xportEntity, $inherited) = getXportEntity(
        $defaultWeb, $dataMacroSpec, $dataEntitySpec, $dataEntity,
        $xportMacroVal, $docManager);

    my $macroSpec = $dataEntitySpec->spec() . "#"
        . $dataEntitySpec->flags() . "#" . $xportEntitySpec->spec();
    my $entitySpec = Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->new(
        $macroSpec, $defaultWeb);

    my $self = {
        'data'            => $dataEntity,
        'dataMacroSpec'   => $dataEntitySpec->spec(),
        'dataEntitySpec'  => $dataEntitySpec,
        'dataFlags'       => $dataEntitySpec->flags(),
        'xport'           => $xportEntity,
        # The transport can potentially change as the documents are
        # loaded, so it's a bit dangerous to use the specs as defined
        # here... so be extremely careful.
        'xportMacroSpec'  => $xportEntitySpec->spec(),
        'xportEntitySpec' => $xportEntitySpec,
        'xportInherited'  => $inherited,        
        'macroSpec'       => $macroSpec,
        'entitySpec'      => $entitySpec,
        'dir'             => $dir
    };

    return bless ($self, $class);
}


# Create a new DataTransport object from an XML::LibXML::Element.
#
# @param[in] $class The name of the class being instantiated
# @param[in] $xmlElem an XML::LibXML::Element object containing a
#   DataTransport definition.
# @param[in] $docManager DocManager object reference (for building
#   cross-references)
#
# @return a reference to a DataTransport object.
sub newXML {
    my ($class,
        $xmlElem,
        $dir,
        $docManager) = @_;

    my ($dataEntitySpec, $dataEntity) = $docManager->getEntityFromXML(
        $ENTITYTYPE_DATA,
        $xmlElem);

    # The above call should have stored the Transport EntitySpec into
    # dataEntitySpec, so use that for searching.
    my ($xportEntitySpec, $xportEntity, $inherited);
    if ($dataEntitySpec->xpid() eq "DEFAULT") {
        # use the DataType's transport
        ($xportEntitySpec, $xportEntity) = $dataEntity->getTransport();
        $inherited = 1;
    } else {
        # use the Transport specified in the XML with the DataType
        $xportEntity = $docManager->getEntity(
            $ENTITYTYPE_XPORT,
            $dataEntitySpec->xpweb(),
            $dataEntitySpec->xpid());
        $xportEntitySpec = $dataEntitySpec->deref();
        $inherited = 0;
    }

    my $macroSpec = $dataEntitySpec->spec() . "#"
        . $dataEntitySpec->flags() . "#" . $xportEntitySpec->spec();
    my $entitySpec = Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->new(
        $macroSpec, $dataEntitySpec->web());

    my $self = {
        'data'            => $dataEntity,
        'dataMacroSpec'   => $dataEntitySpec->spec(),
        'dataEntitySpec'  => $dataEntitySpec,
        'dataFlags'       => $dataEntitySpec->flags(),
        'xport'           => $xportEntity,
        # The transport can potentially change as the documents are
        # loaded, so it's a bit dangerous to use the specs as defined
        # here... so be extremely careful.
        'xportMacroSpec'  => $xportEntitySpec->spec(),
        'xportEntitySpec' => $xportEntitySpec,
        'xportInherited'  => $inherited,
        'macroSpec'       => $macroSpec,
        'entitySpec'      => $entitySpec,
        'dir'             => $dir
    };

    return bless ($self, $class);
}

################################
# XML PROCESSING
################################

# Create an XML::LibXML::Element representing this DataTransport.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DataTransport
#   object reference (implicit using -> syntax).
# @param[in] $elementName the name of the XML element representing the
#   DataTransport.
# @param[in] $inclInh when saving data to disk, inherited elements
#   (e.g. data transport) are intentionally not saved.  For searches,
#   the inherited information is desired.  Set $inclInh to a non-zero
#   value when the inherited information is desired.
#
# @return an XML::LibXML::Element representing this DataTransport.
sub toXML {
    my ($self,
        $elementName,
        $inclInh) = @_;
    # start with a reference to the data type
    my $rv = $self->{'data'}->toXMLRef(
        $elementName, $self->{'dataMacroSpec'}, $inclInh);
    $rv->setAttribute("flags", $self->{'dataFlags'})
        if ($self->{'dataFlags'});
    # It is generally OK to use the xportMacroSpec here because it
    # would only have changed when the transport itself is inherited
    # from the DataType.
    my $xportXMLElem = undef;
    if ($inclInh || !$self->isXportInherited())
    {
        # Don't set a xport child node if the data type default is being used.
        $xportXMLElem = $self->{'xport'}->toXMLRef(
            "xport", $self->{'xportMacroSpec'}, $inclInh);
    }
    if ($inclInh && !defined($xportXMLElem)) {
        my $fakeMacroSpec = $self->{'xport'}->getMacroSpec();
        $xportXMLElem = $self->{'xport'}->toXMLRef(
            "xport", $fakeMacroSpec, $inclInh);
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

sub dataEntity         { return $_[0]->{'data'}; }
sub dataMacroSpec      { return $_[0]->{'dataMacroSpec'}; }
sub dataEntitySpec     { return $_[0]->{'dataEntitySpec'}; }
sub dataInstance       { return $_[0]->{'data'}->instance(); }
sub setDataInstance    { $_[0]->{'data'}->setInstance($_[1]); }
sub dataInstanceNum    { return $_[0]->{'data'}->instanceNum(); }
sub setDataInstanceNum { $_[0]->{'data'}->setInstanceNum($_[1]); }
sub dataSubID          { return $_[0]->{'data'}->subid(); }
sub setDataSubID       { $_[0]->{'data'}->setSubID($_[1]); }
sub xportEntity        { return $_[0]->{'xport'}; }
sub xportEntitySpec    { return $_[0]->{'xportEntitySpec'}; }
sub xportSubID         { return $_[0]->{'xport'}->subid(); }
sub setXportSubID      { $_[0]->{'xport'}->setSubID($_[1]); }
sub isXportInherited   { return $_[0]->{'xportInherited'}; }
sub entitySpec         { return $_[0]->{'entitySpec'}; }
sub dir                { return $_[0]->{'dir'}; }
sub setDir             { $_[0]->{'dir'} = $_[1]; }
sub isReverse          { return $_[0]->{'dataFlags'} =~ /r/; }

sub xportMacroSpec {
    my ($self) = @_;
    return $self->{'xport'}->getMacroSpec()
        if ($self->{'xportInherited'});
    return $self->{'xportMacroSpec'};
}


sub macroSpec {
    my ($self) = @_;
    if ($self->{'xportInherited'}) {
        return $self->{'dataMacroSpec'} . "#" .
            $self->{'dataFlags'} . "#" .
            $self->{'xport'}->getMacroSpec();
    }
    return $self->{'macroSpec'};
}


# Get a hashing key for this DataTransport
sub getHashKey {
    my ($self,
        $oneInstance) = @_;
    my $rv = "";
    if ($self->{'xportInherited'}) {
        if ($oneInstance) {
            $rv = $self->dataEntitySpec()->macroSpecDefSub() . "." .
                $self->{'xport'}->getMacroSpec();
        } else {
            $rv = $self->{'dataMacroSpec'} . "." .
                $self->{'xport'}->getMacroSpec();
        }
    } else {
        if ($oneInstance) {
            $rv = $self->entitySpec()->macroSpecDefSub();
        } else {
            $rv = $self->{'macroSpec'};
        }
    }
    return $rv if ($oneInstance);
    return "$rv." . $self->{'dir'};
}

# Return non-zero if the process entity in this DataTransport would be
# the target of an edge from the DataType.
sub isProcTarget {
    my ($self) = @_;
    if ($self->isReverse()) {
        return $self->dir() == $DIR_FWD;
    }
    return $self->dir() == $DIR_BACK;
}


# Set the transport associated with this DataTransport.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DataTransport
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
    $self->{'xportEntitySpec'} = $xportEntitySpec;
    # it is assumed that this sub will only be used when the transport
    # is inherited
    $self->{'xportInherited'} = 1;
}



################################
# DATA MANAGEMENT
################################


# Associate a process with this DataTransport (i.e. provide a reverse
# cross-reference) for I/O.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DataTransport
#   object reference (implicit using -> syntax).
# @param[in] $procEntity a Foswiki::Plugins::DataFlowDiaPlugin::Process
#   object reference utilizing this DataType.
# @param[in] $dataParamName the internal (to DataType) hash key
#   storing the cross reference (e.g. "consumers").
sub addProcess {
    my ($self,
        $procEntity,
        $dataParamName) = @_;
    my $pt = Foswiki::Plugins::DataFlowDiaPlugin::ProcessTransport->new(
        $procEntity,
        $self);
    $self->{'data'}->addProcess($pt, $dataParamName);
    if (!$self->{'xportInherited'}) {
        # only associate if the transport is specified by the process
        # definition, rather than inheriting it from the data type
        # definition.
        $self->{'xport'}->addProcess($procEntity);
    }
}


# Determine if this DataTransport matches another EntitySpec.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DataTransport
#   object reference (implicit using -> syntax).
# @param[in] $dtEntitySpec a Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec
#   for another DataTransport to match against.
#
# @return true if the DataTransports match (includes checking against DEFAULT).
sub matchDataTransport {
    my ($self,
        $dtEntitySpec) = @_;
    return $self->entitySpec()->match($dtEntitySpec);
}


################################
# GRAPHVIZ PROCESSING
################################

# Returns a graphviz edge from $procEntity to $self->{'data'}.
# If $procEntity2 is defined, the edge is drawn between $procEntity
# and $procEntity2 instead.
#
# @param[in] $self A Foswiki::Plugins::DataFlowDiaPlugin::DataTransport
#   object reference (implicit using -> syntax).
# @param[in] $procEntity A Foswiki::Plugins::DataFlowDiaPlugin::Process
#   connected to this DataTransport.
# @param[in] $procEntity A Foswiki::Plugins::DataFlowDiaPlugin::Process
#   connected to $procEntity to use in place of the DataType.
# @param[in] $noSubID If true, any sub-IDs in the DataType will be ignored.
# @param[in] $dataInstNum an instance number for the DataType.
#
# @return Graphviz text representing the desired edge.
sub getDotEdge {
    my ($self,
        $procEntity,
        $procEntity2,
        $noSubID,
        $dataInstNum) = @_;
    my $rv = "";
    my $origDataInstNum = $self->dataInstanceNum();
    my $origDataSubID = $self->dataSubID();
    my $origXportSubID = $self->xportSubID();
    # SMELL do we need to set the instance name here as well, as in
    # renderDataNode?
    $self->setDataInstanceNum($dataInstNum);
    if ($noSubID) {
        $self->setDataSubID("DEFAULT");
    } else {
        $self->setDataSubID($self->dataEntitySpec()->subid());
    }
    # always use the sub ID for transport edge labels
    $self->setXportSubID($self->xportEntitySpec()->subid());
    my $reverse = $self->isReverse();

    my $srcEntity = $procEntity || $self->dataEntity();
    my $tgtEntity = $procEntity2 || $self->dataEntity();

    if ($self->dir() == $DIR_BOTH) {
        # bidirectional arrow, only reverse the color pair, not the arrow itself
        $rv = $self->{'xport'}->getDotEdge(
            $srcEntity,
            $tgtEntity,
            0,
            "dir=\"both\", color=\""
            . ($reverse ? "red:black" : "black:red") . "\"");
    } elsif ($self->isProcTarget()) {
        $rv = $self->{'xport'}->getDotEdge(
            $tgtEntity,
            $srcEntity,
            $reverse);
    } else {
        $rv = $self->{'xport'}->getDotEdge(
            $srcEntity,
            $tgtEntity,
            $reverse);
    }

    $self->setDataInstanceNum($origDataInstNum);
    $self->setDataSubID($origDataSubID);
    $self->setXportSubID($origXportSubID);

    return $rv;
}


# Returns a graphviz node for the DataType Entity.
#
# @param[in] $self A Foswiki::Plugins::DataFlowDiaPlugin::DataTransport
#   object reference (implicit using -> syntax).
# @param[in] $instanceName an instance name for the DataType
#   (typically the locale pair macro spec for the connecting
#   processes).
# @param[in] $instanceNum an instance number for the DataType.
# @param[in] $noSubID If true, any sub-IDs in the DataType will be ignored.
#
# @return Graphviz text representing the DataType node.
sub renderDataNode {
    my ($self,
        $instanceName,
        $instanceNum,
        $noSubID) = @_;
    my $origInstNum = $self->dataInstanceNum();
    my $origSubID = $self->dataSubID();
    $self->setDataInstanceNum($instanceNum);
    $self->setDataInstance($instanceName);
    my $es = $self->dataEntitySpec();
    if ($noSubID) {
        $self->setDataSubID("DEFAULT");
    } else {
        $self->setDataSubID($es->subid());
    }
    # undef because we shouldn't need any macroAttrs here
    my $rv = $self->{'data'}->renderGraph(undef, $es);
    $self->setDataInstanceNum($origInstNum);
    $self->setDataSubID($origSubID);
    return $rv;
}


################################
# UTILITY SUBS
################################

# Get a transport entity, possibly using the entity associated with
# the data type.
#
# @param[in] $defaultWeb The Wiki web to use if one is not explicitly
#   specified in the transport macro specs ($xportMacroVal).
# @param[in] $dataMacroSpec a DataType macro spec (may include transport).
# @param[in] $dataEntitySpec The EntitySpec for $dataEntity.
# @param[in] $dataEntity The DataType Entity whose transport
#   definition will be used as a fall-back.
# @param[in] $xportMacroVal the value for a transport over-ride
#   specified in the DFDPROC macro (e.g. value of inxport).
# @param[in] $docManager DocManager object reference (for building
#   cross-references)
#
# @return a list:
#   transport EntitySpec
#   Transport Entity object reference
#   boolean, true if the transport was inherited from the DataType defintion
sub getXportEntity {
    my ($defaultWeb,
        $dataMacroSpec,
        $dataEntitySpec,
        $dataEntity,
        $xportMacroVal,
        $docManager) = @_;
    my $xportEntity;
    my $xportEntitySpec;
    my $xportMacroSpec = "DEFAULT";
    my $xportInherited = 0;
    # use this to determine whether a transport was specified in the
    # data macro spec
    my $macroES = Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->new(
        $dataMacroSpec, $defaultWeb);
    if ($macroES->xpid() ne "DEFAULT") {
        # transport reference is specified with the data type reference
        $xportEntitySpec = $dataEntitySpec->deref();
        $xportEntity = $docManager->getEntity(
            $ENTITYTYPE_XPORT,
            $xportEntitySpec->web(),
            $xportEntitySpec->id());
    } elsif (defined($xportMacroVal)) {
        # transport reference is specified across the I/O path
        $xportEntitySpec =
            Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->new(
                $xportMacroVal, $defaultWeb);
        $xportEntity = $docManager->getEntity(
            $ENTITYTYPE_XPORT,
            $xportEntitySpec->web(),
            $xportEntitySpec->id());
    } else {
        # just use the data type's transport, which might be "DEFAULT"
        ($xportEntitySpec, $xportEntity) = $dataEntity->getTransport();
        $xportInherited = 1;
    }
    undef $macroES;

    return ($xportEntitySpec, $xportEntity, $xportInherited)
}


1;
