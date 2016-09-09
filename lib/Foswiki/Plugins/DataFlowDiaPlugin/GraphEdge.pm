# $Id: //foswiki-dfd/rel2_0_1/lib/Foswiki/Plugins/DataFlowDiaPlugin/GraphEdge.pm#2 $

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

---+ package Foswiki::Plugins::DataFlowDiaPlugin::GraphEdge

Defines a class for collecting the Entity objects and the connections
between them, as well as rendering the collection.

=cut

package Foswiki::Plugins::DataFlowDiaPlugin::GraphEdge;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use Foswiki::Plugins::DataFlowDiaPlugin::Util qw(:debug);
use Foswiki::Plugins::DataFlowDiaPlugin::PackageConsts qw(:dirs);

################################
# CONSTRUCTOR
################################

# Create a new GraphEdge object.
#
# @param[in] $class The name of the class being instantiated
# @param[in] $localeEntity1 The Locale Entity object reference where
#   $procEntity1 resides.  Must not be undef.  If $procEntity1 is
#   undef, this should be the same as $localeEntity2.
# @param[in] $procEntity1 A Process Entity object reference that emits
#   data as defined in $dataTransport1 to be consumed by
#   $dataTransport2.  May be undef in the case of a data leaf (i.e. a
#   data type that is either consumed or produced by a process, but no
#   matching process produces or consumes that data).
# @param[in] $dataTransport1 The DataTransport object reference for
#   the data produced or consumed by $procEntity1 for this data flow
#   edge.
# @param[in] $localeEntity2 The Locale for $procEntity2.
# @param[in] $procEntity2 The Process Entity object for the other side
#   of this edge.
# @param[in] $dataTransport2 The DataTransport for $procEntity2
#   matching $procEntity1/$dataTransport1.
# @param[in] $singleDataInstance Under most rendering circumstances,
#   multiple data node instances for a given DataType will be rendered
#   for input and output of a given process.  If non-zero, only one
#   node instance will be rendered.  Used for DFDDATA diagrams,
#   typically.
#
# @return a reference to an GraphEdge object
sub new {
    my ($class,
        $localeEntity1,
        $procEntity1,
        $dataTransport1,
        $localeEntity2,
        $procEntity2,
        $dataTransport2,
        $singleDataInstance) = @_;

    # _debugWrite(
    #     "GraphEdge::new($class, " . 
    #     (defined($localeEntity1) ? $localeEntity1->id() : "undef") . ", " .
    #     (defined($procEntity1) ? $procEntity1->id() : "undef") . ", " .
    #     (defined($dataTransport1) ? $dataTransport1->macroSpec() : "undef") .
    #     ", " .
    #     (defined($localeEntity2) ? $localeEntity2->id() : "undef") . ", " .
    #     (defined($procEntity2) ? $procEntity2->id() : "undef") . ", " .
    #     (defined($dataTransport2) ? $dataTransport2->macroSpec() : "undef") .
    #     ", " . (defined($singleDataInstance) ? $singleDataInstance : "undef") .
    #     ")");
    #_debugStack();

    my $self = {
        'from_locale'    => $localeEntity1,
        'from_proc'      => $procEntity1,
        'from_dataxport' => $dataTransport1,
        'to_locale'      => $localeEntity2,
        'to_proc'        => $procEntity2,
        'to_dataxport'   => $dataTransport2,
        'singleDataInst' => $singleDataInstance,
        'dataInstNum'    => 1,
        'from_instnum'   => 1,
        'to_instnum'     => 1
    };
    return bless($self,$class);
}


################################
# ACCESSORS
################################

sub setDataInstanceNum     { $_[0]->{'dataInstNum'} = $_[1]; }

sub fromLocaleEntity       { return $_[0]->{'from_locale'}; }
sub fromProcEntity         { return $_[0]->{'from_proc'}; }
sub fromProcInstanceNum    { return $_[0]->{'from_instnum'}; }
sub setFromProcInstanceNum { $_[0]->{'from_instnum'} = $_[1]; }
sub fromDataXport          { return $_[0]->{'from_dataxport'}; }
sub fromLocaleMacroSpec
{
    my $le = $_[0]->fromLocaleEntity();
    return (defined($le) ? $le->getMacroSpec() : undef);
}
sub fromProcMacroSpec
{
    my $pe = $_[0]->fromProcEntity();
    return (defined($pe) ? $pe->getMacroSpec() : undef);
}
sub fromXportEntity
{
    my $dt = $_[0]->fromDataXport();
    return (defined($dt) ? $dt->xportEntity() : undef);
}
sub fromXportEntitySpec
{
    my $dt = $_[0]->fromDataXport();
    return (defined($dt) ? $dt->xportEntitySpec() : undef);
}
sub fromDataEntity
{
    my $dt = $_[0]->fromDataXport();
    return (defined($dt) ? $dt->dataEntity() : undef);
}
sub fromDataXportHash
{
    my $dt = $_[0]->fromDataXport();
    return (defined($dt) ? $dt->getHashKey() : undef);
}

# Sets the instance name of the "from" node's DataType Entity.
sub setFromDataInstance
{
    my ($self, $instanceName) = @_;
    my $de = $self->fromDataEntity();
    if (defined($de)) {
        $de->setInstance($instanceName);
    }
}

sub toLocaleEntity       { return $_[0]->{'to_locale'}; }
sub toProcEntity         { return $_[0]->{'to_proc'}; }
sub toProcInstanceNum    { return $_[0]->{'to_instnum'}; }
sub setToProcInstanceNum { $_[0]->{'to_instnum'} = $_[1]; }
sub toDataXport          { return $_[0]->{'to_dataxport'}; }
sub toLocaleMacroSpec
{
    my $le = $_[0]->toLocaleEntity();
    return (defined($le) ? $le->getMacroSpec() : undef);
}
sub toProcMacroSpec
{
    my $pe = $_[0]->toProcEntity();
    return (defined($pe) ? $pe->getMacroSpec() : undef);
}
sub toXportEntity
{
    my $dt = $_[0]->toDataXport();
    return (defined($dt) ? $dt->xportEntity() : undef);
}
sub toXportEntitySpec
{
    my $dt = $_[0]->toDataXport();
    return (defined($dt) ? $dt->xportEntitySpec() : undef);
}
sub toDataEntity
{
    my $dt = $_[0]->toDataXport();
    return (defined($dt) ? $dt->dataEntity() : undef);
}
sub toDataXportHash
{
    my $dt = $_[0]->toDataXport();
    return (defined($dt) ? $dt->getHashKey() : undef);
}

# Sets the instance name of the "to" node's DataType Entity.
sub setToDataInstance
{
    my ($self, $instanceName) = @_;
    my $de = $self->toDataEntity();
    if (defined($de)) {
        $de->setInstance($instanceName);
    }
}


# Get a hashing key for this GraphEdge
sub getHashKey {
    my ($self) = @_;
    my $fromProcSpec = $self->fromProcMacroSpec() || "nil";
    my $toProcSpec = $self->toProcMacroSpec() || "nil";
    my $fromDataXportHash = $self->fromDataXportHash() || "nil";
    my $toDataXportHash = $self->toDataXportHash() || "nil";
    return 
        $self->fromLocaleMacroSpec() . "." .
        $fromProcSpec . "." .
        $self->toLocaleMacroSpec() . "." .
        $toProcSpec . "." .
        $fromDataXportHash . "." .
        $toDataXportHash;
}


# Get the Graphviz edges represented by this GraphEdge object.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::GraphEdge
#   object reference (implicit using -> syntax).
# @param[in] $macroAttrs a Foswiki::Attrs object reference containing
#   the parameters for the macro being processed.
# @param[in] $ignoreLocales TODO document this
#
# @return A list of Graphviz edge definitions (1 or 2).
sub getEdges {
    my ($self,
        $macroAttrs,
        $ignoreLocales) = @_;
    my @rv;
    # to_proc OR from_proc may be undef if this edge represents a data leaf
    # from/to_locale should ALWAYS be defined
    if (defined($self->fromProcEntity())) {
        $self->fromProcEntity()->setInstance(
            $self->fromLocaleEntity()->getGraphvizInstance());
        $self->fromProcEntity()->setInstanceNum($self->fromProcInstanceNum());
    }
    if (defined($self->toProcEntity())) {
        $self->toProcEntity()->setInstance(
            $self->toLocaleEntity()->getGraphvizInstance());
        $self->toProcEntity()->setInstanceNum($self->toProcInstanceNum());
    }
    if ($macroAttrs->{'datanodes'}) {
        my $instanceName = $self->getDataInstanceName($ignoreLocales);
        my $dataXport = $self->getRenderDataXport();
        # data instance is now combined locale to locale
        $self->setFromDataInstance($instanceName);
        if (defined($self->fromProcEntity())) {
            my $fromProc =
                ($dataXport == $self->fromDataXport()
                 ? $self->fromProcEntity()
                 : undef);
            my $toProc =
                ($dataXport == $self->fromDataXport()
                 ? undef
                 : $self->fromProcEntity());
            push @rv, $dataXport->getDotEdge(
                $fromProc, $toProc,
                $self->{'singleDataInst'}, $self->{'dataInstNum'});
        }
        $self->setToDataInstance($instanceName);
        if (defined($self->toProcEntity())) {
            my $fromProc =
                ($dataXport == $self->toDataXport()
                 ? $self->toProcEntity()
                 : undef);
            my $toProc =
                ($dataXport == $self->toDataXport()
                 ? undef
                 : $self->toProcEntity());
            push @rv, $dataXport->getDotEdge(
                $fromProc, $toProc,
                $self->{'singleDataInst'}, $self->{'dataInstNum'});
        }
    } else {
        if (defined($self->fromProcEntity()) &&
            defined($self->toProcEntity())) {
            push @rv, $self->fromDataXport()->getDotEdge(
                $self->fromProcEntity(),
                $self->toProcEntity(),
                0,
                $self->{'dataInstNum'});
        }
    }
    return @rv;
}


# Get the Graphviz node representing the DataType Entity in this
# GraphEdge object.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::GraphEdge
#   object reference (implicit using -> syntax).
# @param[in] $ignoreLocales TODO document this
#
# @return A Graphviz node definition.
sub renderDataNode { 
    my ($self,
        $ignoreLocales) = @_;
    my $instanceName = $self->getDataInstanceName($ignoreLocales);
    # data instance is now combined locale to locale
    # This edge should only have one data node.  Pick one based on
    # 1) Whether it's defined (obvious)
    # 2) Whether a sub ID is specified (less obvious). Assuming the
    #    code is correct, the sub IDs can either be both DEFAULT, one
    #    DEFAULT and the other non-DEFAULT, or both non-DEFAULT *but
    #    the same sub ID*.
    #    Simplifying, the sub IDs can be the same, or different if one
    #    of the sub IDs is "DEFAULT".
    my $dataXport = $self->getRenderDataXport();
    return $dataXport->renderDataNode(
        $instanceName,
        $self->{'dataInstNum'},
        $self->{'singleDataInst'});
}


# Get the Graphviz-friendly instance name of the DataType Entity in
# this GraphEdge object.  This is the combination of the two Locale
# Entity instance names.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::GraphEdge
#   object reference (implicit using -> syntax).
# @param[in] $ignoreLocales TODO document this
#
# @return A Graphviz-friendly name for this DataType node.
sub getDataInstanceName {
    my ($self,
        $ignoreLocales) = @_;
    my $fxes = $self->fromXportEntitySpec();
    my $txes = $self->toXportEntitySpec();
    my $fromXportStr = "DEFAULT_DEFAULT_DEFAULT";
    if (defined($fxes)) { $fromXportStr = $fxes->getGraphvizInstance() }
    elsif (defined($txes)) { $fromXportStr = $txes->getGraphvizInstance() }
    my $toXportStr = "DEFAULT_DEFAULT_DEFAULT";
    if (defined($txes)) { $toXportStr = $txes->getGraphvizInstance() }
    elsif (defined($fxes)) { $toXportStr = $fxes->getGraphvizInstance() }
    my $rv =
        $self->fromLocaleEntity()->getGraphvizInstance() . "_" .
        $fromXportStr . "_" .
        $self->toLocaleEntity()->getGraphvizInstance() . "_" .
        $toXportStr;
    # BUG this probably fails to take locale sub-IDs into account
    return $rv;
}


# Get the appropriate DataTransport Entity to use for graphs.
# DataType entities with sub-IDs will always take precedence.
sub getRenderDataXport {
    my ($self) = @_;
    my $fdx = $self->fromDataXport();
    my $tdx = $self->toDataXport();
    if (defined($fdx) && defined($tdx)) {
        my $fes = $fdx->dataEntitySpec();
        my $tes = $tdx->dataEntitySpec();
        if (($fes->subid() eq $tes->subid()) || ($fes->subid() eq "DEFAULT")) {
            # "from" is default sub ID, use "to"
            # or the sub ID is the same in which case it doesn't matter
            return $tdx;
        } else {
            # "to" sub ID should be DEFAULT, so use "from"
            return $fdx;
        }
    } elsif (defined($fdx)) {
        return $fdx;
    } else {
        return $tdx;
    }
}

1;
