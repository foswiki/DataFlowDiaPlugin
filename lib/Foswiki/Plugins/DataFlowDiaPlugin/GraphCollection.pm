# $Id: //foswiki-dfd/rel2_0_1/lib/Foswiki/Plugins/DataFlowDiaPlugin/GraphCollection.pm#2 $

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

---+ package Foswiki::Plugins::DataFlowDiaPlugin::GraphCollection

Defines a class for collecting the Entity objects and the connections
between them, as well as rendering the collection.

=cut

package Foswiki::Plugins::DataFlowDiaPlugin::GraphCollection;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use Foswiki::Plugins::DataFlowDiaPlugin::Util qw(:graphviz :set :debug);
use Foswiki::Plugins::DataFlowDiaPlugin::GraphEdge;
use Foswiki::Plugins::DataFlowDiaPlugin::PackageConsts qw(:etypes :dirs);

################################
# CONSTRUCTOR
################################

# Create a new GraphCollection object.
#
# @param[in] $class The name of the class being instantiated
# @param[in] $defGraph True if this GraphCollection represents an
#   Entity definition, i.e. DFDPROC, DFDDATA.
#
# @return a reference to an GraphCollection object
sub new {
    my ($class,
        $defGraph) = @_;
    my $self = {
        # Contains Process Entity data organized by locale.
        # key: locale macro spec / value: hash
        #    key: 'entity' / value: locale entity
        #    key: 'processes' / value: hash
        #       key: process macro spec / value: process entity
        #    key: 'procCount' / value: unsigned
        #    key: 'instnum' / value: hash
        #       key: process macro spec / value: process instance num (unsigned)
        # set by: addProcess()
        'locproc'     => {},

        # Contains a hash of Process Entity object references, used to
        # prevent inifinite loops.
        # key: process macro spec / value: 1
        'process'     => {},

        # Contains a set of metadata for edges between Process nodes.
        # key: GraphEdge::getHashKey() / value: GraphEdge
        # set by: addDataLeaf(), addEdge()
        'edges'       => {},

        # Contains a set of metadata for edges between Process and
        # DataType nodes. Should not overlap with 'edges', which
        # contains metadata regarding process-to-process edges that
        # includes data, i.e. these edges may have either one process
        # or none at all.
        # key: locale macro spec / value: hash
        #    key: DataTransport::getHashKey() / value: GraphEdge
        # set by: addDataLeaf(), addEdge()
        'data'        => {},

        # Contains a look-up table for instance numbers of DataType nodes.
        # key: data macro spec / value: unsigned
        # set by: addDataLeaf()
        'dataInstNum' => {},

        # Contains an HTML anchor to be included at the beginning of
        # the rendered output of this GraphCollection.
        # value: text
        # set by: setAnchor()
        'anchor'      => undef,

        # value: bool
        # If non-zero, this is a definition graph and is treated
        # somewhat specially.
        'defGraph'    => $defGraph,

        # Indentation level for dot output.
        # value: unsigned
        # set by: indent()
        'indent'      => 0
    };
    return bless ($self, $class);
}


################################
# ACCESSORS
################################

# set the HTML anchor tag for the rendered output
sub setAnchor { $_[0]->{'anchor'} = $_[1]; }


# Indentation isn't strictly necessary but it does make the output a
# hell of a lot easier to read when debugging.
sub indent {
    my ($self,
        $collapse) = @_;
    if ($collapse) { $self->{'indent'} -= 3; }
    else { $self->{'indent'} += 3; }
}

sub indentStr { return " " x $_[0]->{'indent'}; }

sub hasProcess {
    my ($self,
        $procEntity) = @_;
    return $self->{'process'}->{ $procEntity->getMacroSpec() };
}

sub setProcess {
    my ($self,
        $procEntity) = @_;
    $self->{'process'}->{ $procEntity->getMacroSpec() } = 1;
}

################################
# DATA MANAGEMENT
################################

# Add a Process Entity to be rendered as part of this GraphCollection.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::GraphCollection
#   object reference (implicit using -> syntax).
# @param[in] $localeMacroSpec The macro spec of the locale as
#   specified by the DFDPROC macro used to define $procEntity.
# @param[in] $localeEntity The Locale Entity object referred to by
#   $localeMacroSpec and where $procEntity is a resident and will be
#   rendered if locale rendering is requested.
# @param[in] $procEntity The Process Entity object to be added.
# @param[in] $incCount If true, a new graphviz node instance will be
#   created when rendering $procEntity.
sub addProcess {
    my ($self,
        $localeMacroSpec,
        $localeEntity,
        $procEntity,
        $incCount) = @_;
    $self->{'locproc'}->{$localeMacroSpec}->{'entity'} = $localeEntity;
    my $procKey = $procEntity->getMacroSpec();
    $self->{'locproc'}->{$localeMacroSpec}->{'processes'}->{$procKey} =
        $procEntity;
    if ($incCount) {
        $self->{'locproc'}->{$localeMacroSpec}->{'procCount'}->{$procKey}++;
    } else {
        $self->{'locproc'}->{$localeMacroSpec}->{'procCount'}->{$procKey} = 1;
    }
    $self->{'locproc'}->{$localeMacroSpec}->{'instnum'}->{$procKey} =
        $self->{'locproc'}->{$localeMacroSpec}->{'procCount'}->{$procKey};
}


# Add an edge to this GraphCollection between a DataType node and a
# single Process node, or add a DataType node with no connecting
# edges.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::GraphCollection
#   object reference (implicit using -> syntax).
# @param[in] $localeEntity A Locale Entity used by $procEntity, or a
#   DEFAULT - determines where the DataType node and Process node are
#   rendered.
# @param[in] $procEntity A Process Entity connected to the DataType (or undef).
# @param[in] $dataTransport A DataTransport object reference defining
#   the DataType to be added as a leaf node, and the transport used by
#   $procEntity or the transport used by the data type (which may be
#   DEFAULT).
# @param[in] $oneInstance If zero, a new instance of the graphviz node
#   for the DataType will be added to the rendered graph.
sub addDataLeaf {
    my ($self,
        $localeEntity,
        $procEntity,
        $dataTransport,
        $oneInstance) = @_;
    my $srcProc = undef;
    my $tgtProc = undef;
    my $srcDT = undef;
    my $tgtDT = undef;

    # _debugWrite("GraphCollection::addDataLeaf(self, " . (defined($localeEntity) ? $localeEntity->id() : "undef") . ", " . (defined($procEntity) ? $procEntity->id() : "undef") . ", " . $dataTransport->macroSpec());

    # edge should go from process to data node UNLESS DIR=BACK
    if ($dataTransport->isProcTarget()) {
        $tgtProc = $procEntity;
        $tgtDT = $dataTransport;
    } else {
        $srcProc = $procEntity;
        $srcDT = $dataTransport;
    }
    my $edge = Foswiki::Plugins::DataFlowDiaPlugin::GraphEdge->new(
        $localeEntity,
        $srcProc,
        $srcDT,
        $localeEntity,
        $tgtProc,
        $tgtDT,
        $oneInstance);
    my $key = $edge->getHashKey();
    my $dtkey = $dataTransport->getHashKey($oneInstance);
    my $lockey = $localeEntity->getMacroSpec();
    my $datakey;
    if ($oneInstance) {
        # because there will be only one instance of this data node in
        # the graph, ignore the sub ID, which is also ignored for the
        # same reason elsewhere (GraphEdge, DataType, etc.)
        $datakey = $dataTransport->dataEntitySpec()->macroSpecDefSub() . "#"
            . $lockey;
    } else {
        $datakey = $dataTransport->dataMacroSpec() . "#" . $lockey;
    }
    $self->{'edges'}->{$key} = $edge;
    $self->{'data'}->{$lockey}->{$dtkey} = $edge;
    $edge->setDataInstanceNum(++$self->{'dataInstNum'}->{$datakey})
        unless ($oneInstance);
    if (defined($procEntity)) {
        my $prockey = $procEntity->getMacroSpec();
        if ($dataTransport->isProcTarget()) {
            $edge->setToProcInstanceNum(
                $self->{'locproc'}->{$lockey}->{'instnum'}->{$prockey});
        } else {
            $edge->setFromProcInstanceNum(
                $self->{'locproc'}->{$lockey}->{'instnum'}->{$prockey});
        }
    }
}


# Add an edge to this GraphCollection between two Process nodes.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::GraphCollection
#   object reference (implicit using -> syntax).
# @param[in] $localeEntity1 The Locale Entity where $procEntity1 is to
#   be rendered as part of this particular edge.
# @param[in] $procEntity1 The Process Entity to be rendered as a node
#   on one side of this edge.
# @param[in] $dataTransport1 The DataTransport defined as part of
#   $procEntity1 that connects to $procEntity2.
# @param[in] $localeEntity2 The Locale Entity where $procEntity2 is to
#   be rendered as part of this particular edge.
# @param[in] $procEntity2 The Process Entity to be rendered as a node
#   on one side of this edge.
# @param[in] $dataTransport2 The DataTransport defined as part of
#   $procEntity2 that connects to $procEntity1.
# @param[in] dir The direction of the edge from $procEntity1 to $procEntity2.
sub addEdge {
    my ($self,
        $localeEntity1,
        $procEntity1,
        $dataTransport1,
        $localeEntity2,
        $procEntity2,
        $dataTransport2,
        $dir) = @_;

    # _debugWrite(
    #     "GraphCollection::addEdge(self, " . 
    #     (defined($localeEntity1) ? $localeEntity1->id() : "undef") . ", " .
    #     (defined($procEntity1) ? $procEntity1->id() : "undef") . ", " .
    #     (defined($dataTransport1) ? $dataTransport1->macroSpec() : "undef") .
    #     ", " .
    #     (defined($localeEntity2) ? $localeEntity2->id() : "undef") . ", " .
    #     (defined($procEntity2) ? $procEntity2->id() : "undef") . ", " .
    #     (defined($dataTransport2) ? $dataTransport2->macroSpec() : "undef") .
    #     ", $dir)");

    my ($edge, $fromLoc, $fromProc, $fromDT, $toLoc, $toProc, $toDT);
    if ($dir == $DIR_BACK) {
        $fromLoc  = $localeEntity2;
        $fromProc = $procEntity2;
        $fromDT   = $dataTransport2;
        $toLoc    = $localeEntity1;
        $toProc   = $procEntity1;
        $toDT     = $dataTransport1;
    } else {
        $fromLoc  = $localeEntity1;
        $fromProc = $procEntity1;
        $fromDT   = $dataTransport1;
        $toLoc    = $localeEntity2;
        $toProc   = $procEntity2;
        $toDT     = $dataTransport2;
    }
    $edge = Foswiki::Plugins::DataFlowDiaPlugin::GraphEdge->new(
        $fromLoc, $fromProc, $fromDT, $toLoc, $toProc, $toDT);
    my $key = $edge->getHashKey();
    $self->{'edges'}->{$key} = $edge;
    # Use a hash key of the one locale if 1 and 2 are the same locale,
    # which enables us to easily add data nodes in the appropriate
    # subgraphs.
    my $fromLocMacroSpec = $fromLoc->getMacroSpec();
    my $toLocMacroSpec = $toLoc->getMacroSpec();
    my $lockey = ($fromLocMacroSpec eq $toLocMacroSpec ?
                   $fromLocMacroSpec :
                   $fromLocMacroSpec . "#" . $toLocMacroSpec);
    # macro specs for dataTransport1 and dataTransport2 SHOULD BE THE SAME
    my $dtkey = $dataTransport1->macroSpec();
    $self->{'data'}->{$lockey}->{$dtkey} = $edge;

    if (defined($fromProc)) {
        my $pkey = $fromProc->getMacroSpec();
        my $lkey = $fromLoc->getMacroSpec();
        $edge->setFromProcInstanceNum(
            $self->{'locproc'}->{$lkey}->{'instnum'}->{$pkey});
    }
    if (defined($toProc)) {
        my $pkey = $toProc->getMacroSpec();
        my $lkey = $toLoc->getMacroSpec();
        $edge->setToProcInstanceNum(
            $self->{'locproc'}->{$lkey}->{'instnum'}->{$pkey});
    }
}


################################
# TEXT PROCESSING
################################

# Private rendering function of this GraphCollection for text output.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::GraphCollection
#   object reference (implicit using -> syntax).
# @param[in] $macroAttrs the parameters for the macro being processed,
#   mapping attribute id to value.
# @param[in] $ignoreLocales TODO document this
# @param[in] $docManager DocManager object reference (for building
#   cross-references)
sub renderText {
    my ($self,
        $macroAttrs,
        $ignoreLocales,
        $docManager) = @_;
    my $rv = "";
    my ($storeClass, $procStore) =
        $docManager->newStore(
            $ENTITYTYPE_PROC);
    my $identityspec = $macroAttrs->{'identityspec'}->spec();
    # store the matched processes into a SimpleStore
    foreach my $localeMacroSpec (sort keys %{ $self->{'locproc'} }) {
        my $localeInfo = $self->{'locproc'}->{$localeMacroSpec};
        foreach my $procMacroSpec (sort keys %{ $localeInfo->{'processes'} }) {
            # skip the "origin" entity, if requested
            next if (($macroAttrs->{'printself'} == 0) &&
                     ($procMacroSpec eq $identityspec));
            $procStore->storeEntity(
                $localeInfo->{'processes'}->{$procMacroSpec});
        }
    }
    # Turn all the matches into XML for rendering as text
    my @matches = $procStore->findnodes(
        "/" . $procStore->{'rootName'} . "/" . $procStore->{'nodeName'});
    $rv .= $docManager->renderMatchText($macroAttrs, \@matches);
    
    return $rv;
}


################################
# GRAPHVIZ PROCESSING
################################

# Top-level rendering function for this GraphCollection - this is what
# should be called by external objects.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::GraphCollection
#   object reference (implicit using -> syntax).
# @param[in] $macroAttrs the parameters for the macro being processed,
#   mapping attribute id to value.
# @param[in] $ignoreLocales TODO document this
# @param[in] $docManager DocManager object reference (for building
#   cross-references)
sub render {
    my ($self,
        $macroAttrs,
        $ignoreLocales,
        $docManager) = @_;
    my $rv = "";
    $rv .= $self->{'anchor'} . " "
        if ($self->{'anchor'});
    if (defined($macroAttrs->{'format'})) {
        $rv .= $self->renderText($macroAttrs, $ignoreLocales, $docManager);
    } else {
        $rv .= $self->renderGraph($macroAttrs, $ignoreLocales, $docManager);
    }
    return $rv;
}


# Private rendering function of this GraphCollection for graphical output.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::GraphCollection
#   object reference (implicit using -> syntax).
# @param[in] $macroAttrs the parameters for the macro being processed,
#   mapping attribute id to value.
# @param[in] $ignoreLocales TODO document this
# @param[in] $docManager DocManager object reference (for building
#   cross-references)
sub renderGraph {
    my ($self,
        $macroAttrs,
        $ignoreLocales,
        $docManager) = @_;
    my $rv = "";
    my $localeMacroSpec;
    my $dotText = "";
    # This collects the keys of 'data' objects that were rendered as
    # part of subgraph clusters to prevent them from being rendered
    # again in the data node rendering section.
    my %drawnDataTransports = ();
    # eval {
    #     local $Data::Dumper::Sortkeys = sub { my ($hash) = @_; return [ grep !/^docMgr$/, sort keys %$hash ]; };
    #     local $Data::Dumper::Maxdepth = 5;
    #     local $Data::Dumper::Indent = 1;
    #     _debugWrite("renderGraph");
    #     _debugDump([ $self ]);
    # };
    $self->indent();
    foreach $localeMacroSpec (sort keys %{ $self->{'locproc'} }) {
        my $localeInfo = $self->{'locproc'}->{$localeMacroSpec};
        my $localeEntity = $localeInfo->{'entity'};
        my $nn = $localeEntity->getGraphvizInstance();
        $dotText .= $self->renderLocaleClusterTop(
            $macroAttrs,
            $ignoreLocales,
            $localeMacroSpec,
            $localeEntity,
            $nn,
            \%drawnDataTransports);

        $dotText .= $self->renderLocaleProcesses(
            $macroAttrs,
            $localeInfo,
            $nn);

        $dotText .= $self->renderLocaleClusterBottom(
            $macroAttrs,
            $localeEntity);
    }

    $dotText .= $self->renderUndrawnDataNodes(
        $macroAttrs, $ignoreLocales, \%drawnDataTransports);

    $dotText .= $self->renderEdges($macroAttrs, $ignoreLocales);

    $self->indent(1);

    if ($dotText) {
        $rv .= genDotStart(
            $macroAttrs->{'file'},
            $macroAttrs->{'graphlabel'})
            . $dotText
            . genDotEnd();
    }
    return $rv;
}


# Private rendering function of this GraphCollection for graphical
# output.  Generates the opening Graphviz text for the subgraph for
# Locales if requested, as well as the DataType node definitions that
# belong within that subgraph.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::GraphCollection
#   object reference (implicit using -> syntax).
# @param[in] $macroAttrs the parameters for the macro being processed,
#   mapping attribute id to value.
# @param[in] $ignoreLocales TODO document this
# @param[in] $localeMacroSpec The macro spec for the locale being
#   rendered as a subgraph.
# @param[in] $localeEntity The Locale Entity object reference for the
#   locale being rendered as a subgraph.
# @param[in] $locInstName The Locale's Graphviz-friendly instance name
#   for naming the subgraph.
# @param[out] $drawnDataTransports A hash reference where the locale
#   macro specs are stored when DataType nodes are rendered as part of
#   the subgraph.  Used to prevent duplicated rendering of DataType
#   nodes in inappropriate/incorrect locations.
#
# @return Graphviz text for the beginning portion of the Locale subgraph.
sub renderLocaleClusterTop {
    my ($self,
        $macroAttrs,
        $ignoreLocales,
        $localeMacroSpec,
        $localeEntity,
        $locInstName,
        $drawnDataTransports) = @_;
    my $rv = "";


    if ($macroAttrs->{'nolocales'} || ($localeEntity->id() eq "DEFAULT")) {
        return "";
    }

    $rv .= $self->indentStr()
        .  "subgraph cluster_$locInstName {\n";
    $self->indent();
    $rv .= $self->indentStr()
        .  "graph [ label=\""
        . $localeEntity->getDotLabel()
        . "\" ]\n";

    # render data nodes in this locale if data nodes are requested
    if (($macroAttrs->{'datanodes'}) &&
        defined($self->{'data'}->{$localeMacroSpec})) {
        my $graphEdgeHash = $self->{'data'}->{$localeMacroSpec};
        foreach my $dtkey (sort keys %{ $graphEdgeHash }) {
            $rv .= $self->indentStr()
                . $graphEdgeHash->{$dtkey}->renderDataNode($ignoreLocales)
                . "\n";
        }
        # don't render the data nodes for this locale again.
        $drawnDataTransports->{$localeMacroSpec} = 1;
    }

    return $rv;
}


# Private rendering function of this GraphCollection for graphical
# output.  Generates the closing Graphviz text for the subgraph for
# Locales if requested.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::GraphCollection
#   object reference (implicit using -> syntax).
# @param[in] $macroAttrs the parameters for the macro being processed,
#   mapping attribute id to value.
# @param[in] $localeEntity The Locale Entity object reference for the
#   locale being rendered as a subgraph.
#
# @return Graphviz text for the ending portion of the Locale subgraph.
sub renderLocaleClusterBottom {
    my ($self,
        $macroAttrs,
        $localeEntity) = @_;
    return ""
        if ($macroAttrs->{'nolocales'} || ($localeEntity->id() eq "DEFAULT"));
    $self->indent(1);
    return $self->indentStr() . "}\n";
}


# Private rendering function of this GraphCollection for graphical
# output.  Generates the Process node Graphviz text for processes
# within a given Locale, regardless of whether Locale clustering is
# enabled.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::GraphCollection
#   object reference (implicit using -> syntax).
# @param[in] $macroAttrs the parameters for the macro being processed,
#   mapping attribute id to value.
# @param[in] $localeInfo A specific member (per Locale) of
#   $self->{'locproc'} whose Process Entities are to be rendered.
# @param[in] $procInstName The instance name for this process being
#   rendered, which is the Locale Graphviz instance name.
#
# @return Graphviz text for the Process nodes in the given Locale.
sub renderLocaleProcesses {
    my ($self,
        $macroAttrs,
        $localeInfo,
        $procInstName) = @_;
    my $rv = "";
    my %macroAttrsCopy = %{ $macroAttrs };
    # Make sure the Entity's renderGraph doesn't do
    # anything unnecessary, like subgraphs and recursion.
    $macroAttrsCopy{'nolocales'} = 1;
    $macroAttrsCopy{'level'} = 0;
    foreach my $procKey (sort keys %{ $localeInfo->{'processes'} }) {
        my $procEntity = $localeInfo->{'processes'}->{$procKey};
        my $nodeCount = $localeInfo->{'procCount'}->{$procKey};
        # Always use the locale node name. "nolocales" is
        # about rendering - if we don't use unique names we'll
        # end up rendering graphs that have edges that don't
        # actually exist.
        $procEntity->setInstance($procInstName);
        $procEntity->resetInstanceNum();
        foreach my $i (1..$nodeCount) {
            $rv .= $self->indentStr()
                .  $procEntity->renderGraph(\%macroAttrsCopy)
                .  "\n";
            $procEntity->addInstanceNum();
        }
        $procEntity->resetInstanceNum();
    }
    return $rv;
}


# Private rendering function of this GraphCollection for graphical
# output.  Generates the opening Graphviz text for the DataType nodes
# that are part of this GraphCollection that are not present in
# Locales listed in $drawnDataTransports.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::GraphCollection
#   object reference (implicit using -> syntax).
# @param[in] $macroAttrs the parameters for the macro being processed,
#   mapping attribute id to value.
# @param[in] $ignoreLocales TODO document this
# @param[in] $drawnDataTransports A hash reference where keys are the
#   locale macro specs whose DataType nodes have already been rendered
#   and thus should not be rendered by this sub.
#
# @return Graphviz text for the DataType nodes.
sub renderUndrawnDataNodes {
    my ($self,
        $macroAttrs,
        $ignoreLocales,
        $drawnDataTransports) = @_;
    my $rv = "";
    if ($macroAttrs->{'datanodes'}) {
        foreach my $localeMacroSpec (sort keys %{ $self->{'data'} }) {
            # skip already rendered data nodes
            next if defined($drawnDataTransports->{$localeMacroSpec});
            my $graphEdgeHash = $self->{'data'}->{$localeMacroSpec};
            foreach my $dtkey (sort keys %{ $graphEdgeHash }) {
                $rv .= $self->indentStr()
                    . $graphEdgeHash->{$dtkey}->renderDataNode($ignoreLocales)
                    . "\n";
            }
        }
    }
    return $rv;
}


# Private rendering function of this GraphCollection for graphical
# output.  Generates the opening Graphviz text for all edges between
# nodes in this GraphCollection.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::GraphCollection
#   object reference (implicit using -> syntax).
# @param[in] $macroAttrs the parameters for the macro being processed,
#   mapping attribute id to value.
# @param[in] $ignoreLocales TODO document this
#
# @return Graphviz text for the edges.
sub renderEdges {
    my ($self,
        $macroAttrs,
        $ignoreLocales) = @_;
    my @allEdges =();
    my $rv = "";
    foreach my $edgeKey (sort keys %{ $self->{'edges'} }) {
        push @allEdges, $self->{'edges'}->{$edgeKey}->getEdges(
            $macroAttrs, $ignoreLocales);
    }
    if (@allEdges) {
        $rv .= $self->indentStr()
            . join("\n" . $self->indentStr(), unique(@allEdges))
            . "\n";
    }
    return $rv;
}

1;
