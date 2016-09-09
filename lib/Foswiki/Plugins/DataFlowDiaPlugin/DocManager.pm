# $Id: //foswiki-dfd/rel2_0_1/lib/Foswiki/Plugins/DataFlowDiaPlugin/DocManager.pm#2 $

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

---+ package Foswiki::Plugins::DataFlowDiaPlugin::DocManager

Defines a class for managing the various metadata documents for
DataFlowDiaPlugin.

=cut

package Foswiki::Plugins::DataFlowDiaPlugin::DocManager;

# Always use strict to enforce variable scoping
use strict;
use warnings;
use vars qw(@EXPORT_OK);

require Exporter;
*import = \&Exporter::import;

use Foswiki::Plugins::DataFlowDiaPlugin::SimpleStore;
use Foswiki::Plugins::DataFlowDiaPlugin::Transport;
use Foswiki::Plugins::DataFlowDiaPlugin::Locale;
use Foswiki::Plugins::DataFlowDiaPlugin::DataType;
use Foswiki::Plugins::DataFlowDiaPlugin::Process;
use Foswiki::Plugins::DataFlowDiaPlugin::Group;
use Foswiki::Plugins::DataFlowDiaPlugin::Util qw(:error :debug :set);
use Foswiki::Plugins::DataFlowDiaPlugin::PackageConsts qw(:lookup :etypes :dirs);


################################
# CONSTRUCTORS
################################


# Create a new Foswiki::Plugins::DataFlowDiaPlugin::DocManager instance.
#
# @param[in] $class The name of the class being instantiated
#
# @return a reference to a DocManager object
sub new {
    my ($class) = @_;
    my $self = {
        'stores'    => {}, # hash to SimpleStore instances, key is entity type
        'cgraphNum' => {}, # hash from base file name to count for CONNECT
        'graphNum'  => 0   # graph number for DirectedGraphPlugin file names
    };
    return bless ($self, $class);
}


################################
# MACRO PROCESSING
################################

# Pre-process entity definition macros.  Returns either the original
# macro text on successful processing (so that the macro may be
# re-processed for rendering), or a wiki error message on failure.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DocManager
#   object reference (implicit using -> syntax).
# @param[in] $web the name of the web in the current CGI query.
# @param[in] $topic the name of the topic in the current CGI query.
# @param[in] $entityType the stripped name of the macro ("%", "DFD"
#   and "{...}" removed)
# @param[in] $macroAttrs the parameters for the macro being processed,
#   mapping attribute id to value.
#
# @return Text that will be substituted by the plug-in handler into
#   the processed topic, which may contain an error message.
sub addMacroData {
    my ($self,
        $web,
        $topic,
        $entityType,
        $macroAttrs) = @_;
    my $storeClass = $LOOKUP_ENTITY{$entityType}[0];
    my $rv;

    eval {
        $self->loadDocs($web, $topic);
        $rv = $self->getStore($storeClass)->addMacroData(
            $web, $topic, $macroAttrs);
    };
    if (ref($@)) {
        $rv = macroError("Error while processing macro: " . $@->message());
    } elsif ($@) {
        $rv = macroError("Error while processing macro: " . $@);
    }

    return $rv;
}


# Render plug-in macros.  Returns either the appropriate wiki text
# (which may result in a graph), or a wiki error message on failure.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DocManager
#   object reference (implicit using -> syntax).
# @param[in] $web the name of the web in the current CGI query.
# @param[in] $topic the name of the topic in the current CGI query.
# @param[in] $macroName the stripped name of the macro ("%", "DFD" and
#   "{...}" removed).
# @param[in] $macroAttrs the parameters for the macro being processed,
#   mapping attribute id to value.
#
# @return Text that will be substituted by the plug-in handler into
#   the processed topic, which may contain an error message.
sub renderMacro {
    my ($self,
        $web,
        $topic,
        $macroName,
        $macroAttrs) = @_;
    my $rv = "";
    eval { 
        $self->loadDocs($web, $topic);
        if ($macroName =~ /^(PROC|DATA|TRANSPORT|LOCALE|GROUP)$/) {
            $rv = $self->renderDefn($web, $topic, $macroName, $macroAttrs);
        } elsif ($macroName eq "SEARCH") {
            $rv = $self->search($macroAttrs);
        } elsif ($macroName eq "CONNECT") {
            $rv = $self->connect($web, $topic, $macroAttrs);
        } else {
            $rv = "%PURPLE% hello from renderMacro %ENDCOLOR%\n\n";
        }
    };
    if (ref($@)) {
        $rv = macroError("Error while processing macro: " . $@->message());
    } elsif ($@) {
        $rv = macroError("Error while processing macro: " . $@);
    }
    $self->{'graphNum'}++;
    return $rv;
}


# Return an Entity object reference for the given Entity Type and macro spec.
# @see getEntity
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DocManager
#   object reference (implicit using -> syntax).
# @param[in] $entityType the entity type (see $...EntityType variables
#   above) whose data is to be created or retrieved.
# @param[in] $defaultWeb The name of the web to use to find the Entity
#   in the event the macro spec does not specify a web.
# @param[in] $macroSpec The macro spec for the desired Entity.
#
# @return an Entity object reference.
sub getEntityFromMacroSpec {
    my ($self,
        $entityType,
        $defaultWeb,
        $macroSpec) = @_;
    # entitySpec as defined here can result in incorrect web names for
    # the transport.
    my $entitySpec =
        Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->new(
            $macroSpec, $defaultWeb);
    my $storeClass = $LOOKUP_ENTITY{$entityType}[0];
    my $entity = $self->getStore($storeClass)->getEntity(
        $entitySpec->web(), $entitySpec->id());
    undef $entitySpec;
    # reacquire the entity spec from the entity itself to make sure
    # everything is correct.
    my $xport = undef;
    $xport = $entity->getTransport()
        if ($entity->can("getTransport"));
    $entitySpec =
        Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->newEntity(
            $entity, $xport, $macroSpec);
    return ($entitySpec, $entity);
}


################################
# XML PROCESSING
################################

# Return an Entity object reference corresponding to the given XML Element.
# @see getEntity
# @see EntitySpec::newXML
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DocManager
#   object reference (implicit using -> syntax).
# @param[in] $entityType the entity type (see $...EntityType variables
#   above) whose data is to be created or retrieved.
# @param[in] $xmlElem an XML::LibXML::Element object containing at
#   a bare minimum, the "id" and "web" attributes.
#
# @return an Entity object reference.
sub getEntityFromXML {
    my ($self,
        $entityType,
        $xmlElem) = @_;
    my $entitySpec =
        Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->newXML(
            $xmlElem);
    my $storeClass = $LOOKUP_ENTITY{$entityType}[0];
    my $entity = $self->getStore($storeClass)->getEntity(
        $entitySpec->web(), $entitySpec->id());
    return ($entitySpec, $entity);
}


# Execute an XPath search through all data stores.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DocManager
#   object reference (implicit using -> syntax).
# @param[in] $query an XPath 1.0 expression.
#
# @return a list of matching XML::LibXML::Element object references.
sub findnodes {
    my ($self,
        $query) = @_;
    my @rv = ();

    foreach my $storeClass (keys %{ $self->{'stores'} }) {
        push @rv, $self->getStore($storeClass)->findnodes($query);
    }
    return @rv;
}


# Walk through ancestor tree until we find out what type this data is.
#
# @param[in] $xmlElem The XML::LibXML::Element object reference whose
#   Entity Type is to be determined.
# @return an Entity Type string as defined above.
sub getEntityTypeFromXML {
    my ($xmlElem) = @_;
    FAIL("getEntityTypeFromXML called with undefined element")
        unless defined($xmlElem);
    my $rv = "";
    # get the entity type using the document type
    my $ownerDoc = $xmlElem->ownerDocument;
    my $root = $ownerDoc->documentElement();
    my $parentET;
    FAIL("no root hash for " . $root->nodeName)
        unless defined($LOOKUP_ROOT{$root->nodeName});
    $parentET = $LOOKUP_ROOT{$root->nodeName};
    my $storeClass = $LOOKUP_ENTITY{$parentET}[0];
    $rv = $storeClass->getEntityTypeFromXML($xmlElem);

    # referencing top-level (below root) XML nodes
    if (!defined($rv) && defined($LOOKUP_NODE{$xmlElem->nodeName})) {
        $rv = $LOOKUP_NODE{$xmlElem->nodeName};
    }

    return $rv;
}


# Used by map in _subAttrsXML to get the appropriate value from query results.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DocManager
#   object reference (implicit using -> syntax).
# @param[in] $xmlElem an XML::LibXML object reference to be rendered
#   as text.  Expected to be an Attr or Element object reference.
#
# @return a string containing a useful text representation of $xmlElem.
sub mappingFunctionXML {
    my ($self,
        $xmlElem,
        $macroAttrs) = @_;
    if ($xmlElem->isa("XML::LibXML::Attr")) {
        return $xmlElem->value;
    }
    if ($xmlElem->isa("XML::LibXML::Element") &&
        $xmlElem->hasAttribute("id") &&
        $xmlElem->hasAttribute("web")) {
        my $et = getEntityTypeFromXML($xmlElem);
        if (defined($et)) {
            my ($entitySpec, $entity) = $self->getEntityFromXML(
                $et,
                $xmlElem);
            my $rv = "";
            $rv .= "<"
                . $Foswiki::Plugins::DataFlowDiaPlugin::deprecatedMarkup . ">"
                if ($xmlElem->getAttribute("deprecated"));
            $rv .= $entity->getWikiLink($macroAttrs, $entitySpec);
            $rv .= "</"
                . $Foswiki::Plugins::DataFlowDiaPlugin::deprecatedMarkup . ">"
                if ($xmlElem->getAttribute("deprecated"));
            return $rv;
        } else {
            return $xmlElem->toString(0);
        }
    }
    return $xmlElem;
}


# Create a substitution mapping for text results of macros where the
# desired substitution expression is XPath.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DocManager
#   object reference (implicit using -> syntax).
# @param[in] $xmlElem an XML::LibXML object reference being rendered
#   as text.  Expected to be an Attr or Element object reference.
# @param[in] $macroAttrs the parameters for the macro being processed,
#   mapping attribute id to value.
# @param[in] $xpathExpr The XPath 1.0 expression to be getting values
#   for in the resulting substitution mapping.
# @param[out] $substArr an array of values, in text, matching $xpathExpr.
#
# @return a token string that will be temporarily substituted in the
#   text being formatted in place of the values in $substArr.
sub _substAttrsXML {
    my ($self,
        $xmlElem,
        $macroAttrs,
        $xpathExpr,
        $substArr) = @_;
    # _debugWrite("_substAttrsXML() $xpathExpr");
    my @matches = $xmlElem->findnodes($xpathExpr);
    # _debugWrite("hit:\n" . $_->toString(2)) foreach (@matches);
    my @rv = unique(map { mappingFunctionXML($self,$_,$macroAttrs) } @matches);
    if (scalar(@rv) == 1) {
        return $rv[0]
            if ($macroAttrs->{'aggregate'});
        push(@{ $substArr }, $rv[0]);
        return "~SUBSTATTRSXML" . $#{ $substArr } . "~";
    }
    return join($macroAttrs->{'newline'}, @rv)
        if ($macroAttrs->{'aggregate'});
    # Push an anonymous reference to the array rather than the array
    # itself. For multiple results.
    push(@{ $substArr }, [ @rv ]);
    return "~SUBSTATTRSXML" . $#{ $substArr } . "~";
}


################################
# ACCESSORS
################################

sub stores    { return $_[0]->{'stores'}; }
sub cgraphNum { return $_[0]->{'cgraphNum'}; }
sub graphNum  { return $_[0]->{'graphNum'}; }
# Get the hash keys of the SimpleStore for the given $entityType.
sub getHashKeys {
    my ($self,
        $entityType) = @_;
    my $storeClass = $LOOKUP_ENTITY{$entityType}[0];
    return $self->getStore($storeClass)->getHashKeys();
}


# Get the SimpleStore object reference for the given Entity class/package name.
sub getStore {
    my ($self,
        $storeClass) = @_;
    return $self->{'stores'}->{$storeClass};
}

# Get the SimpleStore object reference for the given Entity Type.
sub getEntityStore {
    my ($self,
        $entityType) = @_;
    return $self->getStore($LOOKUP_ENTITY{$entityType}[0]);
}

################################
# DATA MANAGEMENT
################################

# Loads the data store for the given entity type into internal
# storage, unless the data has already been loaded.  If there is no
# file to load, a new empty document/store is created (which will not
# be updated on disk until this object is destroyed).
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DocManager
#   object reference (implicit using -> syntax).
# @param[in] $entityType the entity type (see $...EntityType variables
#   above) whose data store is to be loaded
# @param[in] $web the name of the web in the current CGI query.
# @param[in] $topic the name of the topic in the current CGI query.
sub loadDoc {
    my ($self,
        $entityType,
        $web,
        $topic) = @_;
    FAIL("loadDoc passed unknown entityType \"$entityType\"\n")
        unless defined($LOOKUP_ENTITY{$entityType});

    my ($storeClass, $simpleStore) = $self->newStore($entityType);
    unless (defined($self->{'stores'}->{$storeClass})) {
        $self->{'stores'}->{$storeClass} = $simpleStore;
        $simpleStore->loadFile($web, $topic);
    }
    undef $simpleStore;
}


# Load the data store for all Entity Types.
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DocManager
#   object reference (implicit using -> syntax).
# @param[in] $web the name of the web in the current CGI query.
# @param[in] $topic the name of the topic in the current CGI query.
sub loadDocs {
    my ($self,
        $web,
        $topic) = @_;
    # only load once per session
    _debugWrite("loadDocs 1");
    return if (%{ $self->{'stores'} });
    _debugWrite("loadDocs 2");
    foreach my $i (@ENTITY_PROC_ORDER) {
        $self->loadDoc($i, $web, $topic);
    }
}


# Save the data store for all Entity Types to disk.
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DocManager
#   object reference (implicit using -> syntax).
sub saveDocs {
    my ($self) = @_;

    foreach my $storeClass (keys %{ $self->{'stores'} }) {
        $self->getStore($storeClass)->saveFile();
    }
}


# Determine if any entity definitions have been removed.
sub checkForRemoved {
    my ($self) = @_;

    foreach my $storeClass (keys %{ $self->{'stores'} }) {
        $self->getStore($storeClass)->checkForRemoved();
    }
}


# Create an unpopulated internal store for the given entity type.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DocManager
#   object reference (implicit using -> syntax).
# @param[in] $entityType the entity type (see $...EntityType variables
#   above) whose data store is to be loaded
sub newStore {
    my ($self,
        $entityType) = @_;
    my $storeClass = $LOOKUP_ENTITY{$entityType}[0];
    my $rootName   = $LOOKUP_ENTITY{$entityType}[1];
    my $nodeName   = $LOOKUP_ENTITY{$entityType}[2];
    # _debugWrite("DocManager::newStore $self " . ref($self));
    # my ($dbgPackage, $dbgFilename, $dbgLine) = caller;
    # _debugWrite("  caller $dbgPackage $dbgFilename:$dbgLine");
    my $ss = Foswiki::Plugins::DataFlowDiaPlugin::SimpleStore->new(
        $storeClass, $rootName, $nodeName, $entityType, $self);
    return ($storeClass, $ss);
}


# Return an Entity object reference for the given web and ID.  This
# may be an Entity that has not (yet) been defined using wiki macros.
# As it is an object reference, the Entity object will be filled in as
# information about it becomes available through macros, though this
# typically only happens when a new entity is defined via macros for
# the first time.
#
# @note The return value is not simply an Entity object reference, but
# an object reference to one of the child classes,
# e.g. Foswiki::Plugins::DataFlowDiaPlugin::Process.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DocManager
#   object reference (implicit using -> syntax).
# @param[in] $entityType the entity type (see $...EntityType variables
#   above) whose data is to be created or retrieved.
# @param[in] $web the name of the web where the desired entity is defined.
# @param[in] $id the ID of the desired entity
#
# @return an Entity object reference.
sub getEntity {
    my ($self,
        $entityType,
        $web,
        $id) = @_;
    my $storeClass = $LOOKUP_ENTITY{$entityType}[0];
    my $rv = $self->getStore($storeClass)->getEntity($web, $id);
    return $rv;
}


# Handle the DFDSEARCH macro, which searches through the data stores
# using an XPath expression.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DocManager
#   object reference (implicit using -> syntax).
# @param[in] $macroAttrs the parameters for the macro being processed,
#   mapping attribute id to value.
#
# @return The formatted search result text.
sub search {
    my ($self,
        $macroAttrs) = @_;
    # set defaults
    $macroAttrs->{'aggregate'} = Foswiki::Func::isTrue(
        $macroAttrs->{'aggregate'}, 1);
    $macroAttrs->{'atomempty'} = Foswiki::Func::isTrue(
        $macroAttrs->{'atomempty'}, 0);
    $macroAttrs->{'separator'} = "\$n()"
        unless defined($macroAttrs->{'separator'});
    $macroAttrs->{'newline'} = "<br/>"
        unless defined($macroAttrs->{'newline'});
    $macroAttrs->{'empty'} = ""
        unless defined($macroAttrs->{'empty'});
    $macroAttrs->{'zeroresults'} = 'No results.$n'
        unless defined($macroAttrs->{'zeroresults'});
    $macroAttrs->{'label'} = "name"
        unless defined($macroAttrs->{'label'});
    my $query = $macroAttrs->{'query'} || $macroAttrs->{'_DEFAULT'};
    my $rv = "";
    die("query missing from SEARCH macro\n") unless $query;
    my @matches = $self->findnodes($query);
    $rv .= $self->renderMatchText($macroAttrs, \@matches);
}


# Handle the DFDCONNECT macro, which generates process-to-process
# graphs and text.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DocManager
#   object reference (implicit using -> syntax).
# @param[in] $web the name of the web in the current CGI query.
# @param[in] $topic the name of the topic in the current CGI query.
# @param[in] $macroAttrs the parameters for the macro being processed,
#   mapping attribute id to value.
#
# @return The formatted search result text (Graphviz, wiki mark-up, etc.).
sub connect {
    my ($self,
        $web,
        $topic,
        $macroAttrs) = @_;

    # _debugFuncStart("DocManager::connect() graph=" . $self->{'graphNum'});
    die("missing CONNECT type parameter\n")
        unless $macroAttrs->{'type'};
    die("missing CONNECT id parameter\n")
        unless $macroAttrs->{'id'};
    my $entityType;
    my $graphType = $macroAttrs->{'type'};
    $graphType =~ tr/[a-z]/[A-Z]/;
    if (($graphType eq $ENTITYTYPE_PROC) ||
        ($graphType eq $ENTITYTYPE_DATA)) {
        $entityType = $graphType;
    } elsif ($graphType eq "GROUP") {
        $entityType = $ENTITYTYPE_PROC;
    } elsif ($graphType eq "TRANSLATION") {
        $entityType = $ENTITYTYPE_DATA;
    } else {
        die("Invalid CONNECT type \"$graphType\"\n");
    }

    # provide defaults for rendering
    $macroAttrs->{'dir'} = $DIR_BOTH
        unless (defined($macroAttrs->{'dir'}));
    $macroAttrs->{'level'} = 0
        unless (defined($macroAttrs->{'level'}));
    $macroAttrs->{'datanodes'} = Foswiki::Func::isTrue(
        $macroAttrs->{'datanodes'}, 1);
    $macroAttrs->{'printself'} = Foswiki::Func::isTrue(
        $macroAttrs->{'printself'}, 1);
    $macroAttrs->{'nolocales'} = Foswiki::Func::isTrue(
        $macroAttrs->{'nolocales'}, 1);
    $macroAttrs->{'aggregate'} = Foswiki::Func::isTrue(
        $macroAttrs->{'aggregate'}, 1);
    $macroAttrs->{'atomempty'} = Foswiki::Func::isTrue(
        $macroAttrs->{'atomempty'}, 0);
    $macroAttrs->{'hidedeprecated'} = Foswiki::Func::isTrue(
        $macroAttrs->{'hidedeprecated'}, 0);
    $macroAttrs->{'separator'} = "\$n()"
        unless defined($macroAttrs->{'separator'});
    $macroAttrs->{'newline'} = "<br/>"
        unless defined($macroAttrs->{'newline'});
    $macroAttrs->{'empty'} = ""
        unless defined($macroAttrs->{'empty'});
    $macroAttrs->{'zeroresults'} = 'No results.$n'
        unless defined($macroAttrs->{'zeroresults'});
    $macroAttrs->{'label'} = "name"
        unless defined($macroAttrs->{'label'});
    %{ $macroAttrs->{'locales_hash'} } =
        map { my $es = Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->new($_, $web); $es->spec() => 1 } split(/\s*,\s*/, $macroAttrs->{'locales'})
        if ($macroAttrs->{'locales'});
    %{ $macroAttrs->{'exclocales_hash'} } =
        map { my $es = Foswiki::Plugins::DataFlowDiaPlugin::EntitySpec->new($_, $web); $es->spec() => 1 } split(/\s*,\s*/, $macroAttrs->{'exclocales'})
        if ($macroAttrs->{'exclocales'});

    my $baseFile = "DFD_CONNECT_" . $macroAttrs->{'id'};
    my $cgraphNum = ++$self->{'cgraphNum'}->{$baseFile};
    $macroAttrs->{'file'} = $baseFile . sprintf("_%03d", $cgraphNum);

    my $storeClass = $LOOKUP_ENTITY{$entityType}[0];
    my $rv = "";
    my $ss = $self->getStore($storeClass);
    $ss->clearSearchMeta();
    $rv .= $ss->connect($web, $topic, $macroAttrs, $graphType);
    return $rv;
}


################################
# TEXT PROCESSING
################################


# Format text per macro attributes and a given set of query matches in XML.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DocManager
#   object reference (implicit using -> syntax).
# @param[in] $macroAttrs The parameters for the macro being processed,
#   mapping attribute id to value.
# @param[in] $matches An array reference to XML::LibXML::Element
#   object references to be rendered to text.
#
# @return The formatted search result text (Graphviz, wiki mark-up, etc.).
sub renderMatchText {
    my ($self,
        $macroAttrs,
        $matches) = @_;
    my $separator = $macroAttrs->{'separator'};
    my $format = $macroAttrs->{'format'};
    my $rv = "";
    return Foswiki::Func::decodeFormatTokens($macroAttrs->{'zeroresults'})
        unless (scalar(@{ $matches }));
    $rv = $macroAttrs->{'header'} . $separator if $macroAttrs->{'header'};
    die("'format' missing from macro\n") unless $format;
    foreach my $match (@{ $matches }) {
        my @substArr;
        my $tempo = $format;
        $tempo =~ s/~([^~]*)~/&_substAttrsXML($self, $match, $macroAttrs, $1, \@substArr)/ge;
        # _debugWrite("search result:\n" . $match->toString(2));
        if (@substArr) {
            my $done = 0;
            # sub-array index, i.e. the index of the arrays that are
            # references in @substArr.
            my $subi = 0;
            while (!$done) {
                my $hit = $tempo;
                $done = 1;
                foreach my $i (0..$#substArr) {
                    if (ref($substArr[$i]) eq "ARRAY") {
                        if ($subi <= $#{ $substArr[$i] }) {
                            # we're still giving results, so we're not done
                            $done = 0 if ($subi < $#{ $substArr[$i] });
                            $hit =~ s/~SUBSTATTRSXML$i~/$substArr[$i]->[$subi]/;
                        } else {
                            $hit =~ s/~SUBSTATTRSXML$i~/$macroAttrs->{'empty'}/;
                        }
                    } else {
                        if (($subi == 0) || (!$macroAttrs->{'atomempty'})) {
                            $hit =~ s/~SUBSTATTRSXML$i~/$substArr[$i]/;
                        } else {
                            $hit =~ s/~SUBSTATTRSXML$i~/$macroAttrs->{'empty'}/;
                        }
                    }
                }
                $subi++;
                $rv .= $hit . $separator;
            }
        } else {
            $rv .= $tempo . $separator;
        }
    }
    $rv .= $macroAttrs->{'footer'} . $separator if $macroAttrs->{'footer'};
    return Foswiki::Func::decodeFormatTokens($rv);
}


################################
# GRAPHVIZ PROCESSING
################################


# Render the definition macros (DFDPROC, DFDDATA, DFDTRANSPORT,
# DFDLOCALE, DFDGROUP) as an HTML anchor and possibly graph.
#
# @param[in] $self a Foswiki::Plugins::DataFlowDiaPlugin::DocManager
#   object reference (implicit using -> syntax).
# @param[in] $web the name of the web in the current CGI query.
# @param[in] $topic the name of the topic in the current CGI query.
# @param[in] $macroName the stripped name of the macro ("%", "DFD"
#   and "{...}" removed)
# @param[in] $macroAttrs the parameters for the macro being processed,
#   mapping attribute id to value.
#
# @return An HTML anchor and possibly a Graphviz graph definition for
#   the defined Entity.
sub renderDefn {
    my ($self,
        $web,
        $topic,
        $macroName,
        $macroAttrs) = @_;
    my $storeClass = $LOOKUP_ENTITY{$macroName}[0];

    # These options should be set this way by default for
    # entity-defining macros.
    $macroAttrs->{'dir'} = $DIR_BOTH;
    $macroAttrs->{'level'} = 1;
    $macroAttrs->{'datanodes'} = 1;
    $macroAttrs->{'printself'} = 1;
    $macroAttrs->{'nolocales'} = 1;
    $macroAttrs->{'graphlabel'} = "";
    if ($macroName eq "PROC") {
        $macroAttrs->{'graphlabel'} = $macroAttrs->{'id'} .
            " Process Data Flow";
    } elsif ($macroName eq "DATA") {
        $macroAttrs->{'graphlabel'} = $macroAttrs->{'id'} .
            " Data Type Usage";
    }
    # Unless the user is doing something weird, specifically putting
    # multiple definitions of the same ID Entity on the same topic,
    # this should be fine.
    $macroAttrs->{'file'} = sprintf(
        "DFD_%s_%s",
        $macroName,
        $macroAttrs->{'id'});
    delete $macroAttrs->{'locales'};
    delete $macroAttrs->{'exclocales'};
    delete $macroAttrs->{'format'};
    delete $macroAttrs->{'header'};
    delete $macroAttrs->{'footer'};
    delete $macroAttrs->{'zeroresults'};

    return $self->getStore($storeClass)->renderDefn(
        $web, $topic, $macroAttrs);
    # _debugFile($web, $topic, $macroName . "_" . $self->{'graphNum'}, $rv);
}


1;
